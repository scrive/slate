module User.UserControl where

import Control.Monad.State
import Data.Functor
import Data.Maybe
import Happstack.Server hiding (simpleHTTP)
import Text.JSON (JSValue(..))
import Text.JSON.Gen

import ActionQueue.Core
import ActionQueue.EmailChangeRequest
import ActionQueue.PasswordReminder
import ActionQueue.UserAccountRequest
import AppView
import Crypto.RNG
import DB hiding (update, query)
import Doc.Action
import Company.Model
import InputValidation
import Kontra
import KontraLink
import MagicHash (MagicHash)
import Mails.SendMail
import MinutesTime hiding (toClockTime)
import Happstack.Fields
import Utils.Monad
import Redirect
import Text.StringTemplates.Templates
import User.Model
import User.UserView
import Util.FlashUtil
import Util.MonadUtils
import Util.HasSomeUserInfo
import qualified Log
import Stats.Control
import User.Action
import User.Utils
import User.History.Model
import ScriveByMail.Model
import ListUtil
import qualified Text.StringTemplates.Fields as F
import Routing
import BrandedDomains
import Analytics.Include


handleAccountGet :: Kontrakcja m => m (Either KontraLink Response)
handleAccountGet = checkUserTOSGet $ do
    ctx <- getContext
    case (ctxmaybeuser ctx) of
         Just user -> do
           mcompany <- getCompanyForUser user
           content <- showAccount user mcompany
           renderFromBody kontrakcja content
         Nothing -> sendRedirect $ LinkLogin (ctxlang ctx) NotLogged

-- please treat this function like a public query form, it's not secure
handleRequestPhoneCall :: Kontrakcja m => m KontraLink
handleRequestPhoneCall = do
  Context{ctxmaybeuser} <- getContext
  memail <- getOptionalField asValidEmail "email"
  mphone <-  getOptionalField asValidPhone "phone"
  muser <- maybe (return Nothing) (dbQuery . GetUserByEmail . Email) memail
  case (muser, mphone) of
    (Just user, Just phone) -> do
      --only set the phone number if they're actually logged in
      -- it is possible to request a phone call from the sign view without being logged in!
      -- this function could be called by anyone!
      when (isJust ctxmaybeuser && fmap userid ctxmaybeuser == Just (userid user)) $ do
        _ <- dbUpdate $ SetUserInfo (userid user) $ (userinfo user){ userphone = phone }
        return ()
      phoneMeRequest muser phone
    (_, Just phone) -> phoneMeRequest Nothing phone
    _ -> return ()
  return $ LinkDesignView

sendChangeToExistingEmailInternalWarningMail :: Kontrakcja m => User -> Email -> m ()
sendChangeToExistingEmailInternalWarningMail user newemail = do
  ctx <- getContext
  let securitymsg =
        "User " ++ getEmail user ++ " (" ++ show (userid user) ++ ")"
        ++ " has requested that their email be changed to " ++ unEmail newemail
        ++ " but this email is already used by another account."
      content =
        securitymsg
        ++ "Maybe they're trying to attempt to merge accounts and need help, "
        ++ "or maybe they're a hacker trying to figure out who is and isn't a user."
  Log.security securitymsg
  scheduleEmailSendout (ctxmailsconfig ctx) $ emptyMail {
      to = [MailAddress { fullname = "info@skrivapa.se", email = "info@skrivapa.se" }]
    , title = "Request to Change Email to Existing Account"
    , content = content
    }

handleGetChangeEmail :: Kontrakcja m => UserID -> MagicHash -> m (Either KontraLink Response)
handleGetChangeEmail uid hash = withUserGet $ do
  mnewemail <- getEmailChangeRequestNewEmail uid hash
  case mnewemail of
    Nothing -> addFlashM $ flashMessageProblemWithEmailChange
    Just newemail -> addFlashM $ modalDoYouWantToChangeEmail newemail
  Context{ctxmaybeuser = Just user} <- getContext
  mcompany <- getCompanyForUser user
  content <- showAccount user mcompany
  renderFromBody kontrakcja content

