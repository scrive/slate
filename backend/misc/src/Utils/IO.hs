module Utils.IO ( checkExecutables
                , readCurl
                , sftpTransfer
                , waitForTermination
                )
where

import Control.Concurrent
import Control.Monad.Base
import Data.Either
import Log
import System.Directory (findExecutable)
import System.Exit
import System.Posix.IO (stdInput)
import System.Posix.Signals
import System.Posix.Terminal (queryTerminal)
import System.Process.ByteString.Lazy (readProcessWithExitCode)
import qualified Data.Aeson.Types as Aeson
import qualified Data.ByteString.Lazy as BSL
import qualified Data.ByteString.Lazy.UTF8 as BSL (toString)
import qualified Data.Text as T

import SFTPConfig

-- | Wait for a signal (sigINT or sigTERM).
waitForTermination :: IO ()
waitForTermination = do
  istty <- queryTerminal stdInput
  mv <- newEmptyMVar
  void $ installHandler softwareTermination (CatchOnce (putMVar mv ())) Nothing
  when istty $ do
    void $ installHandler keyboardSignal (CatchOnce (putMVar mv ())) Nothing
    return ()
  takeMVar mv

curl_exe :: String
curl_exe = "curl"

-- | This function executes curl as external program. Args are args.
readCurl
  :: MonadBase IO m
  => [String]                 -- ^ any arguments
  -> BSL.ByteString           -- ^ standard input
  -> m (ExitCode, BSL.ByteString, BSL.ByteString) -- ^ exitcode, stdout, stderr
readCurl args input = liftBase $
  readProcessWithExitCode curl_exe
  (["--max-time", "60", "-s", "-S"] ++ args) input

sftpTransfer
  :: (MonadBase IO m)
  => SFTPConfig
  -> FilePath
  -> m (ExitCode, BSL.ByteString, BSL.ByteString)
sftpTransfer SFTPConfig{..} filePath = do
  -- We want the directory specified to actually be interpreted as a
  -- directory and not as a file.
  let sftpRemoteDir' = sftpRemoteDir <> if (last sftpRemoteDir /= '/')
                                        then "/" else ""
  readCurl
    (concat [ ["-T", filePath]
            , ["sftp://" <> sftpUser <> ":" <> sftpPassword <> "@" <>
                sftpHost <> sftpRemoteDir']
            ])
    BSL.empty

checkExecutables :: forall m . (MonadLog m, MonadBase IO m, Functor m) => m ()
checkExecutables = logInfo "Checking paths to executables:" . object
                   =<< mapM logFullPathAndVersion
                   =<< checkMissing
                   =<< mapM findExe importantExecutables
  where
    findExe :: (T.Text, [String]) -> m (Either T.Text (T.Text, [String], FilePath))
    findExe (name, options) =
      maybe (Left name) (Right . (name, options,)) <$>
      (liftBase . findExecutable . T.unpack $ name)

    checkMissing :: [Either T.Text (T.Text, [String], FilePath)]
                 -> m [(T.Text, [String], FilePath)]
    checkMissing eithers = do
      let (missing, present) = partitionEithers eithers
      if null missing
        then return present
        else do
        logAttention "Not all important executables are present" $ object [
          "executables" .= missing
          ]
        liftBase exitFailure

    logFullPathAndVersion :: (T.Text, [String], FilePath) -> m Aeson.Pair
    logFullPathAndVersion (name, options, fullpath) | null options
      = return $ name .= fullpath
    logFullPathAndVersion (name, options, fullpath) | otherwise
      = do ver <- liftBase $ readExecutableVersion fullpath options
           return $ name .= (fullpath : lines ver)

    readExecutableVersion :: FilePath -> [String] -> IO String
    readExecutableVersion path options = do
      (_code',stdout',stderr') <-
        readProcessWithExitCode path options (BSL.empty)
      return $ BSL.toString stdout' ++ BSL.toString stderr'

    importantExecutables :: [(T.Text, [String])]
    importantExecutables =
      [ ("java",      ["-version"])
      , ("curl",      ["-V"])
      , ("mutool",    ["-v"])
      , ("pngquant",  ["--version"])
      , ("convert",   ["--version"])
      , ("identify",  ["--version"])
      , ("lessc",     ["-v"])
      , ("gnuplot",   ["--version"])
      , ("pdfdetach", ["-v"])
      , ("qrencode",  ["--version"])
      , ("xmlsec1",   ["--version"])
      ]
