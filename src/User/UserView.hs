module User.UserView (
    -- pages
    viewSubaccounts,
    viewFriends,
    showUser,
    showUserSecurity,
    showUserMailAPI,
    pageAcceptTOS,
    activatePageViewNotValidLink,

    -- mails
    newUserMail,
    inviteSubaccountMail,
    viralInviteMail,
    mailNewAccountCreatedByAdmin,
    mailAccountCreatedBySigningContractReminder,
    mailAccountCreatedBySigningOfferReminder,
    resetPasswordMail,

    mailInviteUserAsSubaccount,
    mailSubaccountAccepted,

    -- modals
    modalWelcomeToSkrivaPa,
    modalAccountSetup,
    modalAccountRemoval,
    modalAccountRemoved,
    modalInviteUserAsSubaccount,
    modalDoYouWantToBeSubaccount,

    -- flash messages
    flashMessageLoginRedirectReason,
    flashMessageUserDetailsSaved,
    flashMessageNoAccountType,
    flashMessageInvalidAccountType,
    flashMessageMustAcceptTOS,
    flashMessageBadOldPassword,
    flashMessagePasswordsDontMatch,
    flashMessageUserPasswordChanged,
    flashMessagePasswordChangeLinkNotValid,
    flashMessageUserWithSameEmailExists,
    flashMessageViralInviteSent,
    flashMessageOtherUserSentInvitation,
    flashMessageNoRemainedInvitationEmails,
    flashMessageActivationLinkNotValid,
    flashMessageUserActivated,
    flashMessageUserAlreadyActivated,
    flashMessageChangePasswordEmailSend,
    flashMessageNoRemainedPasswordReminderEmails,
    flashMessageNewActivationLinkSend,
    flashMessageUserSignupDone,
    flashMessageThanksForTheQuestion,
    flashMessageUserInvitedAsSubaccount,
    flashMessageUserHasBecomeSubaccount,
    flashMessageUserHasLiveDocs,
    flashMessageAccountsDeleted,

    --modals
    modalNewPasswordView,

    --utils
    userBasicFields) where

import Control.Applicative ((<$>))
import Control.Monad.Reader
import Data.Maybe
import ActionSchedulerState
import Happstack.State (query)
import Kontra
import KontraLink
import Mails.SendMail(Mail, emptyMail, title, content)
import Misc
import Templates.Templates
import Templates.TemplatesUtils
import Text.StringTemplate.GenericStandard()
import qualified Data.ByteString as BS
import qualified Data.ByteString.UTF8 as BS
import ListUtil
import FlashMessage
import Util.HasSomeUserInfo

showUser :: KontrakcjaTemplates -> User -> IO String
showUser templates user = renderTemplate templates "showUser" $ do
    userFields user
    field "linkaccount" $ show LinkAccount

userFields :: User -> Fields
userFields user = do
    let fullname          = BS.toString $ getFullName user
        fullnameOrEmail   = BS.toString $ getSmartName user
        fullnamePlusEmail = if null fullname
                            then              "<" ++ (BS.toString $ getEmail user) ++ ">"
                            else fullname ++ " <" ++ (BS.toString $ getEmail user) ++ ">"
    field "id" $ show $ userid user
    field "fstname" $ getFirstName user
    field "sndname" $ getLastName user
    field "email" $ getEmail user
    field "personalnumber" $ getPersonalNumber user
    field "address" $ useraddress $ userinfo user
    field "city" $ usercity $ userinfo user
    field "country" $ usercountry $ userinfo user
    field "zip" $ userzip $ userinfo user
    field "phone" $ userphone $ userinfo user
    field "mobile" $ usermobile $ userinfo user
    field "companyname" $ getCompanyName user
    field "companyposition" $ usercompanyposition $ userinfo user
    field "companynumber" $ getCompanyNumber user
    field "userimagelink" False
    field "companyimagelink" False
    field "fullname" $ fullname
    field "fullnameOrEmail" $ fullnameOrEmail
    field "fullnamePlusEmail" $ fullnamePlusEmail
    field "hassupervisor" $ isJust $ usersupervisor user

    --field "invoiceaddress" $ BS.toString $ useraddress $ userinfo user
    menuFields user

showUserSecurity :: KontrakcjaTemplates -> User -> IO String
showUserSecurity templates user = renderTemplate templates "showUserSecurity" $ do
    field "linksecurity" $ show LinkSecurity
    field "fstname" $ getFirstName user
    field "sndname" $ getLastName user
    field "userimagelink" False
    field "lang" $ do
        field "en" $ LANG_EN == (lang $ usersettings user)
        field "se" $ LANG_SE == (lang $ usersettings user)
    menuFields user

