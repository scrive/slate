module FeatureFlags.Model
  ( Features(..)
  , FeatureFlags(..)
  , defaultFeatures
  , firstAllowedAuthenticationToView
  , firstAllowedAuthenticationToSign
  , firstAllowedInvitationDelivery
  , firstAllowedConfirmationDelivery
  , setFeatureFlagsSql
  , selectFeatureFlagsSelectors
  ) where

import Control.Monad.State
import Data.Unjson
import Database.PostgreSQL.PQTypes.Model.CompositeType

import DB
import Doc.Types.SignatoryLink
import FeatureFlags.Tables
import UserGroup.Types.PaymentPlan

data Features = Features
  { fAdminUsers :: FeatureFlags
  , fRegularUsers :: FeatureFlags
  } deriving (Eq, Ord, Show)

instance Unjson Features where
  unjsonDef =
    objectOf
      $   Features
      <$> field "admin_users"   fAdminUsers   "Feature flags for admin users"
      <*> field "regular_users" fRegularUsers "Feature flags for regular users"

data FeatureFlags = FeatureFlags
  { ffCanUseTemplates :: Bool
  , ffCanUseBranding :: Bool
  , ffCanUseAuthorAttachments :: Bool
  , ffCanUseSignatoryAttachments :: Bool
  , ffCanUseMassSendout :: Bool
  , ffCanUseSMSInvitations :: Bool
  , ffCanUseSMSConfirmations :: Bool
  , ffCanUseDKAuthenticationToView :: Bool
  , ffCanUseDKAuthenticationToSign :: Bool
  , ffCanUseFIAuthenticationToView :: Bool
  , ffCanUseFIAuthenticationToSign :: Bool
  , ffCanUseNOAuthenticationToView :: Bool
  , ffCanUseNOAuthenticationToSign :: Bool
  , ffCanUseSEAuthenticationToView :: Bool
  , ffCanUseSEAuthenticationToSign :: Bool
  , ffCanUseSMSPinAuthenticationToView :: Bool
  , ffCanUseSMSPinAuthenticationToSign :: Bool
  , ffCanUseStandardAuthenticationToView :: Bool
  , ffCanUseStandardAuthenticationToSign :: Bool
  , ffCanUseVerimiAuthenticationToView :: Bool
  , ffCanUseIDINAuthenticationToView :: Bool
  , ffCanUseIDINAuthenticationToSign :: Bool
  , ffCanUseOnfidoAuthenticationToSign :: Bool
  , ffCanUseEmailInvitations :: Bool
  , ffCanUseEmailConfirmations :: Bool
  , ffCanUseAPIInvitations :: Bool
  , ffCanUsePadInvitations :: Bool
  , ffCanUseShareableLinks :: Bool
  , ffCanUseForwarding :: Bool
  , ffCanUseDocumentPartyNotifications :: Bool
  , ffCanUsePortal :: Bool
  , ffCanUseCustomSMSTexts :: Bool
  , ffCanUseArchiveToDropBox :: Bool
  , ffCanUseArchiveToGoogleDrive :: Bool
  , ffCanUseArchiveToOneDrive :: Bool
  , ffCanUseArchiveToSharePoint :: Bool
  , ffCanUseArchiveToSftp :: Bool
  } deriving (Eq, Ord, Show)

