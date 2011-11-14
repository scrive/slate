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
               , hPut
               , hPostNoXToken
               , hPostAllowHttp
               , hGetAllowHttp
               , hGetAjax
               , https
               , RedirectOrContent, allowHttp
               , toK0, toK1, toK2, toK3, toK4, toK5, toK6
               , ToResp, toResp
                 )where

import Control.Monad.State
import Control.Monad.IO.Class()
import Data.Functor
import AppView as V
import Data.Maybe
import Happstack.Server(Response, Method(GET,POST,DELETE,PUT), FromReqURI, rsCode)
import qualified Happstack.Server as H
import Happstack.StaticRouting(Route)
import Happstack.StaticRouting.Internal(Route(Handler))
import KontraLink
import Misc
import Kontra
import qualified User.UserControl as UserControl
import Redirect
import Text.JSON

type RedirectOrContent = Either KontraLink String

class ToResp a where
    toResp:: a -> Kontra Response

instance ToResp Response where
    toResp = return

instance ToResp KontraLink where
    toResp = sendRedirect

instance ToResp String where
    toResp = page . return

instance ToResp JSValue where
    toResp = simpleResponse . encode

instance (ToResp a , ToResp b) => ToResp (Either a b) where
    toResp = either toResp toResp

-- Workaround for GHC 6.12.3:

class Path a where
  pathHandler' :: (Kontra Response -> Kontra Response) -> a -> Kontra Response
  arity' :: a -> Int

instance (FromReqURI d, Path a) => Path (d -> a) where
  pathHandler' w f = H.path (pathHandler' w . f)
  arity' f = 1 + arity' (f undefined)

instance ToResp a => Path (Kontra a) where
  pathHandler' w m = w (m >>= toResp)
  arity' _ = 0

-- | Expect the given method, and exactly 'n' more segments, where 'n' is the arity of the handler
path :: Path a => H.Method -> (Kontra Response -> Kontra Response) -> a -> Route (Kontra Response)
path m w h = Handler (Just (arity' h),m) (pathHandler' w h)

hPostWrap :: Path a => (Kontra Response -> Kontra Response) -> a -> Route (Kontra Response)
hPostWrap f = path POST f

hGetWrap :: Path a => (Kontra Response -> Kontra Response) -> a -> Route (Kontra Response)
hGetWrap f = path GET f

hDeleteWrap :: Path a => (Kontra Response -> Kontra Response) -> a -> Route (Kontra Response)
hDeleteWrap f x = path DELETE f x

hPutWrap :: Path a => (Kontra Response -> Kontra Response) -> a -> Route (Kontra Response)
hPutWrap f x = path PUT f x


{- To change standard string to page-}
page:: Kontra String -> Kontra Response
page pageBody = do
    pb <- pageBody
    ctx <- getContext
    if (isNothing $ ctxservice ctx)
     then renderFromBody TopDocument kontrakcja pb
     else embeddedPage pb





{- Use this to mark that request will try to get data from our service and embed it on our website
   It returns a script that if embeded on site will force redirect to main page
   Ajax request should not contain redirect
-}

hGetAjax :: Path a => a -> Route (Kontra Response)
hGetAjax = hGetWrap wrapAjax

wrapAjax :: Kontra Response -> Kontra Response
wrapAjax action = (noRedirect action) `mplus` ajaxError -- Soft redirects should be supported here, ask MR

noRedirect::Kontra Response -> Kontra Response
noRedirect action = do
    response <- action
    if (rsCode response /= 303)
       then return response
       else mzero

hPost :: Path a => a -> Route (Kontra Response)
hPost = hPostWrap (https . guardXToken)

hGet :: Path a => a -> Route (Kontra Response)
hGet = hGetWrap https

hDelete :: Path a => a -> Route (Kontra Response)
hDelete = hDeleteWrap https

hPut :: Path a => a -> Route (Kontra Response)
hPut = hPutWrap https

hGetAllowHttp :: Path a => a -> Route (Kontra Response)
hGetAllowHttp = hGetWrap allowHttp

hPostAllowHttp :: Path a => a -> Route (Kontra Response)
hPostAllowHttp = hPostWrap allowHttp

hPostNoXToken :: Path a => a -> Route (Kontra Response)
hPostNoXToken = hPostWrap https

https:: Kontra Response -> Kontra Response
https action = do
    secure <- isSecure
    if secure
       then action
       else sendSecureLoopBack


allowHttp:: Kontra Response -> Kontra Response
allowHttp action = do
    secure <- isSecure
    loging <- isFieldSet "logging"
    logged <- isJust <$> ctxmaybeuser <$> getContext
    if (secure || (not $ loging || logged))
       then action
       else sendSecureLoopBack

guardXToken:: Kontra Response -> Kontra Response
guardXToken = (>>) UserControl.guardXToken

-- | Use to enforce a specific arity of a handler to make it explicit
-- how requests are routed (also needed with GHC-6.12.3)
toK0 :: Kontra a -> Kontra a
toK0 = id

toK1 :: (a -> Kontra b) -> (a -> Kontra b)
toK1 = id

toK2 :: (a -> b -> Kontra c) -> (a -> b -> Kontra c)
toK2 = id

toK3 :: (a -> b -> c -> Kontra d) -> (a -> b -> c -> Kontra d)
toK3 = id

toK4 :: (a -> b -> c -> d -> Kontra e) -> (a -> b -> c -> d -> Kontra e)
toK4 = id

toK5 :: (a -> b -> c -> d -> e -> Kontra f) -> (a -> b -> c -> d -> e -> Kontra f)
toK5 = id

toK6 :: (a -> b -> c -> d -> e -> f -> Kontra g) -> (a -> b -> c -> d -> e -> f -> Kontra g)
toK6 = id