handlePostChangeEmail :: Kontrakcja m => UserID -> MagicHash -> m KontraLink
handlePostChangeEmail uid hash = withUserPost $ do
  mnewemail <- getEmailChangeRequestNewEmail uid hash
  Context{ctxmaybeuser = Just user, ctxipnumber, ctxtime} <- getContext
  mpassword <- getRequiredField asDirtyPassword "password"
  case mpassword of
    Nothing -> return ()
    Just password | verifyPassword (userpassword user) password -> do
      changed <- maybe (return False)
                      (dbUpdate . SetUserEmail (userid user))
                      mnewemail
      if changed
        then do
            _ <- dbUpdate $ LogHistoryDetailsChanged (userid user) ctxipnumber ctxtime
                                                     [("email", unEmail $ useremail $ userinfo user, unEmail $ fromJust mnewemail)]
                                                     (Just $ userid user)
            addFlashM $ flashMessageYourEmailHasChanged
        else addFlashM $ flashMessageProblemWithEmailChange
      _ <- dbUpdate $ DeleteAction emailChangeRequest uid
      return ()
    Just _password -> do
      addFlashM $ flashMessageProblemWithPassword
  return $ LinkAccount

getUserInfoUpdate :: Kontrakcja m => m (UserInfo -> UserInfo)
getUserInfoUpdate  = do
    -- a lot doesn't have validation rules defined, but i put in what we do have
    mfstname          <- getValidField asValidName "fstname"
    msndname          <- getValidField asValidName "sndname"
    mpersonalnumber   <- getField "personalnumber"
    mphone            <- getField "phone"
    mcompanyposition  <- getValidField asValidPosition "companyposition"
    mcompanyname      <- getField "companyname"
    mcompanynumber    <- getField "companynumber"
    return $ \ui ->
        ui {
            userfstname = fromMaybe (userfstname ui) mfstname
          , usersndname = fromMaybe (usersndname ui) msndname
          , userpersonalnumber = fromMaybe (userpersonalnumber ui) mpersonalnumber
          , usercompanyposition = fromMaybe (usercompanyposition ui) mcompanyposition
          , userphone  = fromMaybe (userphone ui) mphone
          , usercompanyname = fromMaybe (usercompanyname ui) mcompanyname
          , usercompanynumber = fromMaybe (usercompanynumber ui) mcompanynumber
        }
    where
        getValidField = getDefaultedField ""

getCompanyInfoUpdate :: Kontrakcja m => m (CompanyInfo -> CompanyInfo)
getCompanyInfoUpdate = do
    -- a lot doesn't have validation rules defined, but i put in what we do have
  mcompanyname <- getValidField asValidCompanyName "companyname"
  mcompanynumber <- getValidField asValidCompanyNumber "companynumber"
  mcompanyaddress <- getValidField asValidAddress "companyaddress"
  mcompanyzip <- getField "companyzip"
  mcompanycity <- getField "companycity"
  mcompanycountry <- getField "companycountry"
  return $ \ci ->
      ci {
         companyname = fromMaybe (companyname ci) mcompanyname
      ,  companynumber = fromMaybe (companynumber ci) mcompanynumber
      ,  companyaddress = fromMaybe (companyaddress ci) mcompanyaddress
      ,  companyzip = fromMaybe (companyzip ci) mcompanyzip
      ,  companycity = fromMaybe (companycity ci) mcompanycity
      ,  companycountry = fromMaybe (companycountry ci) mcompanycountry
      }
  where
    getValidField = getDefaultedField ""


handleUsageStatsJSONForUserDays :: Kontrakcja m => m JSValue
handleUsageStatsJSONForUserDays = do
  Context{ctxtime, ctxmaybeuser} <- getContext
  totalS <- renderTemplate_ "statsOrgTotal"
  user <- guardJust ctxmaybeuser
  let som  = asInt $ daysBefore 30 ctxtime
      sixm = asInt $ monthsBefore 6 ctxtime
  if useriscompanyadmin user && isJust (usercompany user)
    then do
      (statsByDay, _) <- getUsageStatsForCompany (fromJust $ usercompany user) som sixm
      return $ singlePageListToJSON $ companyStatsDayToJSON totalS statsByDay
    else do
      (statsByDay, _) <- getUsageStatsForUser (userid user) som sixm
      return $ singlePageListToJSON $ userStatsDayToJSON statsByDay