instance Unjson FeatureFlags where
  unjsonDef =
    objectOf
      $   FeatureFlags
      <$> field "can_use_templates" ffCanUseTemplates "Can use templates"
      <*> field "can_use_branding"  ffCanUseBranding  "Can use branding"
      <*> field "can_use_author_attachments"
                ffCanUseAuthorAttachments
                "Can use author attachments"
      <*> field "can_use_signatory_attachments"
                ffCanUseSignatoryAttachments
                "Can use signatory attachments"
      <*> field "can_use_mass_sendout"      ffCanUseMassSendout      "TODO desc"
      <*> field "can_use_sms_invitations"   ffCanUseSMSInvitations   "TODO desc"
      <*> field "can_use_sms_confirmations" ffCanUseSMSConfirmations "TODO desc"
      <*> field "can_use_dk_authentication_to_view"
                ffCanUseDKAuthenticationToView
                "TODO desc"
      <*> field "can_use_dk_authentication_to_sign"
                ffCanUseDKAuthenticationToSign
                "TODO desc"
      <*> field "can_use_fi_authentication_to_view"
                ffCanUseFIAuthenticationToView
                "TODO desc"
      <*> field "can_use_fi_authentication_to_sign"
                ffCanUseFIAuthenticationToSign
                "Can use Finnish Tupas to sign"
      <*> field "can_use_no_authentication_to_view"
                ffCanUseNOAuthenticationToView
                "TODO desc"
      <*> field "can_use_no_authentication_to_sign"
                ffCanUseNOAuthenticationToSign
                "TODO desc"
      <*> field "can_use_se_authentication_to_view"
                ffCanUseSEAuthenticationToView
                "TODO desc"
      <*> field "can_use_se_authentication_to_sign"
                ffCanUseSEAuthenticationToSign
                "TODO desc"
      <*> field "can_use_sms_pin_authentication_to_view"
                ffCanUseSMSPinAuthenticationToView
                "TODO desc"
      <*> field "can_use_sms_pin_authentication_to_sign"
                ffCanUseSMSPinAuthenticationToSign
                "TODO desc"
      <*> field "can_use_standard_authentication_to_view"
                ffCanUseStandardAuthenticationToView
                "TODO desc"
      <*> field "can_use_standard_authentication_to_sign"
                ffCanUseStandardAuthenticationToSign
                "TODO desc"
      <*> field "can_use_verimi_authentication_to_view"
                ffCanUseVerimiAuthenticationToView
                "TODO desc"
      <*> field "can_use_idin_authentication_to_view"
                ffCanUseIDINAuthenticationToView
                "TODO desc"
      <*> field "can_use_idin_authentication_to_sign"
                ffCanUseIDINAuthenticationToSign
                "TODO desc"
      <*> field "can_use_onfido_authentication_to_sign"
                ffCanUseOnfidoAuthenticationToSign
                "TODO desc"
      <*> field "can_use_email_invitations"   ffCanUseEmailInvitations   "TODO desc"
      <*> field "can_use_email_confirmations" ffCanUseEmailConfirmations "TODO desc"
      <*> fieldDef "can_use_api_invitations" True ffCanUseAPIInvitations "TODO desc"
      <*> fieldDef "can_use_pad_invitations" True ffCanUsePadInvitations "TODO desc"
      <*> field "can_use_shareable_links" ffCanUseShareableLinks "TODO desc"
      <*> field "can_use_forwarding"      ffCanUseForwarding     "TODO desc"
      <*> field "can_use_document_party_notifications"
                ffCanUseDocumentPartyNotifications
                "Can use document notifications"
      <*> field "can_use_portal" ffCanUsePortal "TODO desc"
      <*> field "can_use_custom_sms_texts"
                ffCanUseCustomSMSTexts
                "Can set a custom content of SMS for invitations and confirmations"
      <*> field "can_use_archive_to_drop_box"     ffCanUseArchiveToDropBox     "TODO desc"
      <*> field "can_use_archive_to_google_drive" ffCanUseArchiveToGoogleDrive "TODO desc"
      <*> field "can_use_archive_to_one_drive"    ffCanUseArchiveToOneDrive    "TODO desc"
      <*> field "can_use_archive_to_share_point"  ffCanUseArchiveToSharePoint  "TODO desc"
      <*> field "can_use_archive_to_sftp"         ffCanUseArchiveToSftp        "TODO desc"



type instance CompositeRow FeatureFlags
  = ( Bool
    , Bool
    , Bool
    , Bool
    , Bool
    , Bool
    , Bool
    , Bool
    , Bool
    , Bool
    , Bool
    , Bool
    , Bool
    , Bool
    , Bool
    , Bool
    , Bool
    , Bool
    , Bool
    , Bool
    , Bool
    , Bool
    , Bool
    , Bool
    , Bool
    , Bool
    , Bool
    , Bool
    , Bool
    , Bool
    , Bool
    , Bool
    , Bool
    , Bool
    , Bool
    , Bool
    , Bool
    )

instance PQFormat FeatureFlags where
  pqFormat = compositeTypePqFormat ctFeatureFlags

