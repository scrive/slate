module Main where

import Control.Concurrent
import Control.Monad
import Data.List
import Data.Version
import Happstack.Server (simpleHTTPWithSocket, nullConf, port, timeout)
import Happstack.StaticRouting
import System.Environment
import System.IO
import qualified Control.Exception as E
import qualified Data.ByteString.Char8 as BS

import AppConf
import AppControl
import AppDB
import Configuration
import Crypto.RNG
import DB
import DB.Checks
import DB.SQLFunction
import DB.PostgreSQL
import Utils.Default
import Utils.IO
import Utils.Network
import RoutingTable
import Templates.TemplatesLoader
import User.Model
import Control.Logic
import qualified Log
import qualified MemCache
import qualified Paths_kontrakcja as Paths
import qualified Static.Resources as SR
import qualified Doc.JpegPages as JpegPages

main :: IO ()
main = Log.withLogger $ do
  -- progname effects where state is stored and what the logfile is named
  hSetEncoding stdout utf8
  hSetEncoding stderr utf8

  Log.server $ "Starting kontrakcja-server build " ++ concat (intersperse "." (versionTags Paths.version))

  appConf <- do
    appname <- getProgName
    args <- getArgs
    readConfig Log.server appname args "kontrakcja.conf"

  -- Generating static resources (JS and CSS). For development this does nothing. For production it generates joins.
  staticResources' <- SR.getResourceSetsForImport (SR.Production <| production appConf |> SR.Development) (srConfig appConf) ""
  staticResources <- case staticResources' of
    Right r -> newMVar r
    Left s -> error $ "Error while generating static resources: " ++ s
  appGlobals <- do
    templates <- newMVar =<< liftM2 (,) getTemplatesModTime readGlobalTemplates
    filecache <- MemCache.new BS.length 50000000
    docs <- MemCache.new JpegPages.pagesCount 1000
    rng <- newCryptoRNGState
    return AppGlobals {
        templates = templates
      , filecache = filecache
      , docscache = docs
      , cryptorng = rng
      , staticResources = staticResources
      }

  withPostgreSQL (dbConfig appConf) $ do
    performDBChecks Log.server kontraTables kontraMigrations
    runDBEnv $ defineMany kontraFunctions

  startSystem appGlobals appConf

startSystem :: AppGlobals -> AppConf -> IO ()
startSystem appGlobals appConf = E.bracket startServer stopServer waitForTerm
  where
    startServer = do
      let (iface,port) = httpBindAddress appConf
      listensocket <- listenOn (htonl iface) (fromIntegral port)
      let (routes,overlaps) = compile staticRoutes
      maybe (return ()) Log.server overlaps
      server <- forkIO $ simpleHTTPWithSocket listensocket (nullConf { port = fromIntegral port, timeout = 120}) (appHandler routes appConf appGlobals)
      return server
    stopServer = killThread
    waitForTerm _ = do
      withPostgreSQL (dbConfig appConf) . runCryptoRNGT (cryptorng appGlobals) $
        initDatabaseEntries $ initialUsers appConf
      waitForTermination
      Log.server $ "Termination request received"

initDatabaseEntries :: (CryptoRNG m, MonadDB m) => [(Email, String)] -> m ()
initDatabaseEntries = mapM_ $ \(email, passwordstring) -> do
  -- create initial database entries
  passwd <- createPassword passwordstring
  maybeuser <- dbQuery $ GetUserByEmail email
  case maybeuser of
    Nothing -> do
      _ <- dbUpdate $ AddUser ("", "") (unEmail email) (Just passwd) Nothing (mkLocaleFromRegion defaultValue)
      return ()
    Just _ -> return () -- user exist, do not add it