handleUsageStatsJSONForUserMonths :: Kontrakcja m => m JSValue
handleUsageStatsJSONForUserMonths = do
  Context{ctxtime, ctxmaybeuser} <- getContext
  totalS <- renderTemplate_ "statsOrgTotal"
  user <- guardJust ctxmaybeuser
  let som  = asInt $ daysBefore 30 ctxtime
      sixm = asInt $ monthsBefore 6 ctxtime
  if useriscompanyadmin user && isJust (usercompany user)
    then do
    (_, statsByMonth) <- getUsageStatsForCompany (fromJust $ usercompany user) som sixm
    return $ singlePageListToJSON $ companyStatsMonthToJSON totalS statsByMonth
    else do
    (_, statsByMonth) <- getUsageStatsForUser (userid user) som sixm
    return $ singlePageListToJSON $ userStatsMonthToJSON statsByMonth

handlePostUserMailAPI :: Kontrakcja m => m KontraLink
handlePostUserMailAPI = withUserPost $ do
    User{userid} <- fromJust . ctxmaybeuser <$> getContext
    mapi <- dbQuery $ GetUserMailAPI userid
    getDefaultedField False asValidCheckBox "api_enabled"
      >>= maybe (return LinkUserMailAPI) (\enabledapi -> do
        case mapi of
             Nothing -> do
                 when enabledapi $ do
                     apikey <- random
                     _ <- dbUpdate $ SetUserMailAPIKey userid apikey 50
                     return ()
             Just api -> do
                 if not enabledapi
                    then do
                        _ <- dbUpdate $ RemoveUserMailAPI userid
                        return ()
                    else do
                        mresetkey <- getDefaultedField False asValidCheckBox "reset_key"
                        mresetsenttoday <- getDefaultedField False asValidCheckBox "reset_senttoday"
                        mdailylimit <- getRequiredField asValidNumber "daily_limit"
                        case (mresetkey, mresetsenttoday, mdailylimit) of
                             (Just resetkey, Just resetsenttoday, Just dailylimit) -> do
                                 newkey <- if resetkey
                                   then random
                                   else return $ umapiKey api
                                 _ <- dbUpdate $ SetUserMailAPIKey userid newkey dailylimit
                                 when_ resetsenttoday $ dbUpdate $ ResetUserMailAPI userid
                                 return ()
                             _ -> return ()
        return LinkUserMailAPI)

{- |
    Checks for live documents owned by the user.
-}
isUserDeletable :: Kontrakcja m => User -> m Bool
isUserDeletable user = do
  dbQuery $ IsUserDeletable (userid user)

--there must be a better way than all of these weird user create functions
-- TODO clean up

sendNewUserMail :: Kontrakcja m => User -> m ()
sendNewUserMail user = do
  ctx <- getContext
  al <- newUserAccountRequestLink (ctxlang ctx) (userid user) AccountRequest
  mail <- newUserMail ctx (getEmail user) (getSmartName user) al
  scheduleEmailSendout (ctxmailsconfig ctx) $ mail { to = [MailAddress { fullname = getSmartName user, email = getEmail user }]}
  return ()

createNewUserByAdmin :: Kontrakcja m => String -> (String, String) -> Maybe String -> Maybe (CompanyID, Bool) -> Lang -> m (Maybe User)
createNewUserByAdmin email names custommessage mcompanydata lang = do
    ctx <- getContext
    muser <- createUser (Email email) names (fst <$> mcompanydata) lang
    case muser of
         Just user -> do
             case mcompanydata of
               Just (_, admin) -> do
                 _ <- dbUpdate $ SetUserCompanyAdmin (userid user) admin
                 return ()
               Nothing -> return ()
             let fullname = composeFullName names
             now <- getMinutesTime
             _ <- dbUpdate $ SetInviteInfo (userid <$> ctxmaybeuser ctx) now Admin (userid user)
             chpwdlink <- newUserAccountRequestLink (ctxlang ctx) (userid user) ByAdmin
             mail <- mailNewAccountCreatedByAdmin ctx (getLang user) fullname email chpwdlink custommessage
             scheduleEmailSendout (ctxmailsconfig ctx) $ mail { to = [MailAddress { fullname = fullname, email = email }]}
             return muser
         Nothing -> return muser