instance CompositeFromSQL FeatureFlags where
  toComposite (ffCanUseTemplates, ffCanUseBranding, ffCanUseAuthorAttachments, ffCanUseSignatoryAttachments, ffCanUseMassSendout, ffCanUseSMSInvitations, ffCanUseSMSConfirmations, ffCanUseDKAuthenticationToView, ffCanUseDKAuthenticationToSign, ffCanUseFIAuthenticationToView, ffCanUseFIAuthenticationToSign, ffCanUseNOAuthenticationToView, ffCanUseNOAuthenticationToSign, ffCanUseSEAuthenticationToView, ffCanUseSEAuthenticationToSign, ffCanUseSMSPinAuthenticationToView, ffCanUseSMSPinAuthenticationToSign, ffCanUseStandardAuthenticationToView, ffCanUseStandardAuthenticationToSign, ffCanUseVerimiAuthenticationToView, ffCanUseIDINAuthenticationToView, ffCanUseIDINAuthenticationToSign, ffCanUseOnfidoAuthenticationToSign, ffCanUseEmailInvitations, ffCanUseEmailConfirmations, ffCanUseAPIInvitations, ffCanUsePadInvitations, ffCanUseShareableLinks, ffCanUseForwarding, ffCanUseDocumentPartyNotifications, ffCanUsePortal, ffCanUseCustomSMSTexts, ffCanUseArchiveToDropBox, ffCanUseArchiveToGoogleDrive, ffCanUseArchiveToOneDrive, ffCanUseArchiveToSharePoint, ffCanUseArchiveToSftp)
    = FeatureFlags { .. }

firstAllowedAuthenticationToView :: FeatureFlags -> AuthenticationToViewMethod
firstAllowedAuthenticationToView ff
  | ffCanUseStandardAuthenticationToView ff = StandardAuthenticationToView
  | ffCanUseSMSPinAuthenticationToView ff = SMSPinAuthenticationToView
  | ffCanUseSEAuthenticationToView ff = SEBankIDAuthenticationToView
  | ffCanUseDKAuthenticationToView ff = DKNemIDAuthenticationToView
  | ffCanUseNOAuthenticationToView ff = NOBankIDAuthenticationToView
  | ffCanUseFIAuthenticationToView ff = FITupasAuthenticationToView
  | ffCanUseVerimiAuthenticationToView ff = VerimiAuthenticationToView
  | ffCanUseIDINAuthenticationToView ff = IDINAuthenticationToView
  |
  -- Someone can turn off all FFs, not recommended
    otherwise = StandardAuthenticationToView

firstAllowedAuthenticationToSign :: FeatureFlags -> AuthenticationToSignMethod
firstAllowedAuthenticationToSign ff
  | ffCanUseStandardAuthenticationToSign ff = StandardAuthenticationToSign
  | ffCanUseSMSPinAuthenticationToSign ff = SMSPinAuthenticationToSign
  | ffCanUseSEAuthenticationToSign ff = SEBankIDAuthenticationToSign
  | ffCanUseDKAuthenticationToSign ff = DKNemIDAuthenticationToSign
  | ffCanUseNOAuthenticationToSign ff = NOBankIDAuthenticationToSign
  | ffCanUseFIAuthenticationToSign ff = FITupasAuthenticationToSign
  | ffCanUseIDINAuthenticationToSign ff = IDINAuthenticationToSign
  |
  -- Someone can turn off all FFs, not recommended
    otherwise = StandardAuthenticationToSign

firstAllowedInvitationDelivery :: FeatureFlags -> DeliveryMethod
firstAllowedInvitationDelivery ff | ffCanUseEmailInvitations ff = EmailDelivery
                                  | ffCanUseSMSInvitations ff   = MobileDelivery
                                  | ffCanUseAPIInvitations ff   = APIDelivery
                                  | ffCanUsePadInvitations ff   = PadDelivery
                                  |
  -- Someone can turn off all FFs, not recommended
                                    otherwise                   = EmailDelivery

firstAllowedConfirmationDelivery :: FeatureFlags -> ConfirmationDeliveryMethod
firstAllowedConfirmationDelivery ff
  | ffCanUseEmailConfirmations ff = EmailConfirmationDelivery
  | ffCanUseSMSConfirmations ff   = MobileConfirmationDelivery
  | otherwise                     = NoConfirmationDelivery

