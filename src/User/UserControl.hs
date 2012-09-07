module User.UserControl where

import Control.Monad.State
import Data.Functor
import Data.Maybe
import Happstack.Server hiding (simpleHTTP)
import Text.JSON (JSValue(..), toJSObject, showJSON)

import ActionQueue.Core
import ActionQueue.EmailChangeRequest
import ActionQueue.PasswordReminder
import ActionQueue.UserAccountRequest
import AppView
import Crypto.RNG
import DB hiding (update, query)
import Doc.Action
import Company.Model
import Control.Logic
import InputValidation
import Kontra
import KontraLink
import MagicHash (MagicHash)
import Mails.SendMail
import MinutesTime
import Happstack.Fields
import Utils.Monad
import Utils.Read
import Redirect
import Templates.Templates
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

handleUserGet :: Kontrakcja m => m (Either KontraLink Response)
handleUserGet = checkUserTOSGet $ do
    ctx <- getContext
    createcompany <- isFieldSet "createcompany"  --we could dump this stupid flag if we improved javascript validation
    case (ctxmaybeuser ctx) of
         Just user -> do
           mcompany <- getCompanyForUser user
           showUser user mcompany createcompany >>= renderFromBody kontrakcja
         Nothing -> sendRedirect $ LinkLogin (ctxlocale ctx) NotLogged