handleAcceptTOSGet :: Kontrakcja m => m (Either KontraLink String)
handleAcceptTOSGet = withUserGet $ pageAcceptTOS

handleAcceptTOSPost :: Kontrakcja m => m ()
handleAcceptTOSPost = do
  Context{ctxmaybeuser,ctxtime, ctxipnumber} <- getContext
  userid <- guardJustM $ return $ userid <$>ctxmaybeuser
  tos <- getDefaultedField False asValidCheckBox "tos"
  when (Just True == tos) $ do
      _ <- dbUpdate $ AcceptTermsOfService userid ctxtime
      user <- guardJustM $ dbQuery $ GetUserByID userid
      _ <- addUserSignTOSStatEvent user
      _ <- dbUpdate $ LogHistoryTOSAccept userid ctxipnumber ctxtime (Just userid)
      addFlashM flashMessageUserDetailsSaved
  return ()

handleAccountSetupGet :: Kontrakcja m => UserID -> MagicHash -> m (Either KontraLink Response)
handleAccountSetupGet uid token = handleAccountSetupGetWithMethod uid token AccountRequest

handleAccountSetupGetWithMethod :: Kontrakcja m => UserID -> MagicHash -> SignupMethod -> m (Either KontraLink Response)
handleAccountSetupGetWithMethod uid token sm = do
  ctx <- getContext
  muser <- getUserAccountRequestUser uid token
  case (muser, userhasacceptedtermsofservice =<< muser) of
    (Just user, Nothing) -> do
      mcompany <-  getCompanyForUser user
      mbd <- return $ currentBrandedDomain ctx
      Right <$> (simpleHtmlResponse =<< (renderTemplateAsPage ctx "accountSetupPage" False $ do
                                            F.value "fstname" $ getFirstName user
                                            F.value "sndname" $ getLastName user
                                            F.value "userid"  $ show uid
                                            F.value "company" $ companyname <$> companyinfo <$> mcompany
                                            F.value "signupmethod" $ show sm
                                            brandingFields mbd mcompany
                                            ))
    (Just _user, Just _) -> do
      -- this case looks impossible since we delete the account request upon signing up
      -- but may it happen if they sign tos in some other way?
      return $ Left $ LinkLogin (ctxlang ctx) NotLogged
    _ -> do
      return $ Left $ LinkSignup $ ctxlang ctx

handleAccountSetupPostWithMethod :: Kontrakcja m => UserID -> MagicHash -> SignupMethod -> m JSValue
handleAccountSetupPostWithMethod uid token sm = do
  user <- guardJustM404 $ getUserAccountRequestUser uid token
  if isJust $ userhasacceptedtermsofservice user
    then runJSONGenT $ do
           value "ok" False
           value "error" ("already_active" :: String)
    else do
      mfstname <- getRequiredField asValidName "fstname"
      msndname <- getRequiredField asValidName "sndname"
      mactivateduser <- handleActivate mfstname msndname user sm
      case mactivateduser of
        Nothing -> runJSONGenT $ do
                    value "ok" False
                    value "error" ("reload" :: String)
        Just (_, docs) -> do
          _ <- dbUpdate $ DeleteAction userAccountRequest uid
          forM_ docs (\d -> postDocumentPreparationChange d "mailapi")
          ctx <- getContext
          _ <- dbUpdate $ SetUserSettings (userid user) $ (usersettings user) { lang = ctxlang ctx }
          addFlashM flashMessageUserActivated
          link <- getHomeOrDesignViewLink
          runJSONGenT $ do
            value "ok" True
            value "location" $ show link
            value "userid" $ show uid

