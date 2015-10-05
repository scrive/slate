{-# OPTIONS_GHC -fno-warn-orphans #-}
module Doc.Data.SignatoryLink (
    SignOrder(..)
  , SignInfo(..)
  , DeliveryStatus(..)
  , CSVUpload(..)
  , AuthenticationToViewMethod(..)
  , AuthenticationToSignMethod(..)
  , DeliveryMethod(..)
  , ConfirmationDeliveryMethod(..)
  , SignatoryLink(..)
  , signatoryLinksSelectors
  ) where

import Control.Monad.Catch
import Data.Default
import Data.Int
import Database.PostgreSQL.PQTypes
import Data.Unjson
import Data.Functor.Invariant

import DB.Derive
import Doc.Data.SignatoryAttachment
import Doc.Data.SignatoryField
import Doc.SignatoryLinkID
import IPAddress
import KontraPrelude
import MagicHash
import MinutesTime
import User.UserID

newtype SignOrder = SignOrder { unSignOrder :: Int32 }
  deriving (Eq, Ord, PQFormat)
$(newtypeDeriveUnderlyingReadShow ''SignOrder)

instance Unjson SignOrder where
  unjsonDef = invmap SignOrder unSignOrder unjsonDef

instance FromSQL SignOrder where
  type PQBase SignOrder = PQBase Int32
  fromSQL mbase = SignOrder <$> fromSQL mbase
instance ToSQL SignOrder where
  type PQDest SignOrder = PQDest Int32
  toSQL (SignOrder n) = toSQL n

---------------------------------

data SignInfo = SignInfo {
  signtime     :: !UTCTime
, signipnumber :: !IPAddress
} deriving (Eq, Ord, Show)

---------------------------------

data DeliveryStatus
  = Delivered
  | Undelivered
  | Unknown
  | Deferred
    deriving (Eq, Ord, Show)

instance PQFormat DeliveryStatus where
  pqFormat = const $ pqFormat ($undefined::Int16)

instance FromSQL DeliveryStatus where
  type PQBase DeliveryStatus = PQBase Int16
  fromSQL mbase = do
    n <- fromSQL mbase
    case n :: Int16 of
      1 -> return Delivered
      2 -> return Undelivered
      3 -> return Unknown
      4 -> return Deferred
      _ -> throwM RangeError {
        reRange = [(1, 4)]
      , reValue = n
      }

instance ToSQL DeliveryStatus where
  type PQDest DeliveryStatus = PQDest Int16
  toSQL Delivered   = toSQL (1::Int16)
  toSQL Undelivered = toSQL (2::Int16)
  toSQL Unknown     = toSQL (3::Int16)
  toSQL Deferred    = toSQL (4::Int16)

---------------------------------

data CSVUpload = CSVUpload {
  csvcontents  :: ![[String]]
} deriving (Eq, Ord, Show)

instance Unjson CSVUpload where
  unjsonDef = invmap CSVUpload csvcontents unjsonDef

instance PQFormat [[String]] where
  pqFormat = const $ pqFormat ($undefined::String)
instance FromSQL [[String]] where
  type PQBase [[String]] = PQBase String
  fromSQL = jsonFromSQL
instance ToSQL [[String]] where
  type PQDest [[String]] = PQDest String
  toSQL = jsonToSQL

---------------------------------

data AuthenticationToViewMethod
  = StandardAuthenticationToView
  | SEBankIDAuthenticationToView
  | NOBankIDAuthenticationToView
    deriving (Eq, Ord, Show)

instance PQFormat AuthenticationToViewMethod where
  pqFormat = const $ pqFormat ($undefined::Int16)

instance FromSQL AuthenticationToViewMethod where
  type PQBase AuthenticationToViewMethod = PQBase Int16
  fromSQL mbase = do
    n <- fromSQL mbase
    case n :: Int16 of
      1 -> return StandardAuthenticationToView
      2 -> return SEBankIDAuthenticationToView
      3 -> return NOBankIDAuthenticationToView
      _ -> throwM RangeError {
        reRange = [(1, 3)]
      , reValue = n
      }

instance ToSQL AuthenticationToViewMethod where
  type PQDest AuthenticationToViewMethod = PQDest Int16
  toSQL StandardAuthenticationToView      = toSQL (1::Int16)
  toSQL SEBankIDAuthenticationToView      = toSQL (2::Int16)
  toSQL NOBankIDAuthenticationToView      = toSQL (3::Int16)

---------------------------------

data AuthenticationToSignMethod
  = StandardAuthenticationToSign
  | SEBankIDAuthenticationToSign
  | SMSPinAuthenticationToSign
    deriving (Eq, Ord, Show)

instance PQFormat AuthenticationToSignMethod where
  pqFormat = const $ pqFormat ($undefined::Int16)

instance FromSQL AuthenticationToSignMethod where
  type PQBase AuthenticationToSignMethod = PQBase Int16
  fromSQL mbase = do
    n <- fromSQL mbase
    case n :: Int16 of
      1 -> return StandardAuthenticationToSign
      2 -> return SEBankIDAuthenticationToSign
      3 -> return SMSPinAuthenticationToSign
      _ -> throwM RangeError {
        reRange = [(1, 3)]
      , reValue = n
      }

instance ToSQL AuthenticationToSignMethod where
  type PQDest AuthenticationToSignMethod = PQDest Int16
  toSQL StandardAuthenticationToSign      = toSQL (1::Int16)
  toSQL SEBankIDAuthenticationToSign      = toSQL (2::Int16)
  toSQL SMSPinAuthenticationToSign        = toSQL (3::Int16)

---------------------------------

data DeliveryMethod
  = EmailDelivery
  | PadDelivery
  | APIDelivery
  | MobileDelivery
  | EmailAndMobileDelivery
    deriving (Eq, Ord, Show)

instance PQFormat DeliveryMethod where
  pqFormat = const $ pqFormat ($undefined::Int16)

instance FromSQL DeliveryMethod where
  type PQBase DeliveryMethod = PQBase Int16
  fromSQL mbase = do
    n <- fromSQL mbase
    case n :: Int16 of
      1 -> return EmailDelivery
      2 -> return PadDelivery
      3 -> return APIDelivery
      4 -> return MobileDelivery
      5 -> return EmailAndMobileDelivery
      _ -> throwM RangeError {
        reRange = [(1, 5)]
      , reValue = n
      }

instance ToSQL DeliveryMethod where
  type PQDest DeliveryMethod = PQDest Int16
  toSQL EmailDelivery          = toSQL (1::Int16)
  toSQL PadDelivery            = toSQL (2::Int16)
  toSQL APIDelivery            = toSQL (3::Int16)
  toSQL MobileDelivery         = toSQL (4::Int16)
  toSQL EmailAndMobileDelivery = toSQL (5::Int16)

---------------------------------

data ConfirmationDeliveryMethod
  = EmailConfirmationDelivery
  | MobileConfirmationDelivery
  | EmailAndMobileConfirmationDelivery
  | NoConfirmationDelivery
    deriving (Eq, Ord, Show)

instance PQFormat ConfirmationDeliveryMethod where
  pqFormat = const $ pqFormat ($undefined::Int16)

instance FromSQL ConfirmationDeliveryMethod where
  type PQBase ConfirmationDeliveryMethod = PQBase Int16
  fromSQL mbase = do
    n <- fromSQL mbase
    case n :: Int16 of
      1 -> return EmailConfirmationDelivery
      2 -> return MobileConfirmationDelivery
      3 -> return EmailAndMobileConfirmationDelivery
      4 -> return NoConfirmationDelivery
      _ -> throwM RangeError {
        reRange = [(1, 4)]
      , reValue = n
      }

instance ToSQL ConfirmationDeliveryMethod where
  type PQDest ConfirmationDeliveryMethod = PQDest Int16
  toSQL EmailConfirmationDelivery           = toSQL (1::Int16)
  toSQL MobileConfirmationDelivery          = toSQL (2::Int16)
  toSQL EmailAndMobileConfirmationDelivery  = toSQL (3::Int16)
  toSQL NoConfirmationDelivery              = toSQL (4::Int16)

---------------------------------

data SignatoryLink = SignatoryLink {
  signatorylinkid                         :: !SignatoryLinkID
, signatoryfields                         :: ![SignatoryField]
-- | True if signatory is an author of the document
, signatoryisauthor                       :: !Bool
-- | True if signatory participates in signing process
, signatoryispartner                      :: !Bool
, signatorysignorder                      :: !SignOrder
-- | Authentication code
, signatorymagichash                      :: !MagicHash
-- | If this document has been saved to an account, that is the user id
, maybesignatory                          :: !(Maybe UserID)
-- | When a person has signed this document
, maybesigninfo                           :: !(Maybe SignInfo)
-- | When a person has first seen this document
, maybeseeninfo                           :: !(Maybe SignInfo)
-- | when we receive confirmation that a user has read
, maybereadinvite                         :: !(Maybe UTCTime)
-- | Status of email delivery
, mailinvitationdeliverystatus            :: !DeliveryStatus
-- | Status of email delivery
, smsinvitationdeliverystatus             :: !DeliveryStatus
-- | When was put in recycle bin
, signatorylinkdeleted                    :: !(Maybe UTCTime)
-- | When was purged from the system
, signatorylinkreallydeleted              :: !(Maybe UTCTime)
, signatorylinkcsvupload                  :: !(Maybe CSVUpload)
, signatoryattachments                    :: ![SignatoryAttachment]
, signatorylinksignredirecturl            :: !(Maybe String)
, signatorylinkrejectredirecturl          :: !(Maybe String)
, signatorylinkrejectiontime              :: !(Maybe UTCTime)
, signatorylinkrejectionreason            :: !(Maybe String)
, signatorylinkauthenticationtoviewmethod :: !AuthenticationToViewMethod
, signatorylinkauthenticationtosignmethod :: !AuthenticationToSignMethod
, signatorylinkdeliverymethod             :: !DeliveryMethod
, signatorylinkconfirmationdeliverymethod :: !ConfirmationDeliveryMethod
-- | If a person has identified to view the document
, signatorylinkidentifiedtoview           :: !Bool
} deriving (Show)

instance Default SignatoryLink where
  def = SignatoryLink {
    signatorylinkid = unsafeSignatoryLinkID 0
  , signatoryfields = []
  , signatoryisauthor = False
  , signatoryispartner = False
  , signatorysignorder = SignOrder 1
  , signatorymagichash = unsafeMagicHash 0
  , maybesignatory = Nothing
  , maybesigninfo = Nothing
  , maybeseeninfo = Nothing
  , maybereadinvite = Nothing
  , mailinvitationdeliverystatus = Unknown
  , smsinvitationdeliverystatus = Unknown
  , signatorylinkdeleted = Nothing
  , signatorylinkreallydeleted = Nothing
  , signatorylinkcsvupload = Nothing
  , signatoryattachments = []
  , signatorylinksignredirecturl = Nothing
  , signatorylinkrejectredirecturl = Nothing
  , signatorylinkrejectiontime = Nothing
  , signatorylinkrejectionreason = Nothing
  , signatorylinkauthenticationtoviewmethod = StandardAuthenticationToView
  , signatorylinkauthenticationtosignmethod = StandardAuthenticationToSign
  , signatorylinkdeliverymethod = EmailDelivery
  , signatorylinkconfirmationdeliverymethod = EmailConfirmationDelivery
  , signatorylinkidentifiedtoview = False
  }

---------------------------------

signatoryLinksSelectors :: [SQL]
signatoryLinksSelectors = [
    "signatory_links.id"
  , "ARRAY(SELECT (" <> mintercalate ", " signatoryFieldsSelectors <> ")::signatory_field FROM signatory_link_fields WHERE signatory_links.id = signatory_link_fields.signatory_link_id ORDER BY signatory_link_fields.id)"
  , "signatory_links.is_author"
  , "signatory_links.is_partner"
  , "signatory_links.sign_order"
  , "signatory_links.token"
  , "signatory_links.user_id"
  , "signatory_links.sign_time"
  , "signatory_links.sign_ip"
  , "signatory_links.seen_time"
  , "signatory_links.seen_ip"
  , "signatory_links.read_invitation"
  , "signatory_links.mail_invitation_delivery_status"
  , "signatory_links.sms_invitation_delivery_status"
  , "signatory_links.deleted"
  , "signatory_links.really_deleted"
  , "signatory_links.csv_contents"
  , "ARRAY(SELECT (" <> mintercalate ", " signatoryAttachmentsSelectors <> ")::signatory_attachment FROM signatory_attachments WHERE signatory_links.id = signatory_attachments.signatory_link_id ORDER BY signatory_attachments.file_id)"
  , "signatory_links.sign_redirect_url"
  , "signatory_links.reject_redirect_url"
  , "signatory_links.rejection_time"
  , "signatory_links.rejection_reason"
  , "signatory_links.authentication_to_view_method"
  , "signatory_links.authentication_to_sign_method"
  , "signatory_links.delivery_method"
  , "signatory_links.confirmation_delivery_method"
  , "(SELECT EXISTS (SELECT 1 FROM eid_authentications WHERE signatory_links.id = eid_authentications.signatory_link_id))"
  ]

type instance CompositeRow SignatoryLink = (SignatoryLinkID, CompositeArray1 SignatoryField, Bool, Bool, SignOrder, MagicHash, Maybe UserID, Maybe UTCTime, Maybe IPAddress, Maybe UTCTime, Maybe IPAddress, Maybe UTCTime, DeliveryStatus, DeliveryStatus, Maybe UTCTime, Maybe UTCTime, Maybe [[String]], CompositeArray1 SignatoryAttachment, Maybe String, Maybe String, Maybe UTCTime, Maybe String, AuthenticationToViewMethod, AuthenticationToSignMethod, DeliveryMethod, ConfirmationDeliveryMethod, Bool)

instance PQFormat SignatoryLink where
  pqFormat _ = "%signatory_link"

instance CompositeFromSQL SignatoryLink where
  toComposite (slid, CompositeArray1 fields, is_author, is_partner, sign_order, magic_hash, muser_id, msign_time, msign_ip, mseen_time, mseen_ip, mread_invite, mail_invitation_delivery_status, sms_invitation_delivery_status, mdeleted, mreally_deleted, mcsv_contents, CompositeArray1 attachments, msign_redirect_url, mreject_redirect_url, mrejection_time, mrejection_reason, authentication_to_view_method, authentication_to_sign_method, delivery_method, confirmation_delivery_method, has_identified) = SignatoryLink {
    signatorylinkid = slid
  , signatoryfields = fields
  , signatoryisauthor = is_author
  , signatoryispartner = is_partner
  , signatorysignorder = sign_order
  , signatorymagichash = magic_hash
  , maybesignatory = muser_id
  , maybesigninfo = SignInfo <$> msign_time <*> msign_ip
  , maybeseeninfo = SignInfo <$> mseen_time <*> mseen_ip
  , maybereadinvite = mread_invite
  , mailinvitationdeliverystatus = mail_invitation_delivery_status
  , smsinvitationdeliverystatus = sms_invitation_delivery_status
  , signatorylinkdeleted = mdeleted
  , signatorylinkreallydeleted = mreally_deleted
  , signatorylinkcsvupload = CSVUpload <$> mcsv_contents
  , signatoryattachments = attachments
  , signatorylinksignredirecturl = msign_redirect_url
  , signatorylinkrejectredirecturl = mreject_redirect_url
  , signatorylinkrejectiontime = mrejection_time
  , signatorylinkrejectionreason = mrejection_reason
  , signatorylinkauthenticationtoviewmethod = authentication_to_view_method
  , signatorylinkauthenticationtosignmethod = authentication_to_sign_method
  , signatorylinkdeliverymethod = delivery_method
  , signatorylinkconfirmationdeliverymethod = confirmation_delivery_method
  , signatorylinkidentifiedtoview = has_identified
  }
