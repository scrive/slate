module Kontra
    ( module User.UserState
    , module User.Password
    , Context(..)
    , Kontrakcja
    , KontraMonad(..)
    , isSuperUser
    , Kontra(runKontra)
    , initialUsers
    , clearFlashMsgs
    , addELegTransaction
    , logUserToContext
    , onlySuperUser
    , newPasswordReminderLink
    , newViralInvitationSentLink
    , newAccountCreatedLink
    , newAccountCreatedBySigningLink
    , scheduleEmailSendout
    , queryOrFail
    , queryOrFailIfLeft
    , returnJustOrMZero
    , returnRightOrMZero
    , param
    , currentService
    , currentServiceID
    , HasService(..)
    )
    where

import Control.Applicative
import Control.Monad.Reader
import Control.Monad.State
import Control.Concurrent.MVar
import Doc.DocState
import Happstack.Server
import Misc
import Happstack.State (query, QueryEvent)
import User.UserState
import User.Password hiding (Password, NoPassword)
import qualified Data.ByteString.UTF8 as BS
import Templates.Templates
import Context
import KontraLink
import KontraMonad
import ActionSchedulerState
import ELegitimation.ELeg
import Mails.SendMail
import API.Service.ServiceState
import Util.HasSomeUserInfo

newtype Kontra a = Kontra { runKontra :: ServerPartT (StateT Context IO) a }
    deriving (Applicative, FilterMonad Response, Functor, HasRqData, Monad, MonadIO, MonadPlus, ServerMonad, WebMonad Response)

instance Kontrakcja Kontra

instance KontraMonad Kontra where
    getContext    = Kontra get
    modifyContext = Kontra . modify

instance TemplatesMonad Kontra where
    getTemplates = ctxtemplates <$> getContext

{- |
   A list of default user emails.  These should start out as the users
   in a brand new system.
-}
initialUsers :: [Email]
initialUsers = map (Email . BS.fromString)
         [ "gracjanpolak@gmail.com"
         , "lukas@skrivapa.se"
         , "ericwnormand@gmail.com"
         , "oskar@skrivapa.se"
         , "kbaldyga@gmail.com"
         , "viktor@skrivapa.se"
         , "andrzej@skrivapa.se"
         , "mariusz@skrivapa.se"
         , "heidi@skrivapa.se"
         ]

{- |
   Whether the user is an administrator.
-}
isSuperUser :: [Email] -> Maybe User -> Bool
isSuperUser admins (Just user) = (useremail $ userinfo user) `elem` admins
isSuperUser _ _ = False

{- |
   Will mzero if not logged in as a super user.
-}
onlySuperUser :: Kontrakcja m => m a -> m a
onlySuperUser a = do
    ctx <- getContext
    if isSuperUser (ctxadminaccounts ctx) (ctxmaybeuser ctx)
        then a
        else mzero

{- |
   Adds an Eleg Transaction to the context.
-}
addELegTransaction :: Kontrakcja m => ELegTransaction -> m ()
addELegTransaction tr = do
    modifyContext $ \ctx -> ctx {ctxelegtransactions = tr : ctxelegtransactions ctx }

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

newPasswordReminderLink :: MonadIO m => User -> m KontraLink
newPasswordReminderLink user = do
    action <- liftIO $ newPasswordReminder user
    return $ LinkPasswordReminder (actionID action)
                                  (prToken $ actionType action)

newViralInvitationSentLink :: MonadIO m => Email -> UserID -> m KontraLink
newViralInvitationSentLink email inviterid = do
    action <- liftIO $ newViralInvitationSent email inviterid
    return $ LinkViralInvitationSent (actionID action)
                                     (visToken $ actionType action)

newAccountCreatedLink :: MonadIO m => User -> m KontraLink
newAccountCreatedLink user = do
    action <- liftIO $ newAccountCreated user
    return $ LinkAccountCreated (actionID action)
                                (acToken $ actionType action)
                                (BS.toString $ getEmail user)

newAccountCreatedBySigningLink :: MonadIO m => User -> (DocumentID, SignatoryLinkID) -> m (ActionID, MagicHash)
newAccountCreatedBySigningLink user doclinkdata = do
    action <- liftIO $ newAccountCreatedBySigning user doclinkdata
    let aid = actionID action
        token = acbsToken $ actionType action
    return $ (aid, token)

-- | Schedule mail for send out and awake scheduler
scheduleEmailSendout :: MonadIO m => MVar () -> Mail -> m ()
scheduleEmailSendout enforcer mail = do
    _ <- liftIO $ do
        newEmailSendoutAction mail
        tryPutMVar enforcer ()
    return ()

{- |
   Perform a query (like with query) but if it returns Nothing, mzero; otherwise, return fromJust
 -}
queryOrFail :: (MonadPlus m,Monad m, MonadIO m) => (QueryEvent ev (Maybe res)) => ev -> m res
queryOrFail q = do
  mres <- query q
  returnJustOrMZero mres

queryOrFailIfLeft :: (MonadPlus m,Monad m, MonadIO m) => (QueryEvent ev (Either a res)) => ev -> m res
queryOrFailIfLeft q = do
  mres <- query q
  returnRightOrMZero mres

-- | if it's not a just, mzero. Otherwise, return the value
returnJustOrMZero :: (MonadPlus m,Monad m) => Maybe a -> m a
returnJustOrMZero = maybe mzero return

returnRightOrMZero :: (MonadPlus m, Monad m) => Either a b -> m b
returnRightOrMZero (Left _) = mzero
returnRightOrMZero (Right res) = return res

-- | Checks if request contains a param , else mzero
param :: String -> Kontra Response -> Kontra Response
param p action = (getDataFnM $ look p) >> action

-- | Current service id

currentService :: Context -> (Maybe Service)
currentService  ctx = ctxservice ctx

currentServiceID :: Context -> Maybe ServiceID
currentServiceID  ctx = serviceid <$> currentService ctx


class HasService a where
    getService:: a -> Maybe ServiceID

instance HasService Document where
    getService = documentservice


