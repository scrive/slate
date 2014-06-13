module Main where

import Control.Concurrent
import Control.Monad
import Happstack.Server hiding (waitForTermination)
import Happstack.StaticRouting
import System.IO
import qualified Control.Exception.Lifted as E
import qualified Data.ByteString.Char8 as BS

import AppConf
import AppControl
import Configuration
import Crypto.RNG
import DB
import DB.PostgreSQL
import DB.Checks
import Utils.Default
import Utils.IO
import Utils.Network
import RoutingTable
import Templates
import User.Model
import User.Email
import Company.Model
import AppDBTables (kontraTables)
import qualified Log
import qualified MemCache
import qualified Version
import qualified Doc.RenderedPages as RenderedPages

main :: IO ()
main = Log.withLogger $ do
  -- progname effects where state is stored and what the logfile is named
  hSetEncoding stdout utf8
  hSetEncoding stderr utf8

  Log.mixlog_ $ "Starting kontrakcja-server build " ++ Version.versionID

  appConf <- do
    readConfig2 Log.mixlog_ "kontrakcja.conf"

  checkExecutables

  let connSettings = pgConnSettings $ dbConfig appConf
  withPostgreSQL (defaultSource connSettings) $
    checkDatabase Log.mixlog_ kontraTables

  appGlobals <- do
    templates <- newMVar =<< liftM2 (,) getTemplatesModTime readGlobalTemplates
    filecache <- MemCache.new BS.length 50000000
    docs <- MemCache.new RenderedPages.pagesCount 1000
    rng <- newCryptoRNGState
    connpool <- createPoolSource connSettings
    return AppGlobals {
        templates = templates
      , filecache = filecache
      , docscache = docs
      , cryptorng = rng
      , connsource = connpool
      }

  startSystem appGlobals appConf

startSystem :: AppGlobals -> AppConf -> IO ()
startSystem appGlobals appConf = E.bracket startServer stopServer waitForTerm
  where
    startServer = do
      let (iface,port) = httpBindAddress appConf
      listensocket <- listenOn (htonl iface) (fromIntegral port)
      routes <- case compile $ staticRoutes (production appConf) of
                  Left e -> do
                    Log.mixlog_ e
                    error "static routing"
                  Right r -> return r
      let conf = nullConf {
            port = fromIntegral port
          , timeout = 120
          , logAccess = Nothing
          }
      forkIO . simpleHTTPWithSocket listensocket conf $ appHandler routes appConf appGlobals
    stopServer = killThread
    waitForTerm _ = do
      withPostgreSQL (connsource appGlobals) . runCryptoRNGT (cryptorng appGlobals) $ do
        initDatabaseEntries $ initialUsers appConf
      waitForTermination
      Log.mixlog_ $ "Termination request received"

initDatabaseEntries :: (CryptoRNG m, MonadDB m) => [(Email, String)] -> m ()
initDatabaseEntries = mapM_ $ \(email, passwordstring) -> do
  -- create initial database entries
  passwd <- createPassword passwordstring
  maybeuser <- dbQuery $ GetUserByEmail email
  case maybeuser of
    Nothing -> do
      company <- dbUpdate $ CreateCompany
      _ <- dbUpdate $ AddUser ("", "") (unEmail email) (Just passwd) (companyid company,True) defaultValue Nothing
      return ()
    Just _ -> return () -- user exist, do not add it
