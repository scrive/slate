module Kontra
    ( module KontraError
    , module KontraMonad
    , module Context
    , Kontra(..)
    , KontraPlus(..)
    , runKontraPlus
    , clearFlashMsgs
    , logUserToContext
    , logPadUserToContext
    , isAdmin
    , isSales
    , onlyAdmin
    , onlySalesOrAdmin
    , onlyBackdoorOpen
    , getDataFnM
    , switchLang       -- set language
    )
    where

import Control.Applicative
import Control.Monad.Base
import Control.Monad.Catch
import Control.Monad.Reader
import Control.Monad.State
import Control.Monad.Trans.Control
import Database.PostgreSQL.PQTypes.Class.Instances.Overlapping ()
import Happstack.Server
import Text.StringTemplates.Templates
import qualified Text.StringTemplates.TemplatesLoader as TL

import Context
import Control.Logic
import Control.Monad.Trans.Control.Util
import Control.Monad.Trans.Instances ()
import Crypto.RNG
import DB
import GuardTime (GuardTimeConfMonad(..))
import Happstack.Server.Instances ()
import KontraError
import KontraMonad
import MailContext (MailContextMonad(..))
import Mails.MailsConfig
import Templates
import User.Model
import Utils.List
import qualified Amazon as AWS
import qualified Log

type InnerKontraPlus = StateT Context (AWS.AmazonMonadT (CryptoRNGT (DBT (ServerPartT IO))))

-- | KontraPlus is Kontra plus 'WebMonad', used for interfacing with certain Happstack functions.
newtype KontraPlus a = KontraPlus { unKontraPlus :: InnerKontraPlus a }
  deriving (Alternative, Applicative, CryptoRNG, FilterMonad Response, Functor, HasRqData, Monad, MonadBase IO, MonadCatch, MonadDB, MonadIO, MonadMask, MonadThrow, ServerMonad, WebMonad Response, AWS.AmazonMonad)

instance Log.MonadLog KontraPlus where
  mixlogjs title js = liftBase (Log.mixlogjsIO title js)

runKontraPlus :: Context -> KontraPlus a -> AWS.AmazonMonadT (CryptoRNGT (DBT (ServerPartT IO))) a
runKontraPlus ctx f = evalStateT (unKontraPlus f) ctx

instance MonadBaseControl IO KontraPlus where
  newtype StM KontraPlus a = StKontraPlus { unStKontraPlus :: StM InnerKontraPlus a }
  liftBaseWith = newtypeLiftBaseWith KontraPlus unKontraPlus StKontraPlus
  restoreM     = newtypeRestoreM KontraPlus unStKontraPlus
  {-# INLINE liftBaseWith #-}
  {-# INLINE restoreM #-}

instance KontraMonad KontraPlus where
  getContext    = KontraPlus get
  modifyContext = KontraPlus . modify

instance TemplatesMonad KontraPlus where
  getTemplates = ctxtemplates <$> getContext
  getTextTemplatesByLanguage langStr = do
     Context{ctxglobaltemplates} <- getContext
     return $ TL.localizedVersion langStr ctxglobaltemplates

instance GuardTimeConfMonad KontraPlus where
  getGuardTimeConf = ctxgtconf <$> getContext

instance MailContextMonad KontraPlus where
  getMailContext = contextToMailContext <$> getContext

-- | Kontra is a traditional Happstack handler monad except that it's
-- not WebMonad.
--
-- Note also that in Kontra we don't do backtracking, which is why it
-- is not an instance of MonadPlus.  Errors are signaled explicitly
-- through 'KontraError'.
newtype Kontra a = Kontra { unKontra :: KontraPlus a }
  deriving (Applicative, CryptoRNG, FilterMonad Response, Functor, HasRqData, Monad, MonadBase IO, MonadCatch, MonadIO, MonadDB, MonadMask, MonadThrow, ServerMonad, KontraMonad, TemplatesMonad, Log.MonadLog, AWS.AmazonMonad, MailContextMonad, GuardTimeConfMonad)

instance MonadBaseControl IO Kontra where
  newtype StM Kontra a = StKontra { unStKontra :: StM KontraPlus a }
  liftBaseWith = newtypeLiftBaseWith Kontra unKontra StKontra
  restoreM     = newtypeRestoreM Kontra unStKontra
  {-# INLINE liftBaseWith #-}
  {-# INLINE restoreM #-}

{- Logged in user is admin-}
isAdmin :: Context -> Bool
isAdmin ctx = (useremail <$> userinfo <$> ctxmaybeuser ctx) `melem` (ctxadminaccounts ctx)

{- Logged in user is sales -}
isSales :: Context -> Bool
isSales ctx = (useremail <$> userinfo <$> ctxmaybeuser ctx) `melem` (ctxsalesaccounts ctx)

{- |
   Will 404 if not logged in as an admin.
-}
onlyAdmin :: Kontrakcja m => m a -> m a
onlyAdmin m = do
  admin <- isAdmin <$> getContext
  if admin
    then m
    else respond404

{- |
   Will 404 if not logged in as a sales admin.
-}
onlySalesOrAdmin :: Kontrakcja m => m a -> m a
onlySalesOrAdmin m = do
  admin <- (isAdmin ||^ isSales) <$> getContext
  if admin
    then m
    else respond404

{- |
    Will 404 if the testing backdoor isn't open.
-}
onlyBackdoorOpen :: Kontrakcja m => m a -> m a
onlyBackdoorOpen a = do
  backdoorOpen <- isBackdoorOpen . ctxmailsconfig <$> getContext
  if backdoorOpen
    then a
    else respond404

{- |
   Clears all the flash messages from the context.
-}
clearFlashMsgs:: KontraMonad m => m ()
clearFlashMsgs = modifyContext $ \ctx -> ctx { ctxflashmessages = [] }

{- |
   Sticks the logged in user onto the context
-}
logUserToContext :: Kontrakcja m => Maybe User -> m ()
logUserToContext user =
    modifyContext $ \ctx -> ctx { ctxmaybeuser = user}

logPadUserToContext :: Kontrakcja m => Maybe User -> m ()
logPadUserToContext user =
    modifyContext $ \ctx -> ctx { ctxmaybepaduser = user}

switchLang :: Kontrakcja m => Lang -> m ()
switchLang lang =
     modifyContext $ \ctx -> ctx {
         ctxlang       = lang,
         ctxtemplates  = localizedVersion lang (ctxglobaltemplates ctx)
     }

-- | Extract data from GET or POST request. Fail with 'internalError' if param
-- variable not present or when it cannot be read.
getDataFnM :: (HasRqData m, MonadBase IO m, MonadIO m, ServerMonad m) => RqData a -> m a
getDataFnM fun = either (const internalError) return =<< getDataFn fun