defaultFeatures :: PaymentPlan -> Features
defaultFeatures paymentPlan = Features ff ff
  where
    defaultFF = FeatureFlags { ffCanUseTemplates                  = True
                             , ffCanUseBranding                   = True
                             , ffCanUseAuthorAttachments          = True
                             , ffCanUseSignatoryAttachments       = True
                             , ffCanUseMassSendout                = True
                             , ffCanUseSMSInvitations             = True
                             , ffCanUseSMSConfirmations           = True
                             , ffCanUseDKAuthenticationToView     = True
                             , ffCanUseDKAuthenticationToSign     = True
                             , ffCanUseFIAuthenticationToView     = True
                             , ffCanUseFIAuthenticationToSign     = True
                             , ffCanUseNOAuthenticationToView     = True
                             , ffCanUseNOAuthenticationToSign     = True
                             , ffCanUseSEAuthenticationToView     = True
                             , ffCanUseSEAuthenticationToSign     = True
                             , ffCanUseSMSPinAuthenticationToView = True
                             , ffCanUseSMSPinAuthenticationToSign = True
                             , ffCanUseStandardAuthenticationToView = True
                             , ffCanUseStandardAuthenticationToSign = True
                             , ffCanUseVerimiAuthenticationToView = True
                             , ffCanUseIDINAuthenticationToView   = True
                             , ffCanUseIDINAuthenticationToSign   = True
                             , ffCanUseOnfidoAuthenticationToSign = True
                             , ffCanUseEmailInvitations           = True
                             , ffCanUseEmailConfirmations         = True
                             , ffCanUseAPIInvitations             = True
                             , ffCanUsePadInvitations             = True
                             , ffCanUseShareableLinks             = False
                             , ffCanUseForwarding                 = True
                             , ffCanUseDocumentPartyNotifications = False
                             , ffCanUsePortal                     = False
                             , ffCanUseCustomSMSTexts             = False
                             , ffCanUseArchiveToDropBox           = False
                             , ffCanUseArchiveToGoogleDrive       = False
                             , ffCanUseArchiveToOneDrive          = False
                             , ffCanUseArchiveToSharePoint        = False
                             , ffCanUseArchiveToSftp              = False
                             }
    ff = case paymentPlan of
      FreePlan -> defaultFF { ffCanUseDKAuthenticationToView     = False
                            , ffCanUseDKAuthenticationToSign     = False
                            , ffCanUseFIAuthenticationToView     = False
                            , ffCanUseFIAuthenticationToSign     = False
                            , ffCanUseNOAuthenticationToView     = False
                            , ffCanUseNOAuthenticationToSign     = False
                            , ffCanUseSEAuthenticationToView     = False
                            , ffCanUseSEAuthenticationToSign     = False
                            , ffCanUseVerimiAuthenticationToView = False
                            , ffCanUseIDINAuthenticationToView   = False
                            , ffCanUseIDINAuthenticationToSign   = False
                            , ffCanUseOnfidoAuthenticationToSign = False
                            }
      _ -> defaultFF

