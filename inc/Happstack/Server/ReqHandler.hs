module Happstack.Server.ReqHandler (
    withDecodedBody
  , withRqData
  , RqDataError(..)
  , ReqHandlerSt(..)
  , ReqHandlerT(..)
  , runReqHandlerT
  , mapReqHandlerT
  , PlusSandboxT(..)
  , runPlusSandboxT
  , mapPlusSandboxT
  , WebSandboxT(..)
  , runWebSandboxT
  , mapWebSandboxT
  ) where

import Control.Applicative
import Control.Monad
import Control.Monad.Base
import Control.Monad.Catch
import Control.Monad.Except
import Control.Monad.Trans.Control
import Control.Monad.Trans.Maybe
import Control.Monad.Trans.State
import Data.Typeable
import Happstack.Server
import Happstack.Server.Internal.MessageWrap
import Happstack.Server.Internal.Monads
import Network
import qualified Happstack.Server.Internal.Listen as L

import Happstack.Server.Instances ()
import KontraPrelude

----------------------------------------

-- | Sane variant of 'decodeBody' that doesn't require 'WebMonad'.
withDecodedBody :: (FilterMonad Response m, ServerMonad m, MonadIO m)
                => BodyPolicy
                -> m Response
                -> m Response
withDecodedBody bp action = do
  rq <- askRq
  (_, me) <- bodyInput bp rq
  case me of
    Just e  -> requestEntityTooLarge (toResponse e)
    Nothing -> action

-- | Sane variant of 'withDataFn' that doesn't require 'MonadPlus'.
withRqData :: (HasRqData m, MonadThrow m, ServerMonad m)
           => RqData a -> (a -> m r) -> m r
withRqData fn action = either (rqDataError . Errors) action =<< getDataFn fn

----------------------------------------

data RqDataError = RqDataError (Errors String)
  deriving (Eq, Ord, Show, Typeable)
instance Exception RqDataError

----------------------------------------

data ReqHandlerSt = ReqHandlerSt {
  hsRequest :: !Request
, hsFilter  :: !(Response -> Response)
}

type InnerReqHandlerT = StateT ReqHandlerSt

-- | Replacement for 'ServerPerT' with 'MonadMask'
-- instance and no 'MonadPlus' and 'MonadWeb' instances.
newtype ReqHandlerT m a = ReqHandlerT { unReqHandlerT :: InnerReqHandlerT m a }
  deriving (Applicative, Functor, Monad, MonadBase b, MonadCatch, MonadIO, MonadMask, MonadThrow, MonadTrans)

runReqHandlerT :: Socket -> Conf -> ReqHandlerT IO Response -> IO ()
runReqHandlerT sock conf (ReqHandlerT action) = L.listen' sock conf $ \req -> do
  (res, st) <- runStateT action $ ReqHandlerSt req id
  runValidator (fromMaybe return $ validator conf) $ hsFilter st res

mapReqHandlerT :: (m (a, ReqHandlerSt) -> n (b, ReqHandlerSt)) -> ReqHandlerT m a -> ReqHandlerT n b
mapReqHandlerT f = ReqHandlerT . mapStateT f . unReqHandlerT

instance MonadTransControl ReqHandlerT where
  type StT ReqHandlerT a = StT InnerReqHandlerT a
  liftWith = defaultLiftWith ReqHandlerT unReqHandlerT
  restoreT = defaultRestoreT ReqHandlerT
  {-# INLINE liftWith #-}
  {-# INLINE restoreT #-}

instance MonadBaseControl b m => MonadBaseControl b (ReqHandlerT m) where
  type StM (ReqHandlerT m) a = ComposeSt ReqHandlerT m a
  liftBaseWith = defaultLiftBaseWith
  restoreM     = defaultRestoreM
  {-# INLINE liftBaseWith #-}
  {-# INLINE restoreM #-}

instance Monad m => FilterMonad Response (ReqHandlerT m) where
  setFilter f     = ReqHandlerT . modify $ \st -> st { hsFilter = f }
  composeFilter f = ReqHandlerT . modify $ \st -> st { hsFilter = f . hsFilter st }
  getFilter m     = ReqHandlerT . StateT $ \st -> do
    ~(res, st') <- runStateT (unReqHandlerT m) st
    return ((res, hsFilter st'), st')

instance (MonadIO m, MonadThrow m) => HasRqData (ReqHandlerT m) where
  askRqEnv = smAskRqEnv
  rqDataError = throwM . RqDataError
  localRqEnv = smLocalRqEnv

instance Monad m => ServerMonad (ReqHandlerT m) where
  askRq       = ReqHandlerT $ gets hsRequest
  localRq f m = ReqHandlerT . StateT $ \st -> do
    let req = hsRequest st
    ~(res, st') <- runStateT (unReqHandlerT m) $ st { hsRequest = f req }
    return (res, st' { hsRequest = req })

----------------------------------------

-- | Sandbox for happstack functions using 'MonadPlus'.
-- Note that this is NOT a valid instance of 'MonadMask'.
newtype PlusSandboxT m a = PlusSandboxT { unPlusSandboxT :: MaybeT m a }
  deriving (Applicative, FilterMonad r, Functor, HasRqData, Monad, MonadBase b, MonadCatch, MonadIO, MonadThrow, MonadTrans, ServerMonad)

runPlusSandboxT :: PlusSandboxT m a -> m (Maybe a)
runPlusSandboxT = runMaybeT . unPlusSandboxT

mapPlusSandboxT :: (m (Maybe a) -> n (Maybe b))-> PlusSandboxT m a -> PlusSandboxT n b
mapPlusSandboxT f = PlusSandboxT . mapMaybeT f . unPlusSandboxT

instance (Functor m, Monad m) => Alternative (PlusSandboxT m) where
  empty = mzero
  (<|>) = mplus

instance Monad m => MonadPlus (PlusSandboxT m) where
  mzero = PlusSandboxT mzero
  PlusSandboxT m1 `mplus` PlusSandboxT m2 = PlusSandboxT $ m1 `mplus` m2

----------------------------------------

-- | Sandbox for happstack functions using 'WebMonad'.
-- Note that this is NOT a valid instance of 'MonadMask'.
--
-- In addition, 'MonadPlus' is not derived because
-- its instance for ErrorT throws away information.
newtype WebSandboxT m a = WebSandboxT { unWebSandboxT :: ExceptT Response m a }
  deriving (Applicative, FilterMonad r, Functor, HasRqData, Monad, MonadBase b, MonadCatch, MonadIO, MonadThrow, MonadTrans, ServerMonad)

runWebSandboxT :: WebSandboxT m a -> m (Either Response a)
runWebSandboxT = runExceptT . unWebSandboxT

mapWebSandboxT :: (m (Either Response a) -> n (Either Response b)) -> WebSandboxT m a -> WebSandboxT n b
mapWebSandboxT f = WebSandboxT . mapExceptT f . unWebSandboxT

instance Monad m => WebMonad Response (WebSandboxT m) where
  finishWith = WebSandboxT . throwError
