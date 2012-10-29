module User.UserView (
    -- pages
    userJSON,
    showAccount,
    pageAcceptTOS,
    activatePageViewNotValidLink,

    -- mails
    newUserMail,
    mailNewAccountCreatedByAdmin,
    resetPasswordMail,
    mailEmailChangeRequest,

    -- modals
    modalAccountSetup,
    modalDoYouWantToChangeEmail,

    -- flash messages
    flashMessageLoginRedirectReason,
    flashMessageUserDetailsSaved,
    flashMessageCompanyCreated,
    flashMessageNoAccountType,
    flashMessageInvalidAccountType,
    flashMessageMustAcceptTOS,
    flashMessageBadOldPassword,
    flashMessagePasswordsDontMatch,
    flashMessageUserPasswordChanged,
    flashMessagePasswordChangeLinkNotValid,
    flashMessageUserWithSameEmailExists,
    flashMessageActivationLinkNotValid,
    flashMessageUserActivated,
    flashMessageUserAlreadyActivated,
    flashMessageNewActivationLinkSend,
    flashMessageUserSignupDone,
    flashMessageThanksForTheQuestion,
    flashMessageChangeEmailMailSent,
    flashMessageMismatchedEmails,
    flashMessageProblemWithEmailChange,
    flashMessageProblemWithPassword,
    flashMessageYourEmailHasChanged,

    --modals
    modalNewPasswordView,
    modalUserSignupDone,

    --utils
    userBasicFields,
    menuFields,

    userStatsDayToJSON,
    userStatsMonthToJSON,
    companyStatsDayToJSON,
    companyStatsMonthToJSON
    ) where

import Control.Applicative ((<$>))
import Data.Maybe
import Company.Model
import Kontra
import KontraLink
import MagicHash (MagicHash)
import Mails.SendMail(Mail)
import Templates.Templates
import Templates.TemplatesUtils
import Text.StringTemplate.GenericStandard()
import FlashMessage
import Util.HasSomeCompanyInfo
import Util.HasSomeUserInfo
import User.Model
import MinutesTime
import Text.JSON
import Text.JSON.Gen
import Data.Either
import ScriveByMail.Model
import ScriveByMail.View
import qualified Templates.Fields as F
import Control.Logic

showAccount :: TemplatesMonad m => User -> Maybe Company -> m String
showAccount user mcompany = renderTemplate "showAccount" $ do
    F.value "companyAdmin" $ useriscompanyadmin user
    F.value "noCompany" $ isNothing mcompany
    
userJSON :: Monad m => User -> Maybe MailAPIInfo -> Maybe Company -> Maybe MailAPIInfo -> m JSValue
userJSON user mumailapi mcompany mcmailapi = runJSONGenT $ do
    value "id" $ show $ userid user
    value "fstname" $ getFirstName user
    value "sndname" $ getLastName user
    value "email" $ getEmail user
    value "personalnumber" $ getPersonalNumber user
    value "phone" $ userphone $ userinfo user
    value "mobile" $ usermobile $ userinfo user
    value "companyposition" $ usercompanyposition $ userinfo user
    value "usercompanyname" $ getCompanyName user
    value "usercompanynumber" $ getCompanyNumber user
    value "region" $ "gb" <| LANG_EN == (getLang user) |> "se"
    value "lang"   $ "en" <| LANG_EN == (getLang user) |> "se"
    value "footer" $ customfooter $ usersettings user
    valueM "mailapi" $ case (mumailapi) of
                            Nothing -> return JSNull
                            Just umailapi -> mailAPIInfoJSON umailapi
    valueM "company" $ case (mcompany) of
                            Nothing -> return JSNull
                            Just company -> companyJSON company mcmailapi

companyJSON :: Monad m => Company -> Maybe MailAPIInfo -> m JSValue
companyJSON company mcmailapi = runJSONGenT $ do
    value "companyid" $ show $ companyid company
    value "address" $ companyaddress $ companyinfo company
    value "city" $ companycity $ companyinfo company
    value "country" $ companycountry $ companyinfo company
    value "zip" $ companyzip $ companyinfo company
    value "companyname" $ getCompanyName company
    value "companynumber" $ getCompanyNumber company
    valueM "mailapi" $ case (mcmailapi) of
                            Nothing -> return JSNull
                            Just cmailapi -> mailAPIInfoJSON cmailapi
                            
