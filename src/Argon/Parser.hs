{-# LANGUAGE CPP #-}
module Argon.Parser (parseCode)
    where

import Control.Monad (void)
#if __GLASGOW_HASKELL__ < 710
import Control.Applicative ((<$>))
#endif
import qualified GHC hiding (parseModule)
import qualified SrcLoc       as GHC
import qualified Lexer        as GHC
import qualified Parser       as GHC
import qualified DynFlags     as GHC
import qualified HeaderInfo   as GHC
import qualified MonadUtils   as GHC
import qualified Outputable   as GHC
import qualified FastString   as GHC
import qualified StringBuffer as GHC
import GHC.Paths (libdir)

import Argon.Preprocess
import Argon.Visitor (funcsCC)
import Argon.Types
import Argon.Utils


-- | Parse the code in the given filename and compute cyclomatic complexity for
--   every function binding.
parseCode :: FilePath  -- ^ The filename corresponding to the source code
          -> IO (FilePath, AnalysisResult)
parseCode file = do
    parseResult <- parseModule file
    let analysis = case parseResult of
                      -- TODO: proper msg
                      Left (span, err) -> Left $ spanToString span ++ " " ++ err
                      Right ast        -> Right $ funcsCC ast
    return (file, analysis)

parseModule :: FilePath -> IO (Either (Span, String) (GHC.Located (GHC.HsModule GHC.RdrName)))
parseModule = parseModuleWithCpp defaultCppOptions

-- | Parse a module with specific instructions for the C pre-processor.
parseModuleWithCpp :: CppOptions
                   -> FilePath
                   -> IO (Either (Span, String) (GHC.Located (GHC.HsModule GHC.RdrName)))
parseModuleWithCpp cppOptions file =
  GHC.defaultErrorHandler GHC.defaultFatalMessager GHC.defaultFlushOut $
    GHC.runGhc (Just libdir) $ do
      dflags <- initDynFlags file
      let useCpp = GHC.xopt GHC.Opt_Cpp dflags
      fileContents <-
        if useCpp
          then getPreprocessedSrcDirect cppOptions file
          else GHC.liftIO $ readFile file
      return $
        case parseFile dflags file fileContents of
          GHC.PFailed ss m -> Left (srcSpanToSpan ss, GHC.showSDoc dflags m)
          GHC.POk _ pmod   -> Right pmod

parseFile :: GHC.DynFlags
          -> FilePath
          -> String
          -> GHC.ParseResult (GHC.Located (GHC.HsModule GHC.RdrName))
parseFile = runParser GHC.parseModule

runParser :: GHC.P a -> GHC.DynFlags -> FilePath -> String -> GHC.ParseResult a
runParser parser flags filename str = GHC.unP parser parseState
    where location   = GHC.mkRealSrcLoc (GHC.mkFastString filename) 1 1
          buffer     = GHC.stringToStringBuffer str
          parseState = GHC.mkPState flags buffer location

initDynFlags :: GHC.GhcMonad m => FilePath -> m GHC.DynFlags
initDynFlags file = do
    dflags0 <- GHC.getSessionDynFlags
    src_opts <- GHC.liftIO $ GHC.getOptionsFromFile dflags0 file
    (dflags1, _, _) <- GHC.parseDynamicFilePragma dflags0 src_opts
    void $ GHC.setSessionDynFlags dflags1
    return dflags1
