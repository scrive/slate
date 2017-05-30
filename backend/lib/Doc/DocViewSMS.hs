module Doc.DocViewSMS (
      smsDocumentErrorAuthor
    , smsDocumentErrorSignatory
    , smsInvitation
    , smsInvitationToAuthor
    , smsReminder
    , smsClosedNotification
    , smsRejectNotification
    , smsPinCodeSendout
    ) where

import Control.Conditional ((<|), (|>))
import Control.Monad.Catch
import Control.Monad.Trans
import Text.StringTemplates.Templates
import qualified Text.StringTemplates.Fields as F

import BrandedDomain.BrandedDomain
import Company.CompanyUI
import Company.Model
import DB
import Doc.DocStateData hiding (DocumentStatus(..))
import KontraLink
import KontraPrelude
import MailContext
import SMS.Data
import SMS.SMS
import Templates
import User.Model
import Util.HasSomeUserInfo
import Util.SignatoryLinkUtils
import Utils.Monoid

mkSMS :: (MonadDB m, MonadThrow m, MailContextMonad m) => Document -> SignatoryLink -> Maybe KontraInfoForSMS -> String -> (m SMS)
mkSMS doc sl mkontraInfoForSMS msgBody = do
  mctx <- getMailContext
  (moriginator, provider) <- case maybesignatory =<< getAuthorSigLink doc of
    Nothing -> return (Nothing, SMSDefault)
    Just uid -> do
      muser <- dbQuery $ GetUserByID uid
      case muser of
        Nothing -> return (Nothing, SMSDefault)
        Just user -> do
          orig <- companySmsOriginator <$> (dbQuery $ GetCompanyUI $ usercompany user)
          prov <- companysmsprovider . companyinfo <$> (dbQuery $ GetCompanyByUserID (userid user))
          return (orig, prov)
  let originator = fromMaybe (bdSmsOriginator $ mctxcurrentBrandedDomain mctx) (justEmptyToNothing moriginator)
  return $ SMS (getMobile sl) mkontraInfoForSMS msgBody originator provider

smsDocumentErrorAuthor :: (MailContextMonad m, MonadDB m, MonadThrow m, TemplatesMonad m) => Document -> SignatoryLink -> m SMS
smsDocumentErrorAuthor doc sl = do
  mkSMS doc sl (Just $ OtherDocumentSMS $ documentid doc) =<< renderLocalTemplate doc "_smsDocumentErrorAuthor" (smsFields doc sl)

smsDocumentErrorSignatory :: (MailContextMonad m, MonadDB m, MonadThrow m, TemplatesMonad m) => Document -> SignatoryLink -> m SMS
smsDocumentErrorSignatory doc sl = do
  mkSMS doc sl (Just $ OtherDocumentSMS $ documentid doc) =<< renderLocalTemplate doc "_smsDocumentErrorSignatory" (smsFields doc sl)

smsInvitation :: (MailContextMonad m, MonadDB m, MonadThrow m, TemplatesMonad m) => SignatoryLink -> Document -> m SMS
smsInvitation sl doc = do
  mkSMS doc sl (Just $ DocumentInvitationSMS (documentid doc) (signatorylinkid sl)) =<<
    renderLocalTemplate doc (templateName "_smsInvitationToSign" <| isSignatory sl |> templateName "_smsInvitationToView") (smsFields doc sl)

smsInvitationToAuthor :: (MailContextMonad m, MonadDB m, MonadThrow m, TemplatesMonad m) => Document -> SignatoryLink -> m SMS
smsInvitationToAuthor doc sl = do
  mkSMS doc sl (Just $ DocumentInvitationSMS (documentid doc) (signatorylinkid sl)) =<< renderLocalTemplate doc "_smsInvitationToAuthor" (smsFields doc sl)

smsReminder :: (MailContextMonad m, MonadDB m, MonadThrow m, TemplatesMonad m) => Bool -> Document -> SignatoryLink -> m SMS
smsReminder automatic doc sl = mkSMS doc sl smstypesignatory =<< renderLocalTemplate doc template (smsFields doc sl)
  where (smstypesignatory, template) = case maybesigninfo sl of
          Just _  -> (Just $ (OtherDocumentSMS $ documentid doc), templateName "_smsReminderSigned")
          Nothing | automatic -> (invitation, templateName "_smsReminderAutomatic")
                  | otherwise -> (invitation, templateName "_smsReminder")
        invitation = Just $ DocumentInvitationSMS (documentid doc) (signatorylinkid sl)

smsClosedNotification :: (MailContextMonad m, MonadDB m, MonadThrow m, TemplatesMonad m) => Document -> SignatoryLink -> Bool -> Bool -> m SMS
smsClosedNotification doc sl withEmail sealFixed = do
  mkSMS doc sl (Just $ OtherDocumentSMS $ documentid doc) =<< (renderLocalTemplate doc template $ smsFields doc sl)
  where template = case (sealFixed, withEmail) of
                     (True, True) -> templateName "_smsCorrectedNotificationWithEmail"
                     (True, False) -> templateName "_smsCorrectedNotification"
                     (False, True) -> templateName "_smsClosedNotificationWithEmail"
                     (False, False) -> templateName "_smsClosedNotification"

smsRejectNotification :: (MailContextMonad m, MonadDB m, MonadThrow m, TemplatesMonad m) => Document -> SignatoryLink -> SignatoryLink -> m SMS
smsRejectNotification doc sl rejector = do
  mkSMS doc sl (Just $ OtherDocumentSMS $ documentid doc) =<< renderLocalTemplate doc "_smsRejectNotification" (smsFields doc sl >> F.value "rejectorName" (getSmartName rejector))

smsPinCodeSendout :: (MailContextMonad m, MonadDB m, MonadThrow m, TemplatesMonad m) => Document -> SignatoryLink -> String -> String -> m SMS
smsPinCodeSendout doc sl phone pin = do
  sms <- mkSMS doc sl (Just $ DocumentPinSendoutSMS (documentid doc) (signatorylinkid sl)) =<< renderLocalTemplate doc "_smsPinSendout" (smsFields doc sl >> F.value "pin" pin)
  return sms {smsMSISDN = phone}

smsFields :: (MailContextMonad m, TemplatesMonad m) => Document -> SignatoryLink -> Fields m ()
smsFields document siglink = do
    mctx <- lift $ getMailContext
    F.value "creatorname" $ getSmartName <$> getAuthorSigLink document
    F.value "documenttitle" $ documenttitle document
    F.value "link" $ mctxDomainUrl mctx ++ show (LinkSignDoc (documentid document) siglink)