showUserMailAPI :: KontrakcjaTemplates -> User -> IO String
showUserMailAPI templates user@User{usermailapi} =
    renderTemplate templates "showUserMailAPI" $ do
        field "linkmailapi" $ show LinkUserMailAPI
        field "mailapienabled" $ maybe False (const True) usermailapi
        field "mailapikey" $ show . umapiKey <$> usermailapi
        field "mapidailylimit" $ umapiDailyLimit <$> usermailapi
        field "mapisenttoday" $ umapiSentToday <$> usermailapi
        menuFields user

pageAcceptTOS :: KontrakcjaTemplates -> IO String
pageAcceptTOS templates =
  renderTemplate templates "pageAcceptTOS" ()

viewFriends :: KontrakcjaTemplates -> PagedList User -> User -> IO String
viewFriends templates friends user =
  renderTemplate templates "viewFriends" $ do
    field "friends" $ markParity $ map userFields $ list friends
    field "currentlink" $ show $ LinkSharing $ params friends
    menuFields user
    pagedListFields friends

menuFields :: User -> Fields
menuFields user = do
    field "issubaccounts" $ isAbleToHaveSubaccounts user

viewSubaccounts :: (TemplatesMonad m) => User -> PagedList User -> m String
viewSubaccounts user subusers =
  renderTemplateM "viewSubaccounts" $ do
    field "subaccounts" $ markParity $ map userFields $ list subusers
    field "currentlink" $ show $ LinkSubaccount $ params subusers
    field "user" $ userFields user
    pagedListFields subusers

activatePageViewNotValidLink :: KontrakcjaTemplates -> String -> IO String
activatePageViewNotValidLink templates email =
  renderTemplate templates "activatePageViewNotValidLink" $ field "email" email


resetPasswordMail :: KontrakcjaTemplates -> String -> User -> KontraLink -> IO Mail
resetPasswordMail templates hostname user setpasslink = do
  title   <- renderTemplate templates "passwordChangeLinkMailTitle" ()
  content <- (renderTemplate templates "passwordChangeLinkMailContent" $ do
    field "personname"   $ getFullName user
    field "passwordlink" $ show setpasslink
    field "ctxhostpart"  $ hostname
    ) >>= wrapHTML templates
  return $ emptyMail { title = BS.fromString title, content = BS.fromString content }


newUserMail :: KontrakcjaTemplates -> String -> BS.ByteString -> BS.ByteString -> KontraLink -> Bool -> IO Mail
newUserMail templates hostpart emailaddress personname activatelink vip = do
  title   <- renderTemplate templates "newUserMailTitle" ()
  content <- (renderTemplate templates "newUserMailContent" $ do
    field "personname"   $ BS.toString personname
    field "email"        $ BS.toString emailaddress
    field "activatelink" $ show activatelink
    field "ctxhostpart"  $ hostpart
    field "vip"            vip
    ) >>= wrapHTML templates
  return $ emptyMail { title = BS.fromString title, content = BS.fromString content }


inviteSubaccountMail :: KontrakcjaTemplates -> String -> BS.ByteString -> BS.ByteString -> BS.ByteString -> BS.ByteString -> KontraLink-> IO Mail
inviteSubaccountMail  templates hostpart supervisorname companyname emailaddress personname setpasslink = do
  title   <- renderTemplate templates "inviteSubaccountMailTitle" ()
  content <- (renderTemplate templates "inviteSubaccountMailContent" $ do
    field "personname"     $ BS.toString personname
    field "email"          $ BS.toString emailaddress
    field "passwordlink"   $ show setpasslink
    field "supervisorname" $ BS.toString supervisorname
    field "companyname"    $ BS.toString companyname
    field "ctxhostpart"    $ hostpart
    ) >>= wrapHTML templates
  return $ emptyMail { title = BS.fromString title, content = BS.fromString content }


viralInviteMail :: KontrakcjaTemplates -> Context -> BS.ByteString -> KontraLink -> IO Mail
viralInviteMail templates ctx invitedemail setpasslink = do
  let invitername = BS.toString $ maybe BS.empty getSmartName (ctxmaybeuser ctx)
  title   <- renderTemplate templates "mailViralInviteTitle" $ field "invitername" invitername
  content <- (renderTemplate templates "mailViralInviteContent" $ do
    field "email"        $ BS.toString invitedemail
    field "invitername"  $ invitername
    field "ctxhostpart"  $ ctxhostpart ctx
    field "passwordlink" $ show setpasslink
    ) >>= wrapHTML templates
  return $ emptyMail { title = BS.fromString title, content = BS.fromString content }


