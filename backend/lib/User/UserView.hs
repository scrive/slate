{-# LANGUAGE ExtendedDefaultRules #-}
module User.UserView (
    -- pages
    pageAcceptTOS,
    pageDoYouWantToChangeEmail,

    -- mails
    newUserMail,
    mailNewAccountCreatedByAdmin,
    resetPasswordMail,
    mailEmailChangeRequest,

    -- flash messages
    flashMessageLoginRedirect,
    flashMessagePasswordChangeLinkNotValid,
    flashMessageNewActivationLinkSend,
    flashMessageProblemWithEmailChange,
    flashMessageProblemWithPassword,
    flashMessageYourEmailHasChanged,
    flashMessageUserAccountRequestExpired,
    flashMessageUserAccountRequestExpiredCompany,
    ) where

import Control.Monad.Catch
import Text.StringTemplate.GenericStandard ()
import Text.StringTemplate.GenericStandard ()
import Text.StringTemplates.Templates
import qualified Text.StringTemplates.Fields as F

import AppView
import BrandedDomain.BrandedDomain
import DB
import Doc.DocViewMail
import FlashMessage
import Kontra
import KontraLink
import KontraPrelude
import Mails.SendMail (Mail, kontramail, kontramaillocal)
import Theme.Model
import User.Email
import User.Model
import Util.HasSomeUserInfo

pageAcceptTOS :: TemplatesMonad m => Context -> m String
pageAcceptTOS ctx = renderTemplate "pageAcceptTOS" $ entryPointFields ctx

resetPasswordMail :: (TemplatesMonad m,MonadDB m,MonadThrow m) => Context -> User -> KontraLink -> m Mail
resetPasswordMail ctx user setpasslink = do
  theme <- dbQuery $ GetTheme $ get (bdMailTheme . ctxbrandeddomain) ctx
  kontramail (get ctxmailnoreplyaddress ctx) (get ctxbrandeddomain ctx)
    theme  "passwordChangeLinkMail" $ do
    F.value "personemail"  $ getEmail user
    F.value "passwordlink" $ show setpasslink
    F.value "ctxhostpart"  $ ctxDomainUrl ctx
    brandingMailFields theme

newUserMail :: (TemplatesMonad m,MonadDB m,MonadThrow m) => Context -> String -> KontraLink -> m Mail
newUserMail ctx emailaddress activatelink = do
  theme <- dbQuery $ GetTheme $ get (bdMailTheme . ctxbrandeddomain) ctx
  kontramail (get ctxmailnoreplyaddress ctx)
    (get ctxbrandeddomain ctx) theme "newUserMail" $ do
    F.value "email"        $ emailaddress
    F.value "activatelink" $ show activatelink
    F.value "ctxhostpart"  $ ctxDomainUrl ctx
    brandingMailFields theme


mailNewAccountCreatedByAdmin :: (HasLang a,MonadDB m,MonadThrow m, TemplatesMonad m) => Context -> a -> String -> KontraLink -> m Mail
mailNewAccountCreatedByAdmin ctx lang email setpasslink = do
  theme <- dbQuery $ GetTheme $ get (bdMailTheme . ctxbrandeddomain) ctx
  kontramaillocal (get ctxmailnoreplyaddress ctx) (get ctxbrandeddomain ctx)
    theme lang "mailNewAccountCreatedByAdmin" $ do
    F.value "email"         $ email
    F.value "passwordlink"  $ show setpasslink
    F.value "creatorname"   $ maybe "" getSmartName (get ctxmaybeuser ctx)
    F.value "ctxhostpart"   $ ctxDomainUrl ctx
    brandingMailFields theme


mailEmailChangeRequest :: (TemplatesMonad m, HasSomeUserInfo a,MonadDB m,MonadThrow m) => Context -> a -> Email -> KontraLink -> m Mail
mailEmailChangeRequest ctx user newemail link = do
  theme <- dbQuery $ GetTheme $ get (bdMailTheme . ctxbrandeddomain) ctx
  kontramail (get ctxmailnoreplyaddress ctx) (get ctxbrandeddomain ctx)
    theme "mailRequestChangeEmail" $ do
    F.value "fullname" $ getFullName user
    F.value "newemail" $ unEmail newemail
    F.value "ctxhostpart" $ ctxDomainUrl ctx
    F.value "link" $ show link
    brandingMailFields theme

-------------------------------------------------------------------------------

pageDoYouWantToChangeEmail :: TemplatesMonad m => Context -> Email -> m String
pageDoYouWantToChangeEmail ctx newemail =
  renderTemplate "pageDoYouWantToChangeEmail" $ do
    F.value "newemail" $ unEmail newemail
    entryPointFields ctx

flashMessageLoginRedirect :: TemplatesMonad m => m FlashMessage
flashMessageLoginRedirect =
  toFlashMsg OperationFailed <$> renderTemplate_ "flashMessageLoginPageRedirectReason"

flashMessagePasswordChangeLinkNotValid :: TemplatesMonad m => m FlashMessage
flashMessagePasswordChangeLinkNotValid =
  toFlashMsg OperationFailed <$> renderTemplate_ "flashMessagePasswordChangeLinkNotValid"

flashMessageNewActivationLinkSend :: TemplatesMonad m => m FlashMessage
flashMessageNewActivationLinkSend =
  toFlashMsg OperationDone <$> renderTemplate_ "flashMessageNewActivationLinkSend"

flashMessageProblemWithEmailChange :: TemplatesMonad m => m FlashMessage
flashMessageProblemWithEmailChange =
  toFlashMsg OperationFailed <$> renderTemplate_ "flashMessageProblemWithEmailChange"

flashMessageProblemWithPassword :: TemplatesMonad m => m FlashMessage
flashMessageProblemWithPassword =
  toFlashMsg OperationFailed <$> renderTemplate_ "flashMessageProblemWithPassword"

flashMessageYourEmailHasChanged :: TemplatesMonad m => m FlashMessage
flashMessageYourEmailHasChanged =
  toFlashMsg OperationDone <$> renderTemplate_ "flashMessageYourEmailHasChanged"

flashMessageUserAccountRequestExpiredCompany :: TemplatesMonad m => m FlashMessage
flashMessageUserAccountRequestExpiredCompany =
  toFlashMsg OperationFailed <$> renderTemplate_ "flashMessageUserAccountRequestExpiredCompany"

flashMessageUserAccountRequestExpired :: TemplatesMonad m => m FlashMessage
flashMessageUserAccountRequestExpired =
  toFlashMsg OperationFailed <$> renderTemplate_ "flashMessageUserAccountRequestExpired"
