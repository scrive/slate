-----------------------------------------------------------------------------
-- |
-- Module      :  Routing
-- Maintainer  :  all
-- Stability   :  development
-- Portability :  portable
--
-- Schema for all pages and posts
-----------------------------------------------------------------------------
module Routing ( hGet
               , hGetWrap
               , hPost
               , hDelete
               , hDeleteAllowHttp
               , hPut
               , hPostNoXToken
               , hPostAllowHttp
               , hPostNoXTokenHttp
               , hGetAllowHttp
               , https
               , allowHttp
               , toK0, toK1, toK2, toK3, toK4, toK5, toK6
               , ToResp(..)
               , ThinPage(..)
               ) where

import Control.Monad
import Data.Functor
import Data.Maybe
import Happstack.Server(Response, Method(GET, POST, DELETE, PUT), ToMessage(..))
import Happstack.StaticRouting
import Text.JSON
import qualified Data.Aeson as A

import AppView as V
import Happstack.Fields
import Kontra
import KontraLink
import Redirect
import Util.CSVUtil
import Util.ZipUtil
import Utils.HTTP
import Utils.Read

newtype ThinPage = ThinPage String

kpath :: (Path Kontra KontraPlus h a) => Method -> (Kontra a -> Kontra b) -> h
      -> Route (KontraPlus b)
kpath m h = path m (unKontra . h)

class ToResp a where
    toResp:: a -> Kontra Response

instance ToResp Response where
    toResp = return

instance ToResp (Kontra Response) where
    toResp = id

instance ToResp KontraLink where
    toResp = sendRedirect

instance ToResp String where
    toResp = page . return

instance ToResp ThinPage where
    toResp = pageThin . return

instance ToResp JSValue where
    toResp = simpleJsonResponse

instance ToResp A.Value where
    toResp = simpleAesonResponse

instance ToResp () where
    toResp _ = simpleHtmlResponse ""

instance (ToResp a , ToResp b) => ToResp (Either a b) where
    toResp = either toResp toResp

instance ToResp CSV where
    toResp = return . toResponse

instance ToResp ZipArchive where
    toResp = return . toResponse

hPostWrap :: Path Kontra KontraPlus a Response => (Kontra Response -> Kontra Response) -> a -> Route (KontraPlus Response)
hPostWrap = kpath POST

hGetWrap :: Path Kontra KontraPlus a Response => (Kontra Response -> Kontra Response) -> a -> Route (KontraPlus Response)
hGetWrap = kpath GET

hDeleteWrap :: Path Kontra KontraPlus a Response => (Kontra Response -> Kontra Response) -> a -> Route (KontraPlus Response)
hDeleteWrap = kpath DELETE

hPutWrap :: Path Kontra KontraPlus a Response => (Kontra Response -> Kontra Response) -> a -> Route (KontraPlus Response)
hPutWrap = kpath PUT

{- To change standard string to page -}
page :: Kontra String -> Kontra Response
page pageBody = do
    pb <- pageBody
    renderFromBody pb

{- To change thin page type to full response -}
pageThin :: Kontra ThinPage -> Kontra Response
pageThin pageBody = do
    ThinPage pb  <- pageBody
    renderFromBodyThin pb


hPost :: Path Kontra KontraPlus a Response => a -> Route (KontraPlus Response)
hPost = hPostWrap (https . guardXToken)

hGet :: Path Kontra KontraPlus a Response => a -> Route (KontraPlus Response)
hGet = hGetWrap https

hDelete :: Path Kontra KontraPlus a Response => a -> Route (KontraPlus Response)
hDelete = hDeleteWrap https

hDeleteAllowHttp :: Path Kontra KontraPlus a Response => a -> Route (KontraPlus Response)
hDeleteAllowHttp = hDeleteWrap allowHttp

hPut :: Path Kontra KontraPlus a Response => a -> Route (KontraPlus Response)
hPut = hPutWrap https

hGetAllowHttp :: Path Kontra KontraPlus a Response => a -> Route (KontraPlus Response)
hGetAllowHttp = hGetWrap allowHttp

hPostAllowHttp :: Path Kontra KontraPlus a Response => a -> Route (KontraPlus Response)
hPostAllowHttp = hPostWrap allowHttp

hPostNoXToken :: Path Kontra KontraPlus a Response => a -> Route (KontraPlus Response)
hPostNoXToken = hPostWrap https

hPostNoXTokenHttp :: Path Kontra KontraPlus a Response => a -> Route (KontraPlus Response)
hPostNoXTokenHttp = hPostWrap allowHttp

https:: Kontra Response -> Kontra Response
https action = do
    secure <- isSecure
    useHttps <- ctxusehttps <$> getContext
    if secure || not useHttps
       then action
       else sendSecureLoopBack

allowHttp:: Kontrakcja m => m Response -> m Response
allowHttp action = action

-- | Use to enforce a specific arity of a handler to make it explicit
-- how requests are routed and convert returned value to Responses
toK0 :: ToResp r => Kontra r -> Kontra Response
toK0 m = m >>= toResp

toK1 :: ToResp r => (a -> Kontra r) -> (a -> Kontra Response)
toK1 m a = m a >>= toResp

toK2 :: ToResp r => (a -> b -> Kontra r) -> (a -> b -> Kontra Response)
toK2 m a b = m a b >>= toResp

toK3 :: ToResp r => (a -> b -> c -> Kontra r) -> (a -> b -> c -> Kontra Response)
toK3 m a b c = m a b c >>= toResp

toK4 :: ToResp r => (a -> b -> c -> d -> Kontra r) -> (a -> b -> c -> d -> Kontra Response)
toK4 m a b c d = m a b c d >>= toResp

toK5 :: ToResp r => (a -> b -> c -> d -> e -> Kontra r) -> (a -> b -> c -> d -> e -> Kontra Response)
toK5 m a b c d e = m a b c d e >>= toResp

toK6 :: ToResp r => (a -> b -> c -> d -> e -> f -> Kontra r) -> (a -> b -> c -> d -> e -> f -> Kontra Response)
toK6 m a b c d e f = m a b c d e f >>= toResp


guardXToken :: Kontra Response -> Kontra Response
guardXToken action = do
  ctx <- getContext
  xtoken <- join <$> (fmap maybeRead) <$> readField "xtoken"
  if (isJust xtoken && (fromJust xtoken == ctxxtoken ctx))
    then action
    else do -- Requests authorized by something else then xtoken, can't access session data or change context stuff.
      modifyContext anonymousContext
      res <- action
      modifyContext (\_ -> ctx)
      return res