mailNewAccountCreatedByAdmin :: KontrakcjaTemplates -> Context-> BS.ByteString -> BS.ByteString -> KontraLink -> Maybe String -> IO Mail
mailNewAccountCreatedByAdmin templates ctx personname email setpasslink custommessage = do
  title   <- renderTemplate templates "mailNewAccountCreatedByAdminTitle" ()
  content <- (renderTemplate templates "mailNewAccountCreatedByAdminContent" $ do
    field "personname"    $ BS.toString personname
    field "email"         $ BS.toString email
    field "passwordlink"  $ show setpasslink
    field "creatorname"   $ BS.toString $ maybe BS.empty getSmartName (ctxmaybeuser ctx)
    field "ctxhostpart"   $ ctxhostpart ctx
    field "custommessage"   custommessage
    ) >>= wrapHTML templates
  return $ emptyMail { title = BS.fromString title, content = BS.fromString content }

mailAccountCreatedBySigningContractReminder :: KontrakcjaTemplates -> String -> BS.ByteString -> BS.ByteString -> KontraLink -> IO Mail
mailAccountCreatedBySigningContractReminder =
    mailAccountCreatedBySigning' "mailAccountBySigningContractReminderTitle"
                                 "mailAccountBySigningContractReminderContent"

mailAccountCreatedBySigningOfferReminder :: KontrakcjaTemplates -> String -> BS.ByteString -> BS.ByteString -> KontraLink -> IO Mail
mailAccountCreatedBySigningOfferReminder =
    mailAccountCreatedBySigning' "mailAccountBySigningOfferReminderTitle"
                                 "mailAccountBySigningOfferReminderContent"

mailAccountCreatedBySigning' :: String -> String -> KontrakcjaTemplates -> String -> BS.ByteString -> BS.ByteString -> KontraLink -> IO Mail
mailAccountCreatedBySigning' title_template content_template templates hostpart doctitle personname activationlink = do
    title <- renderTemplate templates title_template ()
    content <- (renderTemplate templates content_template $ do
        field "personname"     $ BS.toString personname
        field "ctxhostpart"    $ hostpart
        field "documenttitle"  $ BS.toString doctitle
        field "activationlink" $ show activationlink
        ) >>= wrapHTML templates
    return $ emptyMail { title = BS.fromString title, content = BS.fromString content }

mailInviteUserAsSubaccount :: (TemplatesMonad m) => Context -> User -> User -> m Mail
mailInviteUserAsSubaccount ctx invited supervisor = do
    templates <- getTemplates
    title <- renderTemplateM "mailInviteUserAsSubaccountTitle" ()
    content <- (liftIO $ renderTemplate templates "mailInviteUserAsSubaccountContent" $ do
                   field "hostpart" (ctxhostpart ctx)
                   field "supervisor" $ userFields supervisor
                   field "invited" $ userFields invited
        ) >>= (liftIO . wrapHTML templates)
    return $ emptyMail { title = BS.fromString title, content = BS.fromString content }

mailSubaccountAccepted :: (TemplatesMonad m) => Context -> User -> User -> m Mail
mailSubaccountAccepted ctx invited supervisor = do
    templates <- getTemplates
    title <- renderTemplateM "mailSubaccountAcceptedTitle" ()
    content <- (liftIO $ renderTemplate templates "mailSubaccountAcceptedContent" $ do
                   field "hostpart" (ctxhostpart ctx)
                   field "user" $ userFields supervisor
                   field "invited" $ userFields invited
        ) >>= (liftIO . wrapHTML templates)
    return $ emptyMail { title = BS.fromString title, content = BS.fromString content }

-------------------------------------------------------------------------------

modalInviteUserAsSubaccount :: TemplatesMonad m => String -> String -> String -> m FlashMessage
modalInviteUserAsSubaccount fstname sndname email =
    toModal <$> (renderTemplateM "modalInviteUserAsSubaccount" $ do
      field "email" email
      field "fstname" fstname
      field "sndname" sndname)

modalWelcomeToSkrivaPa :: TemplatesMonad m => m FlashMessage
modalWelcomeToSkrivaPa =
    toModal <$> renderTemplateM "modalWelcomeToSkrivaPa" ()