userStatsDayToJSON :: [(Int, [Int])] -> [JSValue]
userStatsDayToJSON = rights . map f
  where
    f (d, s:c:i:_) = Right . runJSONGen . object "fields" $ do
      value "date" (showAsDate d)
      value "closed" c
      value "sent" i
      value "signatures" s
    f _ = Left "Bad stat"

userStatsMonthToJSON :: [(Int, [Int])] -> [JSValue]
userStatsMonthToJSON = rights . map f
  where
    f (d, s:c:i:_) = Right . runJSONGen . object "fields" $ do
      value "date" (showAsMonth d)
      value "closed" c
      value "sent" i
      value "signatures" s
    f _ = Left "Bad stat"

companyStatsDayToJSON :: String -> [(Int, String, [Int])] -> [JSValue]
companyStatsDayToJSON ts ls = rights $ [f e | e@(_,n,_) <- ls, n=="Total"]
  where
    f (d, _, s:c:i:_) = Right . runJSONGen . object "fields" $ do
      value "date" (showAsDate d)
      value "closed" c
      value "sent" i
      value "name" ts
      value "signatures" s
      objects "subfields" $ do
         [do value "date" (showAsDate d') 
             value "closed" c'
             value "sent" i' 
             value "name" n' 
             value "signatures" s'
           | (d',n',s':c':i':_) <- ls,
             d' == d,
             n' /= "Total"]
    f _ = Left "Bad stat"

companyStatsMonthToJSON :: String -> [(Int, String, [Int])] -> [JSValue]
companyStatsMonthToJSON ts ls = rights $ [f e | e@(_,n,_) <- ls, n=="Total"]
  where
    f (d, _, s:c:i:_) = Right $ runJSONGen $ object "fields" $ do
      value "date" (showAsMonth d)
      value "closed" c
      value "sent" i
      value "name" ts
      value "signatures" s
      objects "subfields" $ do
        [do value "date" (showAsMonth d')
            value "closed" c' 
            value "sent" i' 
            value "name" n' 
            value "signatures" s'
          | (d',n',s':c':i':_) <- ls,
            d' == d,
            n' /= "Total"]
    f _ = Left "Bad stat"

pageAcceptTOS :: TemplatesMonad m => m String
pageAcceptTOS = renderTemplate_ "pageAcceptTOS"

menuFields :: Monad m => User -> Fields m ()
menuFields user = do
  F.value "iscompanyadmin" $ useriscompanyadmin user
  F.value "seessubscriptiondashboard" $ userSeesSubscriptionDashboard user

userSeesSubscriptionDashboard :: User -> Bool
userSeesSubscriptionDashboard user = useriscompanyadmin user || isNothing (usercompany user)

activatePageViewNotValidLink :: TemplatesMonad m => String -> m String
activatePageViewNotValidLink email =
  renderTemplate "activatePageViewNotValidLink" $ F.value "email" email

resetPasswordMail :: TemplatesMonad m => String -> User -> KontraLink -> m Mail
resetPasswordMail hostname user setpasslink = do
  kontramail "passwordChangeLinkMail" $ do
    F.value "personname"   $ getFullName user
    F.value "passwordlink" $ show setpasslink
    F.value "ctxhostpart"  $ hostname

newUserMail :: TemplatesMonad m => String -> String -> String -> KontraLink -> m Mail
newUserMail hostpart emailaddress personname activatelink = do
  kontramail "newUserMail" $ do
    F.value "personname"   $ personname
    F.value "email"        $ emailaddress
    F.value "activatelink" $ show activatelink
    F.value "ctxhostpart"  $ hostpart

mailNewAccountCreatedByAdmin :: (HasLocale a, TemplatesMonad m) => Context -> a -> String -> String -> KontraLink -> Maybe String -> m Mail
mailNewAccountCreatedByAdmin ctx locale personname email setpasslink custommessage = do
  kontramaillocal locale "mailNewAccountCreatedByAdmin" $ do
    F.value "personname"    $ personname
    F.value "email"         $ email
    F.value "passwordlink"  $ show setpasslink
    F.value "creatorname"   $ maybe "" getSmartName (ctxmaybeuser ctx)
    F.value "ctxhostpart"   $ ctxhostpart ctx
    F.value "custommessage"   custommessage

mailEmailChangeRequest :: (TemplatesMonad m, HasSomeUserInfo a) => String -> a -> Email -> KontraLink -> m Mail
mailEmailChangeRequest hostpart user newemail link = do
  kontramail "mailRequestChangeEmail" $ do
    F.value "fullname" $ getFullName user
    F.value "newemail" $ unEmail newemail
    F.value "hostpart" $ hostpart
    F.value "link" $ show link

-------------------------------------------------------------------------------

modalAccountSetup :: Monad m => KontraLink -> String -> String -> m FlashMessage
modalAccountSetup signuplink fstname sndname = do
  return $ toFlashTemplate Modal "modalAccountSetup" $
    [ ("signuplink", show signuplink)
    , ("fstname", fstname)
    , ("sndname", sndname) ]

modalDoYouWantToChangeEmail :: TemplatesMonad m => Email -> m FlashMessage
modalDoYouWantToChangeEmail newemail = do
  toModal <$> (renderTemplate "modalDoYouWantToChangeEmail" $
                 F.value "newemail" $ unEmail newemail)

flashMessageThanksForTheQuestion :: TemplatesMonad m => m FlashMessage
flashMessageThanksForTheQuestion =
    toFlashMsg OperationDone <$> renderTemplate_ "flashMessageThanksForTheQuestion"

flashMessageLoginRedirectReason :: TemplatesMonad m => LoginRedirectReason -> m (Maybe FlashMessage)
flashMessageLoginRedirectReason reason =
  case reason of
       LoginTry             -> return Nothing
       NotLogged            -> render "notlogged"
       NotLoggedAsSuperUser -> render "notsu"
       InvalidLoginInfo _   -> render "invloginfo"
  where
    render msg = Just . toFlashMsg OperationFailed <$>
      (renderTemplate "flashMessageLoginPageRedirectReason" $ F.value msg True)

flashMessageUserDetailsSaved :: TemplatesMonad m => m FlashMessage
flashMessageUserDetailsSaved =
  toFlashMsg OperationDone <$> renderTemplate_ "flashMessageUserDetailsSaved"

flashMessageCompanyCreated :: TemplatesMonad m => m FlashMessage
flashMessageCompanyCreated =
  toFlashMsg OperationDone <$> renderTemplate_ "flashMessageCompanyCreated"


flashMessageNoAccountType :: TemplatesMonad m => m FlashMessage
flashMessageNoAccountType =
    toFlashMsg OperationFailed <$> renderTemplate_ "flashMessageNoAccountType"

flashMessageInvalidAccountType :: TemplatesMonad m => m FlashMessage
flashMessageInvalidAccountType =
    toFlashMsg OperationFailed <$> renderTemplate_ "flashMessageInvalidAccountType"

flashMessageMustAcceptTOS :: TemplatesMonad m => m FlashMessage
flashMessageMustAcceptTOS =
  toFlashMsg SigningRelated <$> renderTemplate_ "flashMessageMustAcceptTOS"


flashMessageBadOldPassword :: TemplatesMonad m => m FlashMessage
flashMessageBadOldPassword =
  toFlashMsg OperationFailed <$> renderTemplate_ "flashMessageBadOldPassword"


flashMessagePasswordsDontMatch :: TemplatesMonad m => m FlashMessage
flashMessagePasswordsDontMatch =
  toFlashMsg OperationFailed <$> renderTemplate_ "flashMessagePasswordsDontMatch"


flashMessageUserPasswordChanged :: TemplatesMonad m => m FlashMessage
flashMessageUserPasswordChanged =
  toFlashMsg OperationDone <$> renderTemplate_ "flashMessageUserPasswordChanged"

flashMessagePasswordChangeLinkNotValid :: TemplatesMonad m => m FlashMessage
flashMessagePasswordChangeLinkNotValid =
  toFlashMsg OperationFailed <$> renderTemplate_ "flashMessagePasswordChangeLinkNotValid"


flashMessageUserWithSameEmailExists :: TemplatesMonad m => m FlashMessage
flashMessageUserWithSameEmailExists =
  toFlashMsg OperationFailed <$> renderTemplate_ "flashMessageUserWithSameEmailExists"


flashMessageActivationLinkNotValid :: TemplatesMonad m => m FlashMessage
flashMessageActivationLinkNotValid =
  toFlashMsg OperationFailed <$> renderTemplate_ "flashMessageActivationLinkNotValid"


flashMessageUserActivated :: TemplatesMonad m => m FlashMessage
flashMessageUserActivated =
  toFlashMsg SigningRelated <$> renderTemplate_ "flashMessageUserActivated"


flashMessageUserAlreadyActivated :: TemplatesMonad m => m FlashMessage
flashMessageUserAlreadyActivated =
  toFlashMsg OperationFailed <$> renderTemplate_ "flashMessageUserAlreadyActivated"

flashMessageNewActivationLinkSend :: TemplatesMonad m => m FlashMessage
flashMessageNewActivationLinkSend =
  toFlashMsg OperationDone <$> renderTemplate_ "flashMessageNewActivationLinkSend"


flashMessageUserSignupDone :: TemplatesMonad m => m FlashMessage
flashMessageUserSignupDone =
  toFlashMsg OperationDone <$> renderTemplate_ "flashMessageUserSignupDone"

modalNewPasswordView :: TemplatesMonad m => UserID -> MagicHash -> m FlashMessage
modalNewPasswordView aid hash = do
  toModal <$> (renderTemplate "modalNewPasswordView" $ do
            F.value "linkchangepassword" $ show $ LinkPasswordReminder aid hash)

modalUserSignupDone :: TemplatesMonad m => Email -> m FlashMessage
modalUserSignupDone email =
  toModal <$> (renderTemplate "modalUserSignupDone" $ do
                 F.value "email" $ unEmail email)

flashMessageChangeEmailMailSent :: TemplatesMonad m => Email -> m FlashMessage
flashMessageChangeEmailMailSent newemail =
  toFlashMsg OperationDone <$> (renderTemplate "flashMessageChangeEmailMailSent" $
                                  F.value "newemail" $ unEmail newemail)

flashMessageMismatchedEmails :: TemplatesMonad m => m FlashMessage
flashMessageMismatchedEmails =
  toFlashMsg OperationFailed <$> renderTemplate_ "flashMessageMismatchedEmails"

flashMessageProblemWithEmailChange :: TemplatesMonad m => m FlashMessage
flashMessageProblemWithEmailChange =
  toFlashMsg OperationFailed <$> renderTemplate_ "flashMessageProblemWithEmailChange"

flashMessageProblemWithPassword :: TemplatesMonad m => m FlashMessage
flashMessageProblemWithPassword =
  toFlashMsg OperationFailed <$> renderTemplate_ "flashMessageProblemWithPassword"

flashMessageYourEmailHasChanged :: TemplatesMonad m => m FlashMessage
flashMessageYourEmailHasChanged =
  toFlashMsg OperationDone <$> renderTemplate_ "flashMessageYourEmailHasChanged"

-------------------------------------------------------------------------------

{- | Basic fields for the user  -}
userBasicFields :: Monad m => User -> Maybe Company -> Fields m ()
userBasicFields u mc = do
    F.value "id" $ show $ userid u
    F.value "fullname" $ getFullName u
    F.value "email" $ getEmail u
    F.value "company" $ getCompanyName mc
    F.value "phone" $ userphone $ userinfo u
    F.value "position" $ usercompanyposition $ userinfo u
    F.value "iscompanyadmin" $ useriscompanyadmin u
    F.value "TOSdate" $ maybe "-" show (userhasacceptedtermsofservice u)