handleUserPost :: Kontrakcja m => m KontraLink
handleUserPost = do
  guardLoggedIn
  createcompany <- isFieldSet "createcompany"
  changeemail <- isFieldSet "changeemail"
  mlink <- case True of
             _ | createcompany -> Just <$> handleCreateCompany
             _ | changeemail -> Just <$> handleRequestChangeEmail
             _ -> return Nothing

  --whatever happens run the update in case they changed things in other places
  ctx <- getContext
  user' <- guardJust $ ctxmaybeuser ctx
  --requery for the user as they may have been upgraded
  user <- guardJustM $ dbQuery $ GetUserByID (userid user')
  infoUpdate <- getUserInfoUpdate
  _ <- dbUpdate $ SetUserInfo (userid user) (infoUpdate $ userinfo user)
  _ <- dbUpdate $ LogHistoryUserInfoChanged (userid user) (ctxipnumber ctx) (ctxtime ctx)
                                               (userinfo user) (infoUpdate $ userinfo user)
                                               (userid <$> ctxmaybeuser ctx)
  mcompany <- getCompanyForUser user
  case (useriscompanyadmin user, mcompany) of
    (True, Just company) -> do
      companyinfoupdate <- getCompanyInfoUpdate
      _ <- dbUpdate $ SetCompanyInfo (companyid company) (companyinfoupdate $ companyinfo company)
      return ()
    _ -> return ()

  case mlink of
    Just link -> return link
    Nothing -> do
       addFlashM flashMessageUserDetailsSaved
       return $ LinkAccount

-- please treat this function like a public query form, it's not secure
handleRequestPhoneCall :: Kontrakcja m => m KontraLink
handleRequestPhoneCall = do
  Context{ctxmaybeuser} <- getContext
  memail <- getOptionalField asValidEmail "email"
  mphone <-  getOptionalField asValidPhone "phone"
  case (memail, mphone) of
    (Just email, Just phone) -> do
      user <- guardJustM $ dbQuery $ GetUserByEmail (Email email)
      --only set the phone number if they're actually logged in
      -- it is possible to request a phone call from the sign view without being logged in!
      -- this function could be called by anyone!
      when (isJust ctxmaybeuser && fmap userid ctxmaybeuser == Just (userid user)) $ do
        _ <- dbUpdate $ SetUserInfo (userid user) $ (userinfo user){ userphone = phone }
        return ()
      phoneMeRequest user phone
    _ -> return ()
  return $ LinkUpload

handleRequestChangeEmail :: Kontrakcja m => m KontraLink
handleRequestChangeEmail = do
  ctx <- getContext
  user <- guardJust $ ctxmaybeuser ctx
  mnewemail <- getRequiredField asValidEmail "newemail"
  mnewemailagain <- getRequiredField asValidEmail "newemailagain"
  case (Email <$> mnewemail, Email <$> mnewemailagain) of
    (Just newemail, Just newemailagain) | newemail == newemailagain -> do
       mexistinguser <- dbQuery $ GetUserByEmail newemail
       case mexistinguser of
         Just _existinguser ->
           sendChangeToExistingEmailInternalWarningMail user newemail
         Nothing ->
           sendRequestChangeEmailMail user newemail
       --so there's no info leaking show this flash either way
       addFlashM $ flashMessageChangeEmailMailSent newemail
    (Just newemail, Just newemailagain) | newemail /= newemailagain -> do
       addFlashM flashMessageMismatchedEmails
    _ -> return ()
  return $ LinkAccount

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

sendRequestChangeEmailMail :: Kontrakcja m => User -> Email -> m ()
sendRequestChangeEmailMail user newemail = do
  ctx <- getContext
  changeemaillink <- newEmailChangeRequestLink (userid user) newemail
  mail <- mailEmailChangeRequest (ctxhostpart ctx) user newemail changeemaillink
  scheduleEmailSendout (ctxmailsconfig ctx)
                        (mail{to = [MailAddress{
                                    fullname = getFullName user
                                  , email = unEmail newemail }]})

handleCreateCompany :: Kontrakcja m => m KontraLink
handleCreateCompany = do
  ctx <- getContext
  user <- guardJust $ ctxmaybeuser ctx
  company <- dbUpdate $ CreateCompany Nothing
  mailapikey <- random
  _ <- dbUpdate $ SetCompanyMailAPIKey (companyid company) mailapikey 1000
  _ <- dbUpdate $ SetUserCompany (userid user) (Just $ companyid company)
  _ <- dbUpdate $ SetUserCompanyAdmin (userid user) True
  upgradeduser <- guardJustM $ dbQuery $ GetUserByID $ userid user
  _ <- addUserCreateCompanyStatEvent (ctxtime ctx) upgradeduser
  _ <- dbUpdate $ LogHistoryDetailsChanged (userid user) (ctxipnumber ctx) (ctxtime ctx)
                                              [("is_company_admin", "false", "true")]
                                              (Just $ userid user)
  companyinfoupdate <- getCompanyInfoUpdate -- This is redundant to standard usage - bu I want to leave it here because of consistency
  _ <- dbUpdate $ SetCompanyInfo (companyid company) (companyinfoupdate $ companyinfo company)
  addFlashM flashMessageCompanyCreated
  return LoopBack

handleGetChangeEmail :: Kontrakcja m => UserID -> MagicHash -> m (Either KontraLink Response)
handleGetChangeEmail uid hash = withUserGet $ do
  mnewemail <- getEmailChangeRequestNewEmail uid hash
  case mnewemail of
    Nothing -> addFlashM $ flashMessageProblemWithEmailChange
    Just newemail -> addFlashM $ modalDoYouWantToChangeEmail newemail
  Context{ctxmaybeuser = Just user} <- getContext
  mcompany <- getCompanyForUser user
  content <- showUser user mcompany False
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

handleUsageStatsForUser :: Kontrakcja m => m (Either KontraLink Response)
handleUsageStatsForUser = withUserGet $ do
  Context{ctxmaybeuser = Just user} <- getContext
  showUsageStats user >>= renderFromBody kontrakcja

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
      return $ JSObject $ toJSObject [("list", companyStatsDayToJSON totalS statsByDay),
                                      ("paging", JSObject $ toJSObject [
                                        ("pageSize",showJSON (1000::Int)),
                                        ("pageCurrent", showJSON (0::Int)),
                                        ("itemMin",showJSON $ (0::Int)),
                                        ("itemMax",showJSON $ (length statsByDay) - 1)])]
    else do
      (statsByDay, _) <- getUsageStatsForUser (userid user) som sixm
      return $ JSObject $ toJSObject [("list", userStatsDayToJSON statsByDay),
                                      ("paging", JSObject $ toJSObject [
                                        ("pageSize",showJSON (1000::Int)),
                                        ("pageCurrent", showJSON (0::Int)),
                                        ("itemMin",showJSON $ (0::Int)),
                                        ("itemMax",showJSON $ (length statsByDay) - 1)])]

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
    return $ JSObject $ toJSObject [("list", companyStatsMonthToJSON totalS statsByMonth),
                                    ("paging", JSObject $ toJSObject [
                                        ("pageSize",showJSON (1000::Int)),
                                        ("pageCurrent", showJSON (0::Int)),
                                        ("itemMin",showJSON $ (0::Int)),
                                        ("itemMax",showJSON $ (length statsByMonth) - 1)])]
    else do
    (_, statsByMonth) <- getUsageStatsForUser (userid user) som sixm
    return $ JSObject $ toJSObject [("list", userStatsMonthToJSON statsByMonth),
                                    ("paging", JSObject $ toJSObject [
                                        ("pageSize",showJSON (1000::Int)),
                                        ("pageCurrent", showJSON (0::Int)),
                                        ("itemMin",showJSON $ (0::Int)),
                                        ("itemMax",showJSON $ (length statsByMonth) - 1)])]


handleGetUserMailAPI :: Kontrakcja m => m (Either KontraLink Response)
handleGetUserMailAPI = withUserGet $ do
    Context{ctxmaybeuser = Just user@User{userid}} <- getContext
    mapi <- dbQuery $ GetUserMailAPI userid
    mcapi <- maybe (return Nothing) (dbQuery . GetCompanyMailAPI) $ usercompany user
    showUserMailAPI user mapi mcapi >>= renderFromBody kontrakcja

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

handleGetUserSecurity :: Kontrakcja m => m Response
handleGetUserSecurity = do
    ctx <- getContext
    case (ctxmaybeuser ctx) of
         Just user -> showUserSecurity user >>= renderFromBody kontrakcja
         Nothing -> sendRedirect $ LinkLogin (ctxlocale ctx) NotLogged

handlePostUserLocale :: Kontrakcja m => m KontraLink
handlePostUserLocale = do
  ctx <- getContext
  user <- guardJust $ ctxmaybeuser ctx
  mregion <- readField "region"
  _ <- dbUpdate $ SetUserSettings (userid user) $ (usersettings user) {
           locale = maybe (locale $ usersettings user) mkLocaleFromRegion mregion
         }
  referer <- getField "referer"
  case referer of
    Just _ -> return BackToReferer
    Nothing -> return LoopBack

handlePostUserSecurity :: Kontrakcja m => m KontraLink
handlePostUserSecurity = do
  ctx <- getContext
  case (ctxmaybeuser ctx) of
    Just user -> do
      moldpassword <- getOptionalField asDirtyPassword "oldpassword"
      mpassword <- getOptionalField asValidPassword "password"
      mpassword2 <- getOptionalField asDirtyPassword "password2"
      case (moldpassword, mpassword, mpassword2) of
        (Just oldpassword, Just password, Just password2) ->
          case (verifyPassword (userpassword user) oldpassword,
                  checkPasswordsMatch password password2) of
            (False,_) -> do
              _ <- dbUpdate $ LogHistoryPasswordSetupReq (userid user) (ctxipnumber ctx) (ctxtime ctx) (userid <$> ctxmaybeuser ctx)
              addFlashM flashMessageBadOldPassword
            (_, Left f) -> do
              _ <- dbUpdate $ LogHistoryPasswordSetupReq (userid user) (ctxipnumber ctx) (ctxtime ctx) (userid <$> ctxmaybeuser ctx)
              addFlashM f
            _ ->  do
              passwordhash <- createPassword password
              _ <- dbUpdate $ SetUserPassword (userid user) passwordhash
              _ <- dbUpdate $ LogHistoryPasswordSetup (userid user) (ctxipnumber ctx) (ctxtime ctx) (userid <$> ctxmaybeuser ctx)
              addFlashM flashMessageUserDetailsSaved
        _ | isJust moldpassword || isJust mpassword || isJust mpassword2 -> do
              _ <- dbUpdate $ LogHistoryPasswordSetupReq (userid user) (ctxipnumber ctx) (ctxtime ctx) (userid <$> ctxmaybeuser ctx)
              addFlashM flashMessageMissingRequiredField
        _ -> return ()
      mregion <- readField "region"
      footer <- getField "customfooter"
      footerCheckbox <- isFieldSet "footerCheckbox"
      _ <- dbUpdate $ SetUserSettings (userid user) $ (usersettings user) {
             locale = maybe (locale $ usersettings user) mkLocaleFromRegion mregion,
             customfooter = footer <| footerCheckbox |> Nothing
           }
      return LinkAccountSecurity
    Nothing -> return $ LinkLogin (ctxlocale ctx) NotLogged

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
  al <- newUserAccountRequestLink $ userid user
  mail <- newUserMail (ctxhostpart ctx) (getEmail user) (getSmartName user) al
  scheduleEmailSendout (ctxmailsconfig ctx) $ mail { to = [MailAddress { fullname = getSmartName user, email = getEmail user }]}
  return ()

createNewUserByAdmin :: Kontrakcja m => String -> (String, String) -> Maybe String -> Maybe (CompanyID, Bool) -> Locale -> m (Maybe User)
createNewUserByAdmin email names custommessage mcompanydata locale = do
    ctx <- getContext
    muser <- createUser (Email email) names (fst <$> mcompanydata) locale
    case muser of
         Just user -> do
             case mcompanydata of
               Just (_, admin) -> do
                 _ <- dbUpdate $ SetUserCompanyAdmin (userid user) admin
                 return ()
               Nothing -> return ()
             let fullname = composeFullName names
             now <- liftIO $ getMinutesTime
             _ <- dbUpdate $ SetInviteInfo (userid <$> ctxmaybeuser ctx) now Admin (userid user)
             chpwdlink <- newUserAccountRequestLink $ userid user
             mail <- mailNewAccountCreatedByAdmin ctx (getLocale user) fullname email chpwdlink custommessage
             scheduleEmailSendout (ctxmailsconfig ctx) $ mail { to = [MailAddress { fullname = fullname, email = email }]}
             return muser
         Nothing -> return muser

handleAcceptTOSGet :: Kontrakcja m => m (Either KontraLink Response)
handleAcceptTOSGet = withUserGet $ do
    renderFromBody kontrakcja =<< pageAcceptTOS

handleAcceptTOSPost :: Kontrakcja m => m KontraLink
handleAcceptTOSPost = withUserPost $ do
  Context{ctxmaybeuser = Just User{userid}, ctxtime, ctxipnumber} <- getContext
  tos <- getDefaultedField False asValidCheckBox "tos"
  case tos of
    Just True -> do
      _ <- dbUpdate $ AcceptTermsOfService userid ctxtime
      user <- guardJustM $ dbQuery $ GetUserByID userid
      _ <- addUserSignTOSStatEvent user
      _ <- dbUpdate $ LogHistoryTOSAccept userid ctxipnumber ctxtime (Just userid)
      addFlashM flashMessageUserDetailsSaved
      return LinkUpload
    Just False -> do
      addFlashM flashMessageMustAcceptTOS
      return LinkAcceptTOS
    Nothing -> return LinkAcceptTOS

handleQuestion :: Kontrakcja m => m KontraLink
handleQuestion = do
    ctx <- getContext
    name <- getField "name"
    memail <- getDefaultedField "" asValidEmail "email"
    phone <- getField "phone"
    message <- getField "message"
    case memail of
         Nothing -> return LoopBack
         Just email -> do
             let content = "name: "    ++ fromMaybe "" name ++ "<BR/>"
                        ++ "email: "   ++ email ++ "<BR/>"
                        ++ "phone "    ++ fromMaybe "" phone ++ "<BR/>"
                        ++ "message: " ++ fromMaybe "" message
             scheduleEmailSendout (ctxmailsconfig ctx) $ emptyMail {
                   to = [MailAddress { fullname = "info@skrivapa.se", email = "info@skrivapa.se" }]
                 , title = "Question"
                 , content = content
             }
             addFlashM flashMessageThanksForTheQuestion
             return LoopBack

handleAccountSetupGet :: Kontrakcja m => UserID -> MagicHash -> m Response
handleAccountSetupGet uid token = do
  user <- guardJustM404 $ getUserAccountRequestUser uid token
  let locale = getLocale user
  switchLocale locale
  if isJust $ userhasacceptedtermsofservice user
    then respond404
    else do
      addFlashM $ modalAccountSetup (LinkAccountCreated uid token)
                                    (getFirstName user)
                                    (getLastName user)
      sendRedirect $ LinkHome locale

handleAccountSetupPost :: Kontrakcja m => UserID -> MagicHash -> m KontraLink
handleAccountSetupPost uid token = do
  user <- guardJustM404 $ getUserAccountRequestUser uid token
  switchLocale $ getLocale user
  if isJust $ userhasacceptedtermsofservice user
    then addFlashM flashMessageUserAlreadyActivated
    else do
      mfstname <- getRequiredField asValidName "fstname"
      msndname <- getRequiredField asValidName "sndname"
      mactivateduser <- handleActivate mfstname msndname user AccountRequest
      case mactivateduser of
        Nothing -> addFlashM $ modalAccountSetup (LinkAccountCreated uid token)
                                                 (fromMaybe "" mfstname)
                                                 (fromMaybe "" msndname)
        Just (_, docs) -> do
          _ <- dbUpdate $ DeleteAction userAccountRequest uid
          forM_ docs (\d -> postDocumentPreparationChange d "mailapi")
          addFlashM flashMessageUserActivated
  getHomeOrUploadLink

{- |
    This is where we get to when the user clicks the link in their password reminder
    email.  This'll show them the usual landing page, but with a modal dialog
    for changing their password.
-}
handlePasswordReminderGet :: Kontrakcja m => UserID -> MagicHash -> m Response
handlePasswordReminderGet uid token = do
  muser <- getPasswordReminderUser uid token
  case muser of
    Just user -> do
      switchLocale (getLocale user)
      addFlashM $ modalNewPasswordView uid token
      sendRedirect LinkUpload
    Nothing -> do
      addFlashM flashMessagePasswordChangeLinkNotValid
      sendRedirect =<< getHomeOrUploadLink

handlePasswordReminderPost :: Kontrakcja m => UserID -> MagicHash -> m KontraLink
handlePasswordReminderPost uid token = do
  muser <- getPasswordReminderUser uid token
  case muser of
    Just user -> do
      switchLocale (getLocale user)
      Context{ctxtime, ctxipnumber, ctxmaybeuser} <- getContext
      mpassword <- getRequiredField asValidPassword "password"
      mpassword2 <- getRequiredField asDirtyPassword "password2"
      case (mpassword, mpassword2) of
        (Just password, Just password2) -> do
          case (checkPasswordsMatch password password2) of
            Right () -> do
              _ <- dbUpdate $ DeleteAction passwordReminder uid
              passwordhash <- createPassword password
              _ <- dbUpdate $ SetUserPassword (userid user) passwordhash
              _ <- dbUpdate $ LogHistoryPasswordSetup (userid user) ctxipnumber ctxtime (userid <$> ctxmaybeuser)
              addFlashM flashMessageUserPasswordChanged
              _ <- addUserLoginStatEvent ctxtime user
              logUserToContext $ Just user
              return LinkUpload
            Left flash -> do
              _ <- dbUpdate $ LogHistoryPasswordSetupReq (userid user) ctxipnumber (ctxtime) (userid <$> ctxmaybeuser)
              addFlashM flash
              addFlashM $ modalNewPasswordView uid token
              getHomeOrUploadLink
        _ -> do
          _ <- dbUpdate $ LogHistoryPasswordSetupReq (userid user) ctxipnumber ctxtime (userid <$> ctxmaybeuser)
          addFlashM $ modalNewPasswordView uid token
          getHomeOrUploadLink
    Nothing   -> do
      addFlashM flashMessagePasswordChangeLinkNotValid
      getHomeOrUploadLink

{- |
   Fetch the xtoken param and double read it. Once as String and once as MagicHash.
 -}
readXToken :: Kontrakcja m => m (Either String MagicHash)
readXToken = do
  mxtoken <- join <$> (fmap maybeRead) <$> readField "xtoken"
  return $ maybe (Left $ "xtoken read failure" ) Right mxtoken

guardXToken :: Kontrakcja m => m ()
guardXToken = do
  Context { ctxxtoken } <- getContext
  xtoken <- guardRightM readXToken
  unless (xtoken == ctxxtoken) $ do
    Log.debug $ "xtoken failure: session: " ++ show ctxxtoken
      ++ " param: " ++ show xtoken
    internalError