modalAccountSetup :: MonadIO m => Maybe User -> KontraLink -> m FlashMessage
modalAccountSetup muser signuplink = do
    msupervisor <- case msupervisorid of
        Just sid -> query $ GetUserByUserID $ UserID $ unSupervisorID sid
        Nothing  -> return Nothing
    return $ toFlashTemplate Modal "modalAccountSetup" $
        supervisorfields msupervisor ++ [
              ("fstname", showUserField userfstname)
            , ("sndname", showUserField usersndname)
            , ("companyname", showUserField usercompanyname)
            , ("companyposition", showUserField usercompanyposition)
            , ("phone", showUserField userphone)
            , ("signuplink", show signuplink)
            ]
    where
        showUserField f = maybe "" (BS.toString . f . userinfo) muser
        msupervisorid = join (usersupervisor <$> muser)
        supervisorfields Nothing = []
        supervisorfields (Just svis) = [
              ("hassupervisor", "true")
            , ("supervisorcompany", BS.toString $ getCompanyName svis)
            , ("supervisoraccounttype", supervisoraccounttype)
            , (supervisoraccounttype, "true")
            ]
            where
                supervisoraccounttype = show $ accounttype $ usersettings svis

modalAccountRemoval :: TemplatesMonad m => BS.ByteString -> KontraLink -> KontraLink -> m FlashMessage
modalAccountRemoval doctitle activationlink removallink = do
    toModal <$> (renderTemplateM "modalAccountRemoval" $ do
        field "documenttitle"  $ BS.toString doctitle
        field "activationlink" $ show activationlink
        field "removallink"    $ show removallink)

modalAccountRemoved :: TemplatesMonad m => BS.ByteString -> m FlashMessage
modalAccountRemoved doctitle = do
    toModal <$> (renderTemplateM "modalAccountRemoved" $ do
        field "documenttitle"  $ BS.toString doctitle)

flashMessageThanksForTheQuestion :: TemplatesMonad m => m FlashMessage
flashMessageThanksForTheQuestion =
    toFlashMsg OperationDone <$> renderTemplateM "flashMessageThanksForTheQuestion" ()

flashMessageLoginRedirectReason :: TemplatesMonad m => LoginRedirectReason -> m (Maybe FlashMessage)
flashMessageLoginRedirectReason reason =
  case reason of
       LoginTry             -> return Nothing
       NotLogged            -> render "notlogged"
       NotLoggedAsSuperUser -> render "notsu"
       InvalidLoginInfo _   -> render "invloginfo"
  where
    render msg = Just . toFlashMsg OperationFailed <$>
      (renderTemplateM "flashMessageLoginPageRedirectReason" $ field msg True)


flashMessageUserDetailsSaved :: TemplatesMonad m => m FlashMessage
flashMessageUserDetailsSaved =
  toFlashMsg OperationDone <$> renderTemplateM "flashMessageUserDetailsSaved" ()


flashMessageNoAccountType :: TemplatesMonad m => m FlashMessage
flashMessageNoAccountType =
    toFlashMsg OperationFailed <$> renderTemplateM "flashMessageNoAccountType" ()

flashMessageInvalidAccountType :: TemplatesMonad m => m FlashMessage
flashMessageInvalidAccountType =
    toFlashMsg OperationFailed <$> renderTemplateM "flashMessageInvalidAccountType" ()

flashMessageMustAcceptTOS :: TemplatesMonad m => m FlashMessage
flashMessageMustAcceptTOS =
  toFlashMsg SigningRelated <$> renderTemplateM "flashMessageMustAcceptTOS" ()


flashMessageBadOldPassword :: TemplatesMonad m => m FlashMessage
flashMessageBadOldPassword =
  toFlashMsg OperationFailed <$> renderTemplateM "flashMessageBadOldPassword" ()


flashMessagePasswordsDontMatch :: TemplatesMonad m => m FlashMessage
flashMessagePasswordsDontMatch =
  toFlashMsg OperationFailed <$> renderTemplateM "flashMessagePasswordsDontMatch" ()


flashMessageUserPasswordChanged :: TemplatesMonad m => m FlashMessage
flashMessageUserPasswordChanged =
  toFlashMsg OperationDone <$> renderTemplateM "flashMessageUserPasswordChanged" ()

flashMessageUserHasBecomeSubaccount :: TemplatesMonad m => User -> m FlashMessage
flashMessageUserHasBecomeSubaccount supervisor =
  toFlashMsg OperationDone <$> (renderTemplateM "flashMessageUserHasBecomeSubaccount" $ do
    field "supervisor" $ userFields supervisor)

