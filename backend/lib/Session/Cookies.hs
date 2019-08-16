module Session.Cookies (
    SessionCookieInfo(..)
  , startSessionCookie
  , stopSessionCookie
  , sessionCookieInfoFromSession
  , currentSessionInfoCookies
  , isXTokenCookieBroken
  , cookieNameSessionID
  , cookieNameXToken
  ) where

import Control.Arrow
import Control.Monad.IO.Class
import Happstack.Server hiding (Session, addCookie)
import TextShow (TextShow(..), fromText)
import qualified Data.Text as T

import Cookies
import MagicHash
import Session.Types
import Utils.HTTP

-- | Info that we store in cookies.
data SessionCookieInfo = SessionCookieInfo {
    cookieSessionID    :: SessionID -- While parsing we depend on it
                                    -- containing just nums
  , cookieSessionToken :: MagicHash -- While parsing we depend on it
                                    -- starting with alpha
  }

instance Show SessionCookieInfo where
  show SessionCookieInfo{..} =
    show cookieSessionID ++ "-" ++ show cookieSessionToken

instance TextShow SessionCookieInfo where
  showb SessionCookieInfo{..} =
    showb cookieSessionID <> fromText "-" <> showb cookieSessionToken

instance Read SessionCookieInfo where
  readsPrec _ s = do
    let
      (sid, msh) :: (String, String) =
        second (drop 1) $ break (== '-') s
      (sh, rest) = splitAt 16 msh
    case SessionCookieInfo <$> maybeRead (T.pack sid) <*> maybeRead (T.pack sh) of
      Just sci -> [(sci, rest)]
      Nothing  -> []

instance FromReqURI SessionCookieInfo where
  fromReqURI = maybeRead . T.pack

cookieNameXToken :: Text
cookieNameXToken = "xtoken"

cookieNameSessionID :: Text
cookieNameSessionID = "sessionId"

mkCookieFromText :: Text -> Text -> Cookie
mkCookieFromText h v = mkCookie (T.unpack h) (T.unpack v)

-- | Add a session cookie to browser.
startSessionCookie :: (FilterMonad Response m, ServerMonad m, MonadIO m)
                   => Session -> m ()
startSessionCookie s = do
  ishttps  <- isHTTPS
  addHttpOnlyCookie ishttps (MaxAge (60*60*24)) $
    mkCookieFromText cookieNameSessionID . showt $ sessionCookieInfoFromSession s
  addCookie ishttps (MaxAge (60*60*24)) $
    mkCookieFromText cookieNameXToken $ showt $ sesCSRFToken s

-- | Remove session cookie from browser.
stopSessionCookie :: (FilterMonad Response m, ServerMonad m, MonadIO m)
                  => m ()
stopSessionCookie = do
  ishttps  <- isHTTPS
  addHttpOnlyCookie ishttps (MaxAge 0) $
    mkCookieFromText cookieNameSessionID ""
  addCookie ishttps (MaxAge 0) $
    mkCookieFromText cookieNameXToken ""

sessionCookieInfoFromSession :: Session -> SessionCookieInfo
sessionCookieInfoFromSession s = SessionCookieInfo {
     cookieSessionID = sesID s
   , cookieSessionToken = sesToken s
  }

isXTokenCookieBroken :: (FilterMonad Response m, ServerMonad m, MonadIO m)
                     => m Bool
isXTokenCookieBroken = do
  sidCookie    <- lookCookieValues cookieNameSessionID . rqHeaders <$> askRq
  xtokenCookie <- lookCookieValues cookieNameXToken . rqHeaders <$> askRq
  return $ case (sidCookie,xtokenCookie) of
    (_:_, _:_) -> False
    ([],[])    -> False
    _          -> True

-- | Read current session cookie from request.
currentSessionInfoCookies :: ServerMonad m => m [SessionCookieInfo]
currentSessionInfoCookies =
  (catMaybes . fmap maybeRead . lookCookieValues cookieNameSessionID . rqHeaders) <$> askRq
