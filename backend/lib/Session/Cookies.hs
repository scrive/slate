module Session.Cookies (
    SessionCookieInfo(..)
  , startSessionCookie
  , stopSessionCookie
  , sessionCookieInfoFromSession
  , currentSessionInfoCookies
  , cookieNameSessionID
  , cookieNameXToken
  ) where

import Control.Arrow
import Control.Monad.IO.Class
import Happstack.Server hiding (Session, addCookie)

import Cookies
import KontraPrelude
import MagicHash
import Session.Data
import Utils.HTTP

-- | Info that we store in cookies.
data SessionCookieInfo = SessionCookieInfo {
    cookieSessionID    :: SessionID -- While parsing we depend on it containing just nums
  , cookieSessionToken :: MagicHash -- While parsing we depend on it starting with alpha
  }

instance Show SessionCookieInfo where
  show SessionCookieInfo{..} =
    show cookieSessionID ++ "-" ++ show cookieSessionToken

instance Read SessionCookieInfo where
  readsPrec _ s = do
    let (sid, msh) = second (drop 1) $ break (== '-') s
        (sh, rest) = splitAt 16 msh
    case SessionCookieInfo <$> maybeRead sid <*> maybeRead sh of
      Just sci -> [(sci, rest)]
      Nothing  -> []

instance FromReqURI SessionCookieInfo where
  fromReqURI = maybeRead

cookieNameXToken :: String
cookieNameXToken = "xtoken"

cookieNameSessionID :: String
cookieNameSessionID = "sessionId"

-- | Add a session cookie to browser.
startSessionCookie :: (FilterMonad Response m, ServerMonad m, MonadIO m)
                   => Session -> m ()
startSessionCookie s = do
  ishttps  <- isHTTPS
  addHttpOnlyCookie ishttps (MaxAge (60*60*24)) $
    mkCookie cookieNameSessionID . show $ sessionCookieInfoFromSession s
  addCookie ishttps (MaxAge (60*60*24)) $
    mkCookie cookieNameXToken $ show $ sesCSRFToken s

-- | Remove session cookie from browser.
stopSessionCookie :: (FilterMonad Response m, ServerMonad m, MonadIO m)
                  => m ()
stopSessionCookie = do
  ishttps  <- isHTTPS
  addHttpOnlyCookie ishttps (MaxAge 0) $
    mkCookie cookieNameSessionID ""
  addCookie ishttps (MaxAge 0) $
    mkCookie cookieNameXToken ""

sessionCookieInfoFromSession :: Session -> SessionCookieInfo
sessionCookieInfoFromSession s = SessionCookieInfo {
     cookieSessionID = sesID s
   , cookieSessionToken = sesToken s
  }

-- | Read current session cookie from request.
currentSessionInfoCookies :: ServerMonad m => m [SessionCookieInfo]
currentSessionInfoCookies =
  (catMaybes . fmap maybeRead . lookCookieValues cookieNameSessionID . rqHeaders) <$> askRq