flashMessageUserHasLiveDocs :: TemplatesMonad m => m FlashMessage
flashMessageUserHasLiveDocs =
  toFlashMsg OperationFailed <$> renderTemplateM "flashMessageUserHasLiveDocs" ()

flashMessageAccountsDeleted :: TemplatesMonad m => m FlashMessage
flashMessageAccountsDeleted =
  toFlashMsg OperationDone <$> renderTemplateM "flashMessageAccountsDeleted" ()

flashMessagePasswordChangeLinkNotValid :: TemplatesMonad m => m FlashMessage
flashMessagePasswordChangeLinkNotValid =
  toFlashMsg OperationFailed <$> renderTemplateM "flashMessagePasswordChangeLinkNotValid" ()


flashMessageUserWithSameEmailExists :: TemplatesMonad m => m FlashMessage
flashMessageUserWithSameEmailExists =
  toFlashMsg OperationFailed <$> renderTemplateM "flashMessageUserWithSameEmailExists" ()


flashMessageViralInviteSent :: TemplatesMonad m => m FlashMessage
flashMessageViralInviteSent =
  toFlashMsg SigningRelated <$> renderTemplateM "flashMessageViralInviteSent" ()

flashMessageOtherUserSentInvitation :: TemplatesMonad m => m FlashMessage
flashMessageOtherUserSentInvitation =
    toFlashMsg OperationFailed <$> renderTemplateM "flashMessageOtherUserSentInvitation" ()

flashMessageNoRemainedInvitationEmails :: TemplatesMonad m => m FlashMessage
flashMessageNoRemainedInvitationEmails =
    toFlashMsg OperationFailed <$> renderTemplateM "flashMessageNoRemainedInvitationEmails" ()

flashMessageActivationLinkNotValid :: TemplatesMonad m => m FlashMessage
flashMessageActivationLinkNotValid =
  toFlashMsg OperationFailed <$> renderTemplateM "flashMessageActivationLinkNotValid" ()


flashMessageUserActivated :: TemplatesMonad m => m FlashMessage
flashMessageUserActivated =
  toFlashMsg SigningRelated <$> renderTemplateM "flashMessageUserActivated" ()


flashMessageUserAlreadyActivated :: TemplatesMonad m => m FlashMessage
flashMessageUserAlreadyActivated =
  toFlashMsg OperationFailed <$> renderTemplateM "flashMessageUserAlreadyActivated" ()

flashMessageChangePasswordEmailSend :: TemplatesMonad m => m FlashMessage
flashMessageChangePasswordEmailSend =
  toFlashMsg OperationDone <$> renderTemplateM "flashMessageChangePasswordEmailSend" ()

flashMessageNoRemainedPasswordReminderEmails :: TemplatesMonad m => m FlashMessage
flashMessageNoRemainedPasswordReminderEmails =
    toFlashMsg OperationFailed <$> renderTemplateM "flashMessageNoRemainedPasswordReminderEmails" ()

flashMessageNewActivationLinkSend :: TemplatesMonad m => m FlashMessage
flashMessageNewActivationLinkSend =
  toFlashMsg OperationDone <$> renderTemplateM "flashMessageNewActivationLinkSend" ()


flashMessageUserSignupDone :: TemplatesMonad m => m FlashMessage
flashMessageUserSignupDone =
  toFlashMsg OperationDone <$> renderTemplateM "flashMessageUserSignupDone" ()

flashMessageUserInvitedAsSubaccount :: TemplatesMonad m => m FlashMessage
flashMessageUserInvitedAsSubaccount =
  toFlashMsg OperationDone <$> renderTemplateM "flashMessageUserInvitedAsSubaccount" ()

modalNewPasswordView :: TemplatesMonad m => ActionID -> MagicHash -> m FlashMessage
modalNewPasswordView aid hash = do
  toModal <$> (renderTemplateM "modalNewPasswordView" $ do
            field "linkchangepassword" $ show $ LinkPasswordReminder aid hash)

modalDoYouWantToBeSubaccount :: TemplatesMonad m => m FlashMessage
modalDoYouWantToBeSubaccount =
  toModal <$> renderTemplateM "modalDoYouWantToBeSubaccount" ()


-------------------------------------------------------------------------------

{- | Basic fields for the user  -}
userBasicFields :: User -> Fields
userBasicFields u = do
    field "id" $ show $ userid u
    field "fullname" $ getFullName u
    field "email" $ getEmail u
    field "company" $ getCompanyName u
    field "phone" $ userphone $ userinfo u
    field "TOSdate" $ maybe "-" show (userhasacceptedtermsofservice u)