handleAccountSetupPost :: Kontrakcja m => UserID -> MagicHash -> m JSValue
handleAccountSetupPost uid token = handleAccountSetupPostWithMethod uid token AccountRequest

{- |
    This is where we get to when the user clicks the link in their password reminder
    email.  This'll show them the usual landing page, but with option to changing their password.
-}
handlePasswordReminderGet :: Kontrakcja m => UserID -> MagicHash -> m (Either KontraLink (Either Response ThinPage))
handlePasswordReminderGet uid token = do
  muser <- getPasswordReminderUser uid token
  case muser of
    Just user -> do
      switchLang (getLang user)
      let changePassLink = show $ LinkPasswordReminder uid token
      ctx <- getContext
      case (currentBrandedDomain ctx) of
        Just bd -> do
          ad <- getAnalyticsData
          content <- renderTemplate "changePasswordPageWithBranding" $ do
                        F.value "linkchangepassword" $ changePassLink
                        F.value "logolink" $ bdlogolink bd
                        F.value "background" $ bdbackgroundcolorexternal $ bd
                        F.value "buttoncolorclass" $ bdbuttonclass $ bd

                        standardPageFields ctx kontrakcja ad
          Right . Left <$> simpleHtmlResonseClrFlash content
        Nothing -> do
          content <- renderTemplate "changePasswordPage" $ do
                        F.value "linkchangepassword" $ changePassLink
          return $ Right $ Right $ ThinPage content
    Nothing -> do
      ctx <- getContext
      addFlashM flashMessagePasswordChangeLinkNotValid
      return $ Left $ LinkLogin (ctxlang ctx) LoginTry


handlePasswordReminderPost :: Kontrakcja m => UserID -> MagicHash -> m JSValue
handlePasswordReminderPost uid token = do
  muser <- getPasswordReminderUser uid token
  case muser of
    Just user -> do
      switchLang (getLang user)
      Context{ctxtime, ctxipnumber, ctxmaybeuser} <- getContext
      mpassword <- getRequiredField Good "password"
      case mpassword of
        Just password -> do
          _ <- dbUpdate $ DeleteAction passwordReminder uid
          passwordhash <- createPassword password
          _ <- dbUpdate $ SetUserPassword (userid user) passwordhash
          _ <- dbUpdate $ LogHistoryPasswordSetup (userid user) ctxipnumber ctxtime (userid <$> ctxmaybeuser)
          addFlashM flashMessageUserPasswordChanged
          _ <- addUserLoginStatEvent ctxtime user
          logUserToContext $ Just user
          runJSONGenT $ do
            value "logged" True
            value "location" $ show LinkDesignView
        Nothing -> internalError
    Nothing -> runJSONGenT $ value "logged" False

-- please treat this function like a public query form, it's not secure
handleContactUs :: Kontrakcja m => m KontraLink
handleContactUs = do
  Context{..} <- getContext
  fname   <- getField' "firstname"
  lname   <- getField' "lastname"
  email   <- getField' "email"
  message <- getField' "message"
  plan    <- getField' "plan"

  let uid = maybe "user not logged in" ((++) "user with id " . show . userid) ctxmaybeuser
      content = "<p>Hi there!</p>" ++
                "<p>Someone requested information from the payments form.</p>" ++
                "<p>Name: " ++ fname ++ " " ++ lname ++ "</p>" ++
                "<p>Email: " ++ email ++ "</p>" ++
                "<p>Message: \n" ++ message ++ "</p>" ++
                "<p>Looking at plan: " ++ plan ++ "</p>" ++
                "<p>" ++ uid ++ "</p>" ++
                "<p>Have a good one!</p>"

  scheduleEmailSendout ctxmailsconfig $ emptyMail {
            to = [MailAddress { fullname = "info@scrive.com", email = "info@scrive.com" }]
          , title = "Contact request (" ++ plan ++ ")"
          , content = content
      }
  return $ LoopBack