setFeatureFlagsSql :: (SqlSet command) => FeatureFlags -> State command ()
setFeatureFlagsSql ff = do
  sqlSet "can_use_templates" $ ffCanUseTemplates ff
  sqlSet "can_use_branding" $ ffCanUseBranding ff
  sqlSet "can_use_author_attachments" $ ffCanUseAuthorAttachments ff
  sqlSet "can_use_signatory_attachments" $ ffCanUseSignatoryAttachments ff
  sqlSet "can_use_mass_sendout" $ ffCanUseMassSendout ff
  sqlSet "can_use_sms_invitations" $ ffCanUseSMSInvitations ff
  sqlSet "can_use_sms_confirmations" $ ffCanUseSMSConfirmations ff
  sqlSet "can_use_dk_authentication_to_view" $ ffCanUseDKAuthenticationToView ff
  sqlSet "can_use_dk_authentication_to_sign" $ ffCanUseDKAuthenticationToSign ff
  sqlSet "can_use_fi_authentication_to_view" $ ffCanUseFIAuthenticationToView ff
  sqlSet "can_use_fi_authentication_to_sign" $ ffCanUseFIAuthenticationToSign ff
  sqlSet "can_use_no_authentication_to_view" $ ffCanUseNOAuthenticationToView ff
  sqlSet "can_use_no_authentication_to_sign" $ ffCanUseNOAuthenticationToSign ff
  sqlSet "can_use_se_authentication_to_view" $ ffCanUseSEAuthenticationToView ff
  sqlSet "can_use_se_authentication_to_sign" $ ffCanUseSEAuthenticationToSign ff
  sqlSet "can_use_sms_pin_authentication_to_view" $ ffCanUseSMSPinAuthenticationToView ff
  sqlSet "can_use_sms_pin_authentication_to_sign" $ ffCanUseSMSPinAuthenticationToSign ff
  sqlSet "can_use_standard_authentication_to_view"
    $ ffCanUseStandardAuthenticationToView ff
  sqlSet "can_use_standard_authentication_to_sign"
    $ ffCanUseStandardAuthenticationToSign ff
  sqlSet "can_use_verimi_authentication_to_view" $ ffCanUseVerimiAuthenticationToView ff
  sqlSet "can_use_idin_authentication_to_view" $ ffCanUseIDINAuthenticationToView ff
  sqlSet "can_use_idin_authentication_to_sign" $ ffCanUseIDINAuthenticationToSign ff
  sqlSet "can_use_onfido_authentication_to_sign" $ ffCanUseOnfidoAuthenticationToSign ff
  sqlSet "can_use_email_invitations" $ ffCanUseEmailInvitations ff
  sqlSet "can_use_email_confirmations" $ ffCanUseEmailConfirmations ff
  sqlSet "can_use_api_invitations" $ ffCanUseAPIInvitations ff
  sqlSet "can_use_pad_invitations" $ ffCanUsePadInvitations ff
  sqlSet "can_use_shareable_links" $ ffCanUseShareableLinks ff
  sqlSet "can_use_forwarding" $ ffCanUseForwarding ff
  sqlSet "can_use_document_party_notifications" $ ffCanUseDocumentPartyNotifications ff
  sqlSet "can_use_portal" $ ffCanUsePortal ff
  sqlSet "can_use_custom_sms_texts" $ ffCanUseCustomSMSTexts ff
  sqlSet "can_use_archive_to_drop_box" $ ffCanUseArchiveToDropBox ff
  sqlSet "can_use_archive_to_google_drive" $ ffCanUseArchiveToGoogleDrive ff
  sqlSet "can_use_archive_to_one_drive" $ ffCanUseArchiveToOneDrive ff
  sqlSet "can_use_archive_to_share_point" $ ffCanUseArchiveToSharePoint ff
  sqlSet "can_use_archive_to_sftp" $ ffCanUseArchiveToSftp ff

selectFeatureFlagsSelectors :: [SQL]
selectFeatureFlagsSelectors =
  [ "feature_flags.can_use_templates"
  , "feature_flags.can_use_branding"
  , "feature_flags.can_use_author_attachments"
  , "feature_flags.can_use_signatory_attachments"
  , "feature_flags.can_use_mass_sendout"
  , "feature_flags.can_use_sms_invitations"
  , "feature_flags.can_use_sms_confirmations"
  , "feature_flags.can_use_dk_authentication_to_view"
  , "feature_flags.can_use_dk_authentication_to_sign"
  , "feature_flags.can_use_fi_authentication_to_view"
  , "feature_flags.can_use_fi_authentication_to_sign"
  , "feature_flags.can_use_no_authentication_to_view"
  , "feature_flags.can_use_no_authentication_to_sign"
  , "feature_flags.can_use_se_authentication_to_view"
  , "feature_flags.can_use_se_authentication_to_sign"
  , "feature_flags.can_use_sms_pin_authentication_to_view"
  , "feature_flags.can_use_sms_pin_authentication_to_sign"
  , "feature_flags.can_use_standard_authentication_to_view"
  , "feature_flags.can_use_standard_authentication_to_sign"
  , "feature_flags.can_use_verimi_authentication_to_view"
  , "feature_flags.can_use_idin_authentication_to_view"
  , "feature_flags.can_use_idin_authentication_to_sign"
  , "feature_flags.can_use_onfido_authentication_to_sign"
  , "feature_flags.can_use_email_invitations"
  , "feature_flags.can_use_email_confirmations"
  , "feature_flags.can_use_api_invitations"
  , "feature_flags.can_use_pad_invitations"
  , "feature_flags.can_use_shareable_links"
  , "feature_flags.can_use_forwarding"
  , "feature_flags.can_use_document_party_notifications"
  , "feature_flags.can_use_portal"
  , "feature_flags.can_use_custom_sms_texts"
  , "feature_flags.can_use_archive_to_drop_box"
  , "feature_flags.can_use_archive_to_google_drive"
  , "feature_flags.can_use_archive_to_one_drive"
  , "feature_flags.can_use_archive_to_share_point"
  , "feature_flags.can_use_archive_to_sftp"
  ]
