{-# OPTIONS_GHC -fno-warn-orphans #-}
{-# LANGUAGE CPP #-}
module Doc.DocStateData
    ( Author(..)
    , CSVUpload(..)
    , CancelationReason(..)
    , ChargeMode(..)
    , DocStats(..)
    , Document(..)
    , DocumentFunctionality(..)
    , DocumentHistoryEntry(..)
    , DocumentID(..)
    , DocumentLogEntry(..)
    , DocumentSharing(..)
    , DocumentStatus(..)
    , DocumentTag(..)
    , DocumentUI(..)
    , DocumentType(..)
    , DocumentProcess(..)
    , Documents
    , FieldDefinition(..)
    , FieldPlacement(..)
    , File(..)
    , FileID(..)
    , FileStorage(..)
    , IdentificationType(..)
    , JpegPages(..)
    , SignInfo(..)
    , SignOrder(..)
    , Signatory(..)
    , SignatoryField(..)
    , FieldType(..)
    , SignatoryDetails(..)
    , SignatoryLink(..)
    , SignatoryLinkID(..)
    , SignatoryRole(..)
    , SignatureInfo(..)
    , SignatureProvider(..)
    , TimeoutTime(..)
    , AuthorAttachment(..)
    , SignatoryAttachment(..)
    , Supervisor(..)
    , getFieldOfType
    , getValueOfType
    , documentHistoryToDocumentLog
    , emptyDocumentUI
    , doctypeFromString
    ) where

import API.Service.Model
import Company.Model
import Data.Data (Data)
import Data.Int
import Data.Maybe
import Data.Word
import DB.Derive
import DB.Types
import Happstack.Data
import Happstack.Data.IxSet as IxSet
import Happstack.Server.SimpleHTTP
import Happstack.State
import Happstack.Util.Common
import Mails.MailsUtil
import MinutesTime
import Misc
import User.Model
import qualified Data.ByteString as BS
import qualified Data.ByteString.UTF8 as BS
import File.FileID
import File.File
import Doc.JpegPages

import System.IO.Unsafe

newtype Author = Author { unAuthor :: UserID }
    deriving (Eq, Ord, Typeable)

newtype DocumentID = DocumentID { unDocumentID :: Int64 }
    deriving (Eq, Ord, Typeable, Data) -- Data needed by PayEx modules
newtype SignatoryLinkID = SignatoryLinkID { unSignatoryLinkID :: Int }
    deriving (Eq, Ord, Typeable, Data)
newtype TimeoutTime = TimeoutTime { unTimeoutTime :: MinutesTime }
    deriving (Eq, Ord, Typeable)
newtype SignOrder = SignOrder { unSignOrder :: Integer }
    deriving (Eq, Ord, Typeable)

instance Show SignOrder where
    show (SignOrder n) = show n

data IdentificationType = EmailIdentification
                        | ELegitimationIdentification
    deriving (Eq, Ord, Bounded, Enum, Typeable)

data SignatureProvider = BankIDProvider
                       | TeliaProvider
                       | NordeaProvider
    deriving (Eq, Ord, Typeable)

data SignatureInfo0 = SignatureInfo0 { signatureinfotext0        :: String
                                     , signatureinfosignature0   :: String
                                     , signatureinfocertificate0 :: String
                                     , signatureinfoprovider0    :: SignatureProvider
                                     }
    deriving (Eq, Ord, Typeable)

data SignatureInfo = SignatureInfo { signatureinfotext        :: String
                                   , signatureinfosignature   :: String
                                   , signatureinfocertificate :: String
                                   , signatureinfoprovider    :: SignatureProvider
                                   , signaturefstnameverified :: Bool
                                   , signaturelstnameverified :: Bool
                                   , signaturepersnumverified :: Bool
                                   }
    deriving (Eq, Ord, Typeable)

-- added by Eric Normand for template system
-- Defines a new field to be placed in a contract
data FieldDefinition0 = FieldDefinition0
    { fieldlabel0 :: BS.ByteString
    , fieldvalue0 :: BS.ByteString
    , fieldplacements0 :: [FieldPlacement]
    }
    deriving (Eq, Ord, Typeable)

data FieldDefinition = FieldDefinition
    { fieldlabel :: BS.ByteString
    , fieldvalue :: BS.ByteString
    , fieldplacements :: [FieldPlacement]
    , fieldfilledbyauthor :: Bool
    }
    deriving (Eq, Ord, Typeable)

data FieldType =
    FirstNameFT | LastNameFT | CompanyFT | PersonalNumberFT
  | CompanyNumberFT | EmailFT | CustomFT BS.ByteString Bool -- label filledbyauthor
    deriving (Eq, Ord, Data, Typeable)

data SignatoryField = SignatoryField {
    sfType       :: FieldType
  , sfValue      :: BS.ByteString
  , sfPlacements :: [FieldPlacement]
  } deriving (Eq, Ord, Data, Typeable)

-- defines where a field is placed
data FieldPlacement = FieldPlacement
    { placementx :: Int
    , placementy :: Int
    , placementpage :: Int
    , placementpagewidth :: Int
    , placementpageheight :: Int
    }
    deriving (Eq, Ord, Data, Typeable)
-- end of updates for template system

data SignatoryDetails0 = SignatoryDetails0
    { signatoryname00      :: BS.ByteString  -- "Gracjan Polak"
    , signatorycompany00   :: BS.ByteString  -- SkrivaPå
    , signatorynumber00    :: BS.ByteString  -- 123456789
    , signatoryemail00     :: BS.ByteString  -- "gracjanpolak@skrivapa.se"
    }
    deriving (Eq, Ord, Typeable)

data SignatoryDetails1 = SignatoryDetails1
    { signatoryname1      :: BS.ByteString
    , signatorycompany1   :: BS.ByteString
    , signatorynumber1    :: BS.ByteString
    , signatoryemail1     :: BS.ByteString
    , signatorynameplacements1 :: [FieldPlacement]
    , signatorycompanyplacements1 :: [FieldPlacement]
    , signatoryemailplacements1 :: [FieldPlacement]
    , signatorynumberplacements1 :: [FieldPlacement]
    , signatoryotherfields1 :: [FieldDefinition]
    }
    deriving (Eq, Ord, Typeable)

data SignatoryDetails2 = SignatoryDetails2
    { signatoryfstname2   :: BS.ByteString
    , signatorysndname2   :: BS.ByteString
    , signatorycompany2   :: BS.ByteString
    , signatorynumber2    :: BS.ByteString
    , signatoryemail2     :: BS.ByteString
    , signatorynameplacements2 :: [FieldPlacement]
    , signatorycompanyplacements2 :: [FieldPlacement]
    , signatoryemailplacements2 :: [FieldPlacement]
    , signatorynumberplacements2 :: [FieldPlacement]
    , signatoryotherfields2 :: [FieldDefinition]
    }
    deriving (Eq, Ord, Typeable)


data SignatoryDetails3 = SignatoryDetails3
    { signatoryfstname3   :: BS.ByteString  -- "Gracjan Polak"
    , signatorysndname3   :: BS.ByteString  -- "Gracjan Polak"
    , signatorycompany3   :: BS.ByteString  -- SkrivaPå
    , signatorynumber3    :: BS.ByteString  -- 123456789
    , signatoryemail3     :: BS.ByteString  -- "gracjanpolak@skrivapa.se"
    -- for templates
    , signatoryfstnameplacements3 :: [FieldPlacement]
    , signatorysndnameplacements3 :: [FieldPlacement]
    , signatorycompanyplacements3 :: [FieldPlacement]
    , signatoryemailplacements3 :: [FieldPlacement]
    , signatorynumberplacements3 :: [FieldPlacement]
    , signatoryotherfields3 :: [FieldDefinition]
    }
    deriving (Eq, Ord, Typeable)

data SignatoryDetails4 = SignatoryDetails4
    { signatoryfstname4        :: BS.ByteString  -- "Gracjan"
    , signatorysndname4        :: BS.ByteString  -- "Polak"
    , signatorycompany4        :: BS.ByteString  -- SkrivaPå
    , signatorypersonalnumber4 :: BS.ByteString  -- 123456789
    , signatorycompanynumber4  :: BS.ByteString  -- 123456789
    , signatoryemail4          :: BS.ByteString  -- "gracjanpolak@skrivapa.se"
    -- for templates
    , signatoryfstnameplacements4        :: [FieldPlacement]
    , signatorysndnameplacements4        :: [FieldPlacement]
    , signatorycompanyplacements4        :: [FieldPlacement]
    , signatoryemailplacements4          :: [FieldPlacement]
    , signatorypersonalnumberplacements4 :: [FieldPlacement]
    , signatorycompanynumberplacements4  :: [FieldPlacement]
    , signatoryotherfields4              :: [FieldDefinition]
    }
    deriving (Eq, Ord, Typeable)

data SignatoryDetails5 = SignatoryDetails5
    { signatoryfstname5        :: BS.ByteString  -- "Gracjan"
    , signatorysndname5        :: BS.ByteString  -- "Polak"
    , signatorycompany5        :: BS.ByteString  -- SkrivaPå
    , signatorypersonalnumber5 :: BS.ByteString  -- 123456789
    , signatorycompanynumber5  :: BS.ByteString  -- 123456789
    , signatoryemail5          :: BS.ByteString  -- "gracjanpolak@skrivapa.se"
    -- for ordered signing
    , signatorysignorder5      :: SignOrder
    -- for templates
    , signatoryfstnameplacements5        :: [FieldPlacement]
    , signatorysndnameplacements5        :: [FieldPlacement]
    , signatorycompanyplacements5        :: [FieldPlacement]
    , signatoryemailplacements5          :: [FieldPlacement]
    , signatorypersonalnumberplacements5 :: [FieldPlacement]
    , signatorycompanynumberplacements5  :: [FieldPlacement]
    , signatoryotherfields5              :: [FieldDefinition]
    }
    deriving (Eq, Ord, Typeable)

data SignatoryDetails = SignatoryDetails
    { signatorysignorder :: SignOrder
    -- for templates
    , signatoryfields    :: [SignatoryField]
    }
    deriving (Eq, Ord, Typeable)

data SignatoryLink1 = SignatoryLink1
    { signatorylinkid1    :: SignatoryLinkID
    , signatorydetails1   :: SignatoryDetails
    , maybesignatory1     :: Maybe Signatory
    , maybesigninfo1      :: Maybe SignInfo
    , maybeseentime1      :: Maybe MinutesTime
    }
    deriving (Eq, Ord, Typeable)

data SignatoryLink2 = SignatoryLink2
    { signatorylinkid2    :: SignatoryLinkID
    , signatorydetails2   :: SignatoryDetails
    , signatorymagichash2 :: MagicHash
    , maybesignatory2     :: Maybe Signatory
    , maybesigninfo2      :: Maybe SignInfo
    , maybeseentime2      :: Maybe MinutesTime
    }
    deriving (Eq, Ord, Typeable)

data SignatoryLink3 = SignatoryLink3
    { signatorylinkid3    :: SignatoryLinkID
    , signatorydetails3   :: SignatoryDetails
    , signatorymagichash3 :: MagicHash
    , maybesignatory3     :: Maybe Signatory
    , maybesigninfo3      :: Maybe SignInfo
    , maybeseeninfo3      :: Maybe SignInfo
    }
    deriving (Eq, Ord, Typeable)

data SignatoryLink4 = SignatoryLink4
    { signatorylinkid4    :: SignatoryLinkID
    , signatorydetails4   :: SignatoryDetails
    , signatorymagichash4 :: MagicHash
    , maybesignatory4     :: Maybe Signatory
    , maybesigninfo4      :: Maybe SignInfo
    , maybeseeninfo4      :: Maybe SignInfo
    , invitationdeliverystatus4 :: MailsDeliveryStatus
    }
    deriving (Eq, Ord, Typeable)

data SignatoryLink5 = SignatoryLink5
    { signatorylinkid5          :: SignatoryLinkID
    , signatorydetails5         :: SignatoryDetails
    , signatorymagichash5       :: MagicHash
    , maybesignatory5           :: Maybe Signatory
    , maybesigninfo5            :: Maybe SignInfo
    , maybeseeninfo5            :: Maybe SignInfo
    , invitationdeliverystatus5 :: MailsDeliveryStatus
    , signatorysignatureinfo5   :: Maybe SignatureInfo
    }
    deriving (Eq, Ord, Typeable)

data SignatoryLink6 = SignatoryLink6
    { signatorylinkid6          :: SignatoryLinkID     -- ^ a random number id, unique in th escope of a document only
    , signatorydetails6         :: SignatoryDetails    -- ^ details of this person as filled in invitation
    , signatorymagichash6       :: MagicHash           -- ^ authentication code
    , maybesignatory6           :: Maybe UserID        -- ^ if this document has been saved to an account, that is the user id
    , maybesigninfo6            :: Maybe SignInfo      -- ^ when a person has signed this document
    , maybeseeninfo6            :: Maybe SignInfo      -- ^ when a person has first seen this document
    , invitationdeliverystatus6 :: MailsDeliveryStatus -- ^ status of email delivery
    , signatorysignatureinfo6   :: Maybe SignatureInfo -- ^ info about what fields have been filled for this person
    }
    deriving (Eq, Ord, Typeable)

data SignatoryLink7 = SignatoryLink7
    { signatorylinkid7          :: SignatoryLinkID     -- ^ a random number id, unique in th escope of a document only
    , signatorydetails7         :: SignatoryDetails    -- ^ details of this person as filled in invitation
    , signatorymagichash7       :: MagicHash           -- ^ authentication code
    , maybesignatory7           :: Maybe UserID        -- ^ if this document has been saved to an account, that is the user id
    , maybesigninfo7            :: Maybe SignInfo      -- ^ when a person has signed this document
    , maybeseeninfo7            :: Maybe SignInfo      -- ^ when a person has first seen this document
    , invitationdeliverystatus7 :: MailsDeliveryStatus -- ^ status of email delivery
    , signatorysignatureinfo7   :: Maybe SignatureInfo -- ^ info about what fields have been filled for this person
    , signatoryroles7           :: [SignatoryRole]
    , signatorylinkdeleted7     :: Bool
    }
    deriving (Eq, Ord, Typeable)

data SignatoryLink8 = SignatoryLink8
    { signatorylinkid8          :: SignatoryLinkID     -- ^ a random number id, unique in th escope of a document only
    , signatorydetails8         :: SignatoryDetails    -- ^ details of this person as filled in invitation
    , signatorymagichash8       :: MagicHash           -- ^ authentication code
    , maybesignatory8           :: Maybe UserID        -- ^ if this document has been saved to an account, that is the user id
    , maybesigninfo8            :: Maybe SignInfo      -- ^ when a person has signed this document
    , maybeseeninfo8            :: Maybe SignInfo      -- ^ when a person has first seen this document
    , maybereadinvite8          :: Maybe MinutesTime   -- ^ when we receive confirmation that a user has read
    , invitationdeliverystatus8 :: MailsDeliveryStatus -- ^ status of email delivery
    , signatorysignatureinfo8   :: Maybe SignatureInfo -- ^ info about what fields have been filled for this person
    , signatoryroles8           :: [SignatoryRole]
    , signatorylinkdeleted8     :: Bool
    }
    deriving (Eq, Ord, Typeable)

data SignatoryLink9 = SignatoryLink9
    { signatorylinkid9          :: SignatoryLinkID     -- ^ a random number id, unique in th escope of a document only
    , signatorydetails9         :: SignatoryDetails    -- ^ details of this person as filled in invitation
    , signatorymagichash9       :: MagicHash           -- ^ authentication code
    , maybesignatory9           :: Maybe UserID        -- ^ if this document has been saved to an account, that is the user id
    , maybesupervisor9          :: Maybe UserID        -- ^ if this document has been saved to an account with a supervisor, this is the userid
    , maybesigninfo9            :: Maybe SignInfo      -- ^ when a person has signed this document
    , maybeseeninfo9            :: Maybe SignInfo      -- ^ when a person has first seen this document
    , maybereadinvite9          :: Maybe MinutesTime   -- ^ when we receive confirmation that a user has read
    , invitationdeliverystatus9 :: MailsDeliveryStatus -- ^ status of email delivery
    , signatorysignatureinfo9   :: Maybe SignatureInfo -- ^ info about what fields have been filled for this person
    , signatoryroles9           :: [SignatoryRole]
    , signatorylinkdeleted9     :: Bool
    }
    deriving (Eq, Ord, Typeable)

data SignatoryLink10 = SignatoryLink10
    { signatorylinkid10            :: SignatoryLinkID     -- ^ a random number id, unique in th escope of a document only
    , signatorydetails10           :: SignatoryDetails    -- ^ details of this person as filled in invitation
    , signatorymagichash10         :: MagicHash           -- ^ authentication code
    , maybesignatory10             :: Maybe UserID        -- ^ if this document has been saved to an account, that is the user id
    , maybesupervisor10            :: Maybe UserID        -- ^ if this document has been saved to an account with a supervisor, this is the userid
    , maybesigninfo10              :: Maybe SignInfo      -- ^ when a person has signed this document
    , maybeseeninfo10              :: Maybe SignInfo      -- ^ when a person has first seen this document
    , maybereadinvite10            :: Maybe MinutesTime   -- ^ when we receive confirmation that a user has read
    , invitationdeliverystatus10   :: MailsDeliveryStatus -- ^ status of email delivery
    , signatorysignatureinfo10     :: Maybe SignatureInfo -- ^ info about what fields have been filled for this person
    , signatoryroles10             :: [SignatoryRole]
    , signatorylinkdeleted10       :: Bool -- ^ when true sends the doc to the recycle bin for that sig
    , signatorylinkreallydeleted10 :: Bool -- ^ when true it means that the doc has been removed from the recycle bin
    }
    deriving (Eq, Ord, Typeable)

data SignatoryLink = SignatoryLink
    { signatorylinkid            :: SignatoryLinkID     -- ^ a random number id, unique in th escope of a document only
    , signatorydetails           :: SignatoryDetails    -- ^ details of this person as filled in invitation
    , signatorymagichash         :: MagicHash           -- ^ authentication code
    , maybesignatory             :: Maybe UserID        -- ^ if this document has been saved to an account, that is the user id
    , maybesupervisor            :: Maybe UserID        -- ^ THIS IS NOW DEPRECATED - use maybecompany instead
    , maybecompany               :: Maybe CompanyID     -- ^ if this document has been saved to a company account this is the companyid
    , maybesigninfo              :: Maybe SignInfo      -- ^ when a person has signed this document
    , maybeseeninfo              :: Maybe SignInfo      -- ^ when a person has first seen this document
    , maybereadinvite            :: Maybe MinutesTime   -- ^ when we receive confirmation that a user has read
    , invitationdeliverystatus   :: MailsDeliveryStatus -- ^ status of email delivery
    , signatorysignatureinfo     :: Maybe SignatureInfo -- ^ info about what fields have been filled for this person
    , signatoryroles             :: [SignatoryRole]
    , signatorylinkdeleted       :: Bool -- ^ when true sends the doc to the recycle bin for that sig
    , signatorylinkreallydeleted :: Bool -- ^ when true it means that the doc has been removed from the recycle bin
    }
    deriving (Eq, Ord, Typeable)

data SignatoryRole = SignatoryPartner | SignatoryAuthor
    deriving (Eq, Ord, Bounded, Enum, Typeable, Show)

instance Version SignatoryRole



data SignInfo = SignInfo
    { signtime :: MinutesTime
    , signipnumber :: Word32
    }
    deriving (Eq, Ord, Typeable)

data SignInfo0 = SignInfo0
    { signtime0 :: MinutesTime
    }
    deriving (Eq, Ord, Typeable)

newtype Signatory = Signatory { unSignatory :: UserID }
    deriving (Eq, Ord, Typeable)

newtype Supervisor = Supervisor { unSupervisor :: UserID }
                   deriving (Eq, Ord, Typeable)

{-
   Document start in Preparation state.

   Meaning:
   * Preparation: Only author can see it. He's still editing.
   * Pending: People can sign document. Could be timed out.
   * AwaitingAuthor: Everyone has signed but the author.
   * Closed: Everybody signed. This is final state.
   * Canceled: Author has canceled the document.
   * Timedout: This works as autocancel and has exactly same
     properties.

   Transitions:
   * Preparation to Pending: When invitations are sent.
   * Preparation to Cancel: mail about cancel to
     all who have signed it already is sent.
     TODO: Should other parties get an email?
   * Preparation to Timedout: mail about timeout to
     all who have signed it already is sent.
   * Pending to Closed: When everyone has signed.
     Info about closed deal is sent to everybody involved.
   * Pending to AwaitingAuthor: When all signatories have signed and there were fields.
     Info is sent to author.
   * AwaitingAuthor to Closed: Author signs it.
   * Pending to Cancel: Send no emails.
   * Pending to Timeout: TODO: No action?

   Allowed actions:
   * Preparation: change document, change title, add/rem signatories
   * Pending: change email of a signatory, signatory can sign
   * AwaitingAuthor: autho can sign.
   * Closed: nothing
   * Canceled: edit back to Preparation
   * Timedout: edit back to Preparation

   Archived bit:
   * This bit just moves document out of main view.
 -}

data DocumentStatus = Preparation
                    | Pending
                    | Closed
                    | Canceled
                    | Timedout
                    | Rejected
                    | AwaitingAuthor
                    | DocumentError String
    deriving (Eq, Ord, Typeable, Data)

data DocumentType0 = Contract0 | ContractTemplate0 | Offer0 | OfferTemplate0 | Attachment0 | AttachmentTemplate0
    deriving (Eq, Ord, Typeable)

data DocumentProcess = Contract | Offer | Order
    deriving (Eq, Ord, Typeable)

data DocumentType = Signable DocumentProcess | Template DocumentProcess | Attachment | AttachmentTemplate
    deriving (Eq, Ord, Typeable)
             
-- | Terrible, I know. Better idea?
doctypeFromString :: String -> DocumentType
doctypeFromString "Signable Contract"  = Signable Contract
doctypeFromString "Signable Offer"     = Signable Offer
doctypeFromString "Signable Order"     = Signable Order
doctypeFromString "Template Contract"  = Template Contract
doctypeFromString "Template Offer"     = Template Offer
doctypeFromString "Template Order"     = Template Order
doctypeFromString "Attachment"         = Attachment
doctypeFromString "AttachmentTemplate" = AttachmentTemplate
doctypeFromString _                    = error "Bad document type"

{- |
    This is no longer used because there's no quarantine anymore, it's been replaced
    with a flag called documentdeleted
-}
data DocumentRecordStatus = LiveDocument | QuarantinedDocument | DeletedDocument
    deriving (Eq, Ord, Typeable, Show)

data DocumentFunctionality = BasicFunctionality | AdvancedFunctionality
    deriving (Eq, Ord, Typeable)

data ChargeMode = ChargeInitialFree   -- initial 5 documents are free
                | ChargeNormal        -- value times number of people involved

    deriving (Eq, Ord, Typeable)

data DocumentSharing = Private
                       | Shared -- means that the document is shared with subaccounts, and those with same parent accounts
    deriving (Eq, Ord, Typeable)

data DocumentTag = DocumentTag {
        tagname :: BS.ByteString
     ,  tagvalue :: BS.ByteString
     } deriving (Eq, Ord, Typeable, Data)

data DocumentUI = DocumentUI {
        documentmailfooter :: Maybe BS.ByteString
    } deriving (Eq, Ord, Typeable)
    
emptyDocumentUI :: DocumentUI
emptyDocumentUI = DocumentUI {
                    documentmailfooter = Nothing
                   }

data DocumentHistoryEntry0 = DocumentHistoryCreated0 { dochisttime0 :: MinutesTime }
                          | DocumentHistoryInvitationSent0 { dochisttime0 :: MinutesTime
                                                          , ipnumber0 :: Word32
                                                          }    -- changed state from Preparatio to Pending
    deriving (Eq, Ord, Typeable)

data DocumentHistoryEntry
    = DocumentHistoryCreated
      { dochisttime :: MinutesTime
      }
    | DocumentHistoryInvitationSent
      { dochisttime :: MinutesTime
      , ipnumber :: Word32
      , dochistsignatories :: [SignatoryDetails]
      }    -- changed state from Preparatio to Pending
    | DocumentHistoryTimedOut
      { dochisttime :: MinutesTime
      }
    | DocumentHistorySigned
      { dochisttime :: MinutesTime
      , ipnumber :: Word32
      , dochistsignatorydetails :: SignatoryDetails
      }
    | DocumentHistoryRejected
      { dochisttime :: MinutesTime
      , ipnumber :: Word32
      , dochistsignatorydetails :: SignatoryDetails
      }
    | DocumentHistoryClosed
      { dochisttime :: MinutesTime
      , ipnumber :: Word32
      }
    | DocumentHistoryCanceled
      { dochisttime :: MinutesTime
      , ipnumber :: Word32
      -- , dochistsignatorydetails :: SignatoryDetails
      }
    | DocumentHistoryRestarted
      { dochisttime :: MinutesTime
      , ipnumber :: Word32
      }
    deriving (Eq, Ord, Typeable)

data DocumentLogEntry = DocumentLogEntry MinutesTime BS.ByteString
    deriving (Typeable, Show, Data)

$(deriveSerialize ''DocumentLogEntry)
instance Version DocumentLogEntry

getFieldOfType :: FieldType -> [SignatoryField] -> Maybe SignatoryField
getFieldOfType _ [] = Nothing
getFieldOfType t (sf:rest) =
  if sfType sf == t then Just sf else getFieldOfType t rest

getValueOfType :: FieldType -> SignatoryDetails -> BS.ByteString
getValueOfType t = fromMaybe BS.empty . fmap sfValue . getFieldOfType t . signatoryfields


documentHistoryToDocumentLog :: DocumentHistoryEntry -> DocumentLogEntry
documentHistoryToDocumentLog DocumentHistoryCreated
      { dochisttime
      } = DocumentLogEntry dochisttime $ BS.fromString "Document created"
documentHistoryToDocumentLog DocumentHistoryInvitationSent
      { dochisttime
      , ipnumber
      } = DocumentLogEntry dochisttime $ BS.fromString $ "Invitations sent to signatories" ++ formatIP ipnumber
documentHistoryToDocumentLog DocumentHistoryTimedOut
      { dochisttime
      } = DocumentLogEntry dochisttime $ BS.fromString "Document timed out"
documentHistoryToDocumentLog DocumentHistorySigned
      { dochisttime
      , ipnumber
      } = DocumentLogEntry dochisttime $ BS.fromString $ "Document signed by a signatory" ++ formatIP ipnumber
documentHistoryToDocumentLog DocumentHistoryRejected
      { dochisttime
      , ipnumber
      } = DocumentLogEntry dochisttime $ BS.fromString $ "Document rejected by a signatory" ++ formatIP ipnumber
documentHistoryToDocumentLog DocumentHistoryClosed
      { dochisttime
      , ipnumber
      } = DocumentLogEntry dochisttime $ BS.fromString $ "Document closed" ++ formatIP ipnumber
documentHistoryToDocumentLog DocumentHistoryCanceled
      { dochisttime
      , ipnumber
      } = DocumentLogEntry dochisttime $ BS.fromString $ "Document canceled" ++ formatIP ipnumber
documentHistoryToDocumentLog DocumentHistoryRestarted
      { dochisttime
      , ipnumber
      } = DocumentLogEntry dochisttime $ BS.fromString $ "Document restarted" ++ formatIP ipnumber

data DocStats = DocStats
                { doccount          :: !Int
                , signaturecount    :: !Int
                , signaturecount1m  :: !Int
                , signaturecount2m  :: !Int
                , signaturecount3m  :: !Int
                , signaturecount6m  :: !Int
                , signaturecount12m :: !Int
                }
    deriving (Eq, Ord, Typeable, Data) -- Data instance used for View modules (quite incorrectly there, please remove ASAP)


data Document23 = Document23
    { documentid23                     :: DocumentID
    , documenttitle23                  :: BS.ByteString
    , documentsignatorylinks23         :: [SignatoryLink]
    , documentfiles23                  :: [File]
    , documentsealedfiles23            :: [File]
    , documentstatus23                 :: DocumentStatus
    , documenttype23                   :: DocumentType
    , documentfunctionality23          :: DocumentFunctionality
    , documentctime23                  :: MinutesTime
    , documentmtime23                  :: MinutesTime
    , documentdaystosign23             :: Maybe Int
    , documenttimeouttime23            :: Maybe TimeoutTime
    , documentinvitetime23             :: Maybe SignInfo
    , documentlog23                    :: [DocumentLogEntry]      -- to be made into plain text
    , documentinvitetext23             :: BS.ByteString
    , documenttrustweaverreference23   :: Maybe BS.ByteString
    , documentallowedidtypes23         :: [IdentificationType]
    , documentcsvupload23              :: Maybe CSVUpload
    , documentcancelationreason23      :: Maybe CancelationReason -- When a document is cancelled, there are two (for the moment) possible explanations. Manually cancelled by the author and automatically cancelled by the eleg service because the wrong person was signing.
    , documentsharing23                :: DocumentSharing
    , documentrejectioninfo23          :: Maybe (MinutesTime, SignatoryLinkID, BS.ByteString)
    , documenttags23                   :: [DocumentTag]
    , documentservice23                :: Maybe ServiceID
    , documentattachments23            :: [DocumentID]
    } deriving Typeable

data Document24 = Document24
    { documentid24                     :: DocumentID
    , documenttitle24                  :: BS.ByteString
    , documentsignatorylinks24         :: [SignatoryLink]
    , documentfiles24                  :: [File]
    , documentsealedfiles24            :: [File]
    , documentstatus24                 :: DocumentStatus
    , documenttype24                   :: DocumentType
    , documentfunctionality24          :: DocumentFunctionality
    , documentctime24                  :: MinutesTime
    , documentmtime24                  :: MinutesTime
    , documentdaystosign24             :: Maybe Int
    , documenttimeouttime24            :: Maybe TimeoutTime
    , documentinvitetime24             :: Maybe SignInfo
    , documentlog24                    :: [DocumentLogEntry]      -- to be made into plain text
    , documentinvitetext24             :: BS.ByteString
    , documenttrustweaverreference24   :: Maybe BS.ByteString
    , documentallowedidtypes24         :: [IdentificationType]
    , documentcsvupload24              :: Maybe CSVUpload
    , documentcancelationreason24      :: Maybe CancelationReason -- When a document is cancelled, there are two (for the moment) possible explanations. Manually cancelled by the author and automatically cancelled by the eleg service because the wrong person was signing.
    , documentsharing24                :: DocumentSharing
    , documentrejectioninfo24          :: Maybe (MinutesTime, SignatoryLinkID, BS.ByteString)
    , documenttags24                   :: [DocumentTag]
    , documentservice24                :: Maybe ServiceID
    , documentattachments24            :: [DocumentID]
    , documentoriginalcompany24        :: Maybe CompanyID
    } deriving Typeable

-- migration for author attachments
data Document25 = Document25
    { documentid25                     :: DocumentID
    , documenttitle25                  :: BS.ByteString
    , documentsignatorylinks25         :: [SignatoryLink]
    , documentfiles25                  :: [File]
    , documentsealedfiles25            :: [File]
    , documentstatus25                 :: DocumentStatus
    , documenttype25                   :: DocumentType
    , documentfunctionality25          :: DocumentFunctionality
    , documentctime25                  :: MinutesTime
    , documentmtime25                  :: MinutesTime
    , documentdaystosign25             :: Maybe Int
    , documenttimeouttime25            :: Maybe TimeoutTime
    , documentinvitetime25             :: Maybe SignInfo
    , documentlog25                    :: [DocumentLogEntry]      -- to be made into plain text
    , documentinvitetext25             :: BS.ByteString
    , documenttrustweaverreference25   :: Maybe BS.ByteString
    , documentallowedidtypes25         :: [IdentificationType]
    , documentcsvupload25              :: Maybe CSVUpload
    , documentcancelationreason25      :: Maybe CancelationReason -- When a document is cancelled, there are two (for the moment) possible explanations. Manually cancelled by the author and automatically cancelled by the eleg service because the wrong person was signing.
    , documentsharing25                :: DocumentSharing
    , documentrejectioninfo25          :: Maybe (MinutesTime, SignatoryLinkID, BS.ByteString)
    , documenttags25                   :: [DocumentTag]
    , documentservice25                :: Maybe ServiceID
    , documentattachments25            :: [DocumentID]
    , documentoriginalcompany25        :: Maybe CompanyID
    , documentrecordstatus25           :: DocumentRecordStatus
    , documentquarantineexpiry25       :: Maybe MinutesTime  -- the time when any quarantine will end (included as a separate field to record status for easy indexing)
    } deriving Typeable

-- migration for author attachments
data Document26 = Document26
    { documentid26                     :: DocumentID
    , documenttitle26                  :: BS.ByteString
    , documentsignatorylinks26         :: [SignatoryLink]
    , documentfiles26                  :: [File]
    , documentsealedfiles26            :: [File]
    , documentstatus26                 :: DocumentStatus
    , documenttype26                   :: DocumentType
    , documentfunctionality26          :: DocumentFunctionality
    , documentctime26                  :: MinutesTime
    , documentmtime26                  :: MinutesTime
    , documentdaystosign26             :: Maybe Int
    , documenttimeouttime26            :: Maybe TimeoutTime
    , documentinvitetime26             :: Maybe SignInfo
    , documentlog26                    :: [DocumentLogEntry]      -- to be made into plain text
    , documentinvitetext26             :: BS.ByteString
    , documenttrustweaverreference26   :: Maybe BS.ByteString
    , documentallowedidtypes26         :: [IdentificationType]
    , documentcsvupload26              :: Maybe CSVUpload
    , documentcancelationreason26      :: Maybe CancelationReason -- When a document is cancelled, there are two (for the moment) possible explanations. Manually cancelled by the author and automatically cancelled by the eleg service because the wrong person was signing.
    , documentsharing26                :: DocumentSharing
    , documentrejectioninfo26          :: Maybe (MinutesTime, SignatoryLinkID, BS.ByteString)
    , documenttags26                   :: [DocumentTag]
    , documentservice26                :: Maybe ServiceID
    , documentattachments26            :: [DocumentID] -- this needs to go away in next migration
    , documentoriginalcompany26        :: Maybe CompanyID
    , documentrecordstatus26           :: DocumentRecordStatus
    , documentquarantineexpiry26       :: Maybe MinutesTime  -- the time when any quarantine will end (included as a separate field to record status for easy indexing)
    , documentauthorattachments26      :: [AuthorAttachment]
    , documentsignatoryattachments26   :: [SignatoryAttachment]
    }  deriving Typeable

data Document27 = Document27
    { documentid27                     :: DocumentID
    , documenttitle27                  :: BS.ByteString
    , documentsignatorylinks27         :: [SignatoryLink]
    , documentfiles27                  :: [File]
    , documentsealedfiles27            :: [File]
    , documentstatus27                 :: DocumentStatus
    , documenttype27                   :: DocumentType
    , documentfunctionality27          :: DocumentFunctionality
    , documentctime27                  :: MinutesTime
    , documentmtime27                  :: MinutesTime
    , documentdaystosign27             :: Maybe Int
    , documenttimeouttime27            :: Maybe TimeoutTime
    , documentinvitetime27             :: Maybe SignInfo
    , documentlog27                    :: [DocumentLogEntry]      -- to be made into plain text
    , documentinvitetext27             :: BS.ByteString
    , documenttrustweaverreference27   :: Maybe BS.ByteString
    , documentallowedidtypes27         :: [IdentificationType]
    , documentcsvupload27              :: Maybe CSVUpload
    , documentcancelationreason27      :: Maybe CancelationReason -- When a document is cancelled, there are two (for the moment) possible explanations. Manually cancelled by the author and automatically cancelled by the eleg service because the wrong person was signing.
    , documentsharing27                :: DocumentSharing
    , documentrejectioninfo27          :: Maybe (MinutesTime, SignatoryLinkID, BS.ByteString)
    , documenttags27                   :: [DocumentTag]
    , documentservice27                :: Maybe ServiceID
    , documentattachments27            :: [DocumentID] -- this needs to go away in next migration
    , documentoriginalcompany27        :: Maybe CompanyID
    , documentrecordstatus27           :: DocumentRecordStatus
    , documentquarantineexpiry27       :: Maybe MinutesTime  -- the time when any quarantine will end (included as a separate field to record status for easy indexing)
    , documentauthorattachments27      :: [AuthorAttachment]
    , documentsignatoryattachments27   :: [SignatoryAttachment]
    , documentui27                     :: DocumentUI
    } deriving Typeable

data Document28 = Document28
    { documentid28                     :: DocumentID
    , documenttitle28                  :: BS.ByteString
    , documentsignatorylinks28         :: [SignatoryLink]
    , documentfiles28                  :: [File]
    , documentsealedfiles28            :: [File]
    , documentstatus28                 :: DocumentStatus
    , documenttype28                   :: DocumentType
    , documentfunctionality28          :: DocumentFunctionality
    , documentctime28                  :: MinutesTime
    , documentmtime28                  :: MinutesTime
    , documentdaystosign28             :: Maybe Int
    , documenttimeouttime28            :: Maybe TimeoutTime
    , documentinvitetime28             :: Maybe SignInfo
    , documentlog28                    :: [DocumentLogEntry]      -- to be made into plain text
    , documentinvitetext28             :: BS.ByteString
    , documenttrustweaverreference28   :: Maybe BS.ByteString
    , documentallowedidtypes28         :: [IdentificationType]
    , documentcsvupload28              :: Maybe CSVUpload
    , documentcancelationreason28      :: Maybe CancelationReason -- When a document is cancelled, there are two (for the moment) possible explanations. Manually cancelled by the author and automatically cancelled by the eleg service because the wrong person was signing.
    , documentsharing28                :: DocumentSharing
    , documentrejectioninfo28          :: Maybe (MinutesTime, SignatoryLinkID, BS.ByteString)
    , documenttags28                   :: [DocumentTag]
    , documentservice28                :: Maybe ServiceID
    , documentattachments28            :: [DocumentID] -- this needs to go away in next migration
    , documentoriginalcompany28        :: Maybe CompanyID
    , documentdeleted28                :: Bool -- set to true when doc is deleted - the other fields will be cleared too, so it is really truely deleting, it's just we want to avoid re-using the docid.
    , documentauthorattachments28      :: [AuthorAttachment]
    , documentsignatoryattachments28   :: [SignatoryAttachment]
    , documentui28                     :: DocumentUI
    } deriving Typeable

data Document29 = Document29
    { documentid29                     :: DocumentID
    , documenttitle29                  :: BS.ByteString
    , documentsignatorylinks29         :: [SignatoryLink]
    , documentfiles29                  :: [File]
    , documentsealedfiles29            :: [File]
    , documentstatus29                 :: DocumentStatus
    , documenttype29                   :: DocumentType
    , documentfunctionality29          :: DocumentFunctionality
    , documentctime29                  :: MinutesTime
    , documentmtime29                  :: MinutesTime
    , documentdaystosign29             :: Maybe Int
    , documenttimeouttime29            :: Maybe TimeoutTime
    , documentinvitetime29             :: Maybe SignInfo
    , documentlog29                    :: [DocumentLogEntry]      -- to be made into plain text
    , documentinvitetext29             :: BS.ByteString
    , documenttrustweaverreference29   :: Maybe BS.ByteString
    , documentallowedidtypes29         :: [IdentificationType]
    , documentcsvupload29              :: Maybe CSVUpload
    , documentcancelationreason29      :: Maybe CancelationReason -- When a document is cancelled, there are two (for the moment) possible explanations. Manually cancelled by the author and automatically cancelled by the eleg service because the wrong person was signing.
    , documentsharing29                :: DocumentSharing
    , documentrejectioninfo29          :: Maybe (MinutesTime, SignatoryLinkID, BS.ByteString)
    , documenttags29                   :: [DocumentTag]
    , documentservice29                :: Maybe ServiceID
    , documentattachments29            :: [DocumentID] -- this needs to go away in next migration
    , documentdeleted29                :: Bool -- set to true when doc is deleted - the other fields will be cleared too, so it is really truely deleting, it's just we want to avoid re-using the docid.
    , documentauthorattachments29      :: [AuthorAttachment]
    , documentsignatoryattachments29   :: [SignatoryAttachment]
    , documentui29                     :: DocumentUI
    } deriving Typeable

data Document30 = Document30
    { documentid30                     :: DocumentID
    , documenttitle30                  :: BS.ByteString
    , documentsignatorylinks30         :: [SignatoryLink]
    , documentfiles30                  :: [File]
    , documentsealedfiles30            :: [File]
    , documentstatus30                 :: DocumentStatus
    , documenttype30                   :: DocumentType
    , documentfunctionality30          :: DocumentFunctionality
    , documentctime30                  :: MinutesTime
    , documentmtime30                  :: MinutesTime
    , documentdaystosign30             :: Maybe Int
    , documenttimeouttime30            :: Maybe TimeoutTime
    , documentinvitetime30             :: Maybe SignInfo
    , documentlog30                    :: [DocumentLogEntry]      -- to be made into plain text
    , documentinvitetext30             :: BS.ByteString
    , documenttrustweaverreference30   :: Maybe BS.ByteString
    , documentallowedidtypes30         :: [IdentificationType]
    , documentcsvupload30              :: Maybe CSVUpload
    , documentcancelationreason30      :: Maybe CancelationReason -- When a document is cancelled, there are two (for the moment) possible explanations. Manually cancelled by the author and automatically cancelled by the eleg service because the wrong person was signing.
    , documentsharing30                :: DocumentSharing
    , documentrejectioninfo30          :: Maybe (MinutesTime, SignatoryLinkID, BS.ByteString)
    , documenttags30                   :: [DocumentTag]
    , documentservice30                :: Maybe ServiceID
    , documentattachments30            :: [DocumentID] -- this needs to go away in next migration
    , documentdeleted30                :: Bool -- set to true when doc is deleted - the other fields will be cleared too, so it is really truely deleting, it's just we want to avoid re-using the docid.
    , documentauthorattachments30      :: [AuthorAttachment]
    , documentsignatoryattachments30   :: [SignatoryAttachment]
    , documentui30                     :: DocumentUI
    , documentregion30                 :: Region
    } deriving Typeable

data Document = Document
    { documentid                     :: DocumentID
    , documenttitle                  :: BS.ByteString
    , documentsignatorylinks         :: [SignatoryLink]
    , documentfiles                  :: [FileID]
    , documentsealedfiles            :: [FileID]
    , documentstatus                 :: DocumentStatus
    , documenttype                   :: DocumentType
    , documentfunctionality          :: DocumentFunctionality
    , documentctime                  :: MinutesTime
    , documentmtime                  :: MinutesTime
    , documentdaystosign             :: Maybe Int
    , documenttimeouttime            :: Maybe TimeoutTime
    , documentinvitetime             :: Maybe SignInfo
    , documentlog                    :: [DocumentLogEntry]      -- to be made into plain text
    , documentinvitetext             :: BS.ByteString
    , documentallowedidtypes         :: [IdentificationType]
    , documentcsvupload              :: Maybe CSVUpload
    , documentcancelationreason      :: Maybe CancelationReason -- When a document is cancelled, there are two (for the moment) possible explanations. Manually cancelled by the author and automatically cancelled by the eleg service because the wrong person was signing.
    , documentsharing                :: DocumentSharing
    , documentrejectioninfo          :: Maybe (MinutesTime, SignatoryLinkID, BS.ByteString)
    , documenttags                   :: [DocumentTag]
    , documentservice                :: Maybe ServiceID
    , documentdeleted                :: Bool -- set to true when doc is deleted - the other fields will be cleared too, so it is really truely deleting, it's just we want to avoid re-using the docid.
    , documentauthorattachments      :: [AuthorAttachment]
    , documentsignatoryattachments   :: [SignatoryAttachment]
    , documentui                     :: DocumentUI
    , documentregion                 :: Region
    }

instance HasLocale Document where
  getLocale = mkLocaleFromRegion . documentregion

data CancelationReason =  ManualCancel
                        -- The data returned by ELeg server
                        --                 msg                    fn            ln            num
                        | ELegDataMismatch String SignatoryLinkID BS.ByteString BS.ByteString BS.ByteString
    deriving (Eq, Ord, Typeable, Data)


{- | Watch out. This instance is a bit special. It has to be
   "Document" - as this is what database uses as table name.  Simple
   deriving clause will create a "MyApp.MyModule.Document"!  -}

instance Typeable Document where typeOf _ = mkTypeOf "Document"

data CSVUpload = CSVUpload
    { csvtitle :: BS.ByteString
    , csvcontents  :: [[BS.ByteString]]
    , csvsignatoryindex :: Int
    }
    deriving (Eq, Ord, Typeable)


-- for Author Attachment and Signatory Attachments, obviously -EN
data AuthorAttachment0 = AuthorAttachment0 { authorattachmentfile0 :: File }
                      deriving (Eq, Ord, Typeable)

instance Version AuthorAttachment0

data AuthorAttachment = AuthorAttachment { authorattachmentfile :: FileID }
                      deriving (Eq, Ord, Typeable)

instance Version AuthorAttachment where
    mode = extension 1 (Proxy :: Proxy AuthorAttachment0)

instance Migrate AuthorAttachment0 AuthorAttachment where
    migrate (AuthorAttachment0 
             { authorattachmentfile0 
             }) = AuthorAttachment 
                { authorattachmentfile = unsafePerformIO $ update $ PutFileUnchecked authorattachmentfile0
                }



data SignatoryAttachment0 = SignatoryAttachment0 { signatoryattachmentfile0            :: Maybe File
                                                 , signatoryattachmentemail0           :: BS.ByteString
                                                 , signatoryattachmentname0            :: BS.ByteString
                                                 , signatoryattachmentdescription0     :: BS.ByteString
                                                 }
                         deriving (Eq, Ord, Typeable)


instance Version SignatoryAttachment0

data SignatoryAttachment = SignatoryAttachment { signatoryattachmentfile            :: Maybe FileID
                                               , signatoryattachmentemail           :: BS.ByteString
                                               , signatoryattachmentname            :: BS.ByteString
                                               , signatoryattachmentdescription     :: BS.ByteString
                                               }
                         deriving (Eq, Ord, Typeable)

instance Version SignatoryAttachment where
    mode = extension 1 (Proxy :: Proxy SignatoryAttachment0)

instance Migrate SignatoryAttachment0 SignatoryAttachment where
    migrate (SignatoryAttachment0 
             { signatoryattachmentfile0
             , signatoryattachmentemail0
             , signatoryattachmentname0
             , signatoryattachmentdescription0
             }) = SignatoryAttachment 
                { signatoryattachmentfile         = maybe Nothing (Just . unsafePerformIO . update . PutFileUnchecked) signatoryattachmentfile0
                , signatoryattachmentemail        = signatoryattachmentemail0
                , signatoryattachmentname         = signatoryattachmentname0
                , signatoryattachmentdescription  = signatoryattachmentdescription0
                }

$(deriveSerialize ''AuthorAttachment0)
$(deriveSerialize ''SignatoryAttachment)
$(deriveSerialize ''SignatoryAttachment0)
$(deriveSerialize ''AuthorAttachment)


instance Eq Document where
    a == b = documentid a == documentid b

instance Ord Document where
    compare a b | documentid a == documentid b = EQ
                | otherwise = compare (documentmtime b,documenttitle a,documentid a)
                                      (documentmtime a,documenttitle b,documentid b)
                              -- see above: we use reverse time here!

instance Show SignatoryLinkID where
    showsPrec prec (SignatoryLinkID x) = showsPrec prec x


deriving instance Show Document
deriving instance Show DocumentStatus
deriving instance Show DocumentType
deriving instance Show DocumentProcess
deriving instance Show DocumentFunctionality
deriving instance Show CSVUpload
deriving instance Show ChargeMode
deriving instance Show DocumentSharing
deriving instance Show DocumentTag
deriving instance Show DocumentUI
deriving instance Show Author

deriving instance Show DocStats

deriving instance Show FieldDefinition
deriving instance Show FieldPlacement
deriving instance Show SignatoryField
deriving instance Show FieldType

deriving instance Show AuthorAttachment
deriving instance Show SignatoryAttachment

instance Show TimeoutTime where
    showsPrec prec = showsPrec prec . unTimeoutTime

deriving instance Show SignatoryLink
deriving instance Show SignatoryLink1
deriving instance Show SignatoryLink2
deriving instance Show SignInfo
deriving instance Show SignInfo0
deriving instance Show SignatoryDetails
deriving instance Show SignatoryDetails0
deriving instance Show DocumentHistoryEntry
deriving instance Show IdentificationType
deriving instance Show CancelationReason
deriving instance Show SignatureProvider
deriving instance Show SignatureInfo0
deriving instance Show SignatureInfo

instance Show Signatory where
    showsPrec prec (Signatory userid) = showsPrec prec userid

instance Show Supervisor where
  showsPrec prec (Supervisor userid) = showsPrec prec userid

instance Show DocumentID where
    showsPrec prec (DocumentID val) =
         showsPrec prec val

instance Read DocumentID where
    readsPrec prec = let makeDocumentID (i,v) = (DocumentID i,v)
                     in map makeDocumentID . readsPrec prec

instance Read SignatoryLinkID where
    readsPrec prec = let make (i,v) = (SignatoryLinkID i,v)
                     in map make . readsPrec prec

instance FromReqURI DocumentID where
    fromReqURI = readM

instance FromReqURI SignatoryLinkID where
    fromReqURI = readM

$(deriveSerialize ''FieldDefinition0)
instance Version FieldDefinition0

$(deriveSerialize ''FieldDefinition)
instance Version FieldDefinition where
    mode = extension 1 (Proxy :: Proxy FieldDefinition0)

instance Migrate FieldDefinition0 FieldDefinition where
    migrate (FieldDefinition0
             { fieldlabel0
             , fieldvalue0
             , fieldplacements0
             }) = FieldDefinition
                { fieldlabel = fieldlabel0
                , fieldvalue = fieldvalue0
                , fieldplacements = fieldplacements0
                , fieldfilledbyauthor = False
                }

$(deriveSerialize ''FieldPlacement)
instance Version FieldPlacement

$(deriveSerialize ''SignInfo0)
instance Version SignInfo0

$(deriveSerialize ''SignInfo)
instance Version SignInfo where
    mode = extension 1 (Proxy :: Proxy SignInfo0)

$(deriveSerialize ''SignOrder)
instance Version SignOrder

$(deriveSerialize ''IdentificationType)
instance Version IdentificationType

$(deriveSerialize ''CancelationReason)
instance Version CancelationReason

$(deriveSerialize ''SignatureProvider)
instance Version SignatureProvider

$(deriveSerialize ''SignatureInfo0)
instance Version SignatureInfo0

$(deriveSerialize ''SignatureInfo)
instance Version SignatureInfo where
    mode = extension 1 (Proxy :: Proxy SignatureInfo0)

instance Migrate SignatureInfo0 SignatureInfo where
    migrate (SignatureInfo0
            { signatureinfotext0
            , signatureinfosignature0
            , signatureinfocertificate0
            , signatureinfoprovider0
            }) = SignatureInfo
            { signatureinfotext = signatureinfotext0
            , signatureinfosignature = signatureinfosignature0
            , signatureinfocertificate = signatureinfocertificate0
            , signatureinfoprovider = signatureinfoprovider0
            , signaturefstnameverified = False
            , signaturelstnameverified = False
            , signaturepersnumverified = False
            }

instance Migrate SignInfo0 SignInfo where
    migrate (SignInfo0
             { signtime0
             }) = SignInfo
                { signtime = signtime0
                , signipnumber = 0 -- mean unknown
                }

$(deriveSerialize ''SignatoryDetails0)
instance Version SignatoryDetails0

$(deriveSerialize ''SignatoryDetails1)
instance Version SignatoryDetails1 where
    mode = extension 1 (Proxy :: Proxy SignatoryDetails0)

$(deriveSerialize ''SignatoryDetails2)
instance Version SignatoryDetails2 where
    mode = extension 2 (Proxy :: Proxy SignatoryDetails1)

$(deriveSerialize ''SignatoryDetails3)
instance Version SignatoryDetails3 where
    mode = extension 3 (Proxy :: Proxy SignatoryDetails2)

$(deriveSerialize ''SignatoryDetails4)
instance Version SignatoryDetails4 where
    mode = extension 4 (Proxy :: Proxy SignatoryDetails3)

$(deriveSerialize ''SignatoryDetails5)
instance Version SignatoryDetails5 where
    mode = extension 5 (Proxy :: Proxy SignatoryDetails4)

$(deriveSerialize ''SignatoryDetails)
instance Version SignatoryDetails where
    mode = extension 6 (Proxy :: Proxy SignatoryDetails5)

$(deriveSerialize ''SignatoryField)
instance Version SignatoryField

$(deriveSerialize ''FieldType)
instance Version FieldType

$(deriveSerialize ''SignatoryLink1)
instance Version SignatoryLink1 where
    mode = extension 1 (Proxy :: Proxy ())

$(deriveSerialize ''SignatoryLink2)
instance Version SignatoryLink2 where
    mode = extension 2 (Proxy :: Proxy SignatoryLink1)

$(deriveSerialize ''SignatoryLink3)
instance Version SignatoryLink3 where
    mode = extension 3 (Proxy :: Proxy SignatoryLink2)

$(deriveSerialize ''SignatoryLink4)
instance Version SignatoryLink4 where
    mode = extension 4 (Proxy :: Proxy SignatoryLink3)

$(deriveSerialize ''SignatoryLink5)
instance Version SignatoryLink5 where
    mode = extension 5 (Proxy :: Proxy SignatoryLink4)

$(deriveSerialize ''SignatoryLink6)
instance Version SignatoryLink6 where
    mode = extension 6 (Proxy :: Proxy SignatoryLink5)

$(deriveSerialize ''SignatoryLink7)
instance Version SignatoryLink7 where
    mode = extension 7 (Proxy :: Proxy SignatoryLink6)

$(deriveSerialize ''SignatoryLink8)
instance Version SignatoryLink8 where
    mode = extension 8 (Proxy :: Proxy SignatoryLink7)

$(deriveSerialize ''SignatoryLink9)
instance Version SignatoryLink9 where
    mode = extension 9 (Proxy :: Proxy SignatoryLink8)

$(deriveSerialize ''SignatoryLink10)
instance Version SignatoryLink10 where
    mode = extension 10 (Proxy :: Proxy SignatoryLink9)

$(deriveSerialize ''SignatoryLink)
instance Version SignatoryLink where
    mode = extension 11 (Proxy :: Proxy SignatoryLink10)

instance Migrate SignatoryDetails0 SignatoryDetails1 where
    migrate (SignatoryDetails0
             { signatoryname00
             , signatorycompany00
             , signatorynumber00
             , signatoryemail00
             }) = SignatoryDetails1
                { signatoryname1 = signatoryname00
                , signatorycompany1 = signatorycompany00
                , signatorynumber1 = signatorynumber00
                , signatoryemail1 = signatoryemail00
                , signatorynameplacements1 = []
                , signatorycompanyplacements1 = []
                , signatoryemailplacements1 = []
                , signatorynumberplacements1 = []
                , signatoryotherfields1 = []
                }


instance Migrate SignatoryDetails1 SignatoryDetails2 where
    migrate (SignatoryDetails1
             {  signatoryname1
                , signatorycompany1
                , signatorynumber1
                , signatoryemail1
                , signatorynameplacements1
                , signatorycompanyplacements1
                , signatoryemailplacements1
                , signatorynumberplacements1
                , signatoryotherfields1
              }) = SignatoryDetails2
                { signatoryfstname2 =  signatoryname1
                , signatorysndname2 = BS.empty
                , signatorycompany2 = signatorycompany1
                , signatorynumber2 = signatorynumber1
                , signatoryemail2 = signatoryemail1
                , signatorynameplacements2 = signatorynameplacements1
                , signatorycompanyplacements2 = signatorycompanyplacements1
                , signatoryemailplacements2 = signatoryemailplacements1
                , signatorynumberplacements2 = signatorynumberplacements1
                , signatoryotherfields2 = signatoryotherfields1
                }


instance Migrate SignatoryDetails2 SignatoryDetails3 where
    migrate (SignatoryDetails2
             {  signatoryfstname2
                , signatorysndname2
                , signatorycompany2
                , signatorynumber2
                , signatoryemail2
                , signatorynameplacements2
                , signatorycompanyplacements2
                , signatoryemailplacements2
                , signatorynumberplacements2
                , signatoryotherfields2
                }) = SignatoryDetails3
                { signatoryfstname3 =  signatoryfstname2
                , signatorysndname3 = signatorysndname2
                , signatorycompany3 = signatorycompany2
                , signatorynumber3 = signatorynumber2
                , signatoryemail3 = signatoryemail2
                , signatoryfstnameplacements3 = signatorynameplacements2
                , signatorysndnameplacements3 = []
                , signatorycompanyplacements3 = signatorycompanyplacements2
                , signatoryemailplacements3 = signatoryemailplacements2
                , signatorynumberplacements3 = signatorynumberplacements2
                , signatoryotherfields3 = signatoryotherfields2
                }


instance Migrate SignatoryDetails3 SignatoryDetails4 where
    migrate (SignatoryDetails3
             {  signatoryfstname3
                , signatorysndname3
                , signatorycompany3
                , signatorynumber3
                , signatoryemail3
                , signatoryfstnameplacements3
                , signatorysndnameplacements3
                , signatorycompanyplacements3
                , signatoryemailplacements3
                , signatorynumberplacements3
                , signatoryotherfields3
                }) = SignatoryDetails4
                { signatoryfstname4 =  signatoryfstname3
                , signatorysndname4 = signatorysndname3
                , signatorycompany4 = signatorycompany3
                , signatorypersonalnumber4 = signatorynumber3
                , signatorycompanynumber4 = BS.empty
                , signatoryemail4 = signatoryemail3
                , signatoryfstnameplacements4 = signatoryfstnameplacements3
                , signatorysndnameplacements4 = signatorysndnameplacements3
                , signatorycompanyplacements4 = signatorycompanyplacements3
                , signatoryemailplacements4 = signatoryemailplacements3
                , signatorypersonalnumberplacements4 = signatorynumberplacements3
                , signatorycompanynumberplacements4 = []
                , signatoryotherfields4 = signatoryotherfields3
                }

instance Migrate SignatoryDetails4 SignatoryDetails5 where
    migrate (SignatoryDetails4
             {  signatoryfstname4
                , signatorysndname4
                , signatorycompany4
                , signatorypersonalnumber4
                , signatorycompanynumber4
                , signatoryemail4
                , signatoryfstnameplacements4
                , signatorysndnameplacements4
                , signatorycompanyplacements4
                , signatoryemailplacements4
                , signatorypersonalnumberplacements4
                , signatorycompanynumberplacements4
                , signatoryotherfields4
                }) = SignatoryDetails5
                { signatoryfstname5 = signatoryfstname4
                , signatorysndname5 = signatorysndname4
                , signatorycompany5 = signatorycompany4
                , signatorypersonalnumber5 = signatorypersonalnumber4
                , signatorycompanynumber5 = signatorycompanynumber4
                , signatoryemail5 = signatoryemail4
                , signatorysignorder5 = SignOrder 1
                , signatoryfstnameplacements5 = signatoryfstnameplacements4
                , signatorysndnameplacements5 = signatorysndnameplacements4
                , signatorycompanyplacements5 = signatorycompanyplacements4
                , signatoryemailplacements5 = signatoryemailplacements4
                , signatorypersonalnumberplacements5 = signatorypersonalnumberplacements4
                , signatorycompanynumberplacements5 = signatorycompanynumberplacements4
                , signatoryotherfields5 = signatoryotherfields4
                }

instance Migrate SignatoryDetails5 SignatoryDetails where
    migrate (SignatoryDetails5
             {  signatoryfstname5
                , signatorysndname5
                , signatorycompany5
                , signatorypersonalnumber5
                , signatorycompanynumber5
                , signatoryemail5
                , signatorysignorder5
                , signatoryfstnameplacements5
                , signatorysndnameplacements5
                , signatorycompanyplacements5
                , signatoryemailplacements5
                , signatorypersonalnumberplacements5
                , signatorycompanynumberplacements5
                , signatoryotherfields5
                }) = SignatoryDetails
                { signatorysignorder = signatorysignorder5
                , signatoryfields = fields
                }
      where
        fields = [
            SignatoryField {
                sfType = FirstNameFT
              , sfValue = signatoryfstname5
              , sfPlacements = signatoryfstnameplacements5
              }
          , SignatoryField {
                sfType = LastNameFT
              , sfValue = signatorysndname5
              , sfPlacements = signatorysndnameplacements5
              }
          , SignatoryField {
                sfType = CompanyFT
              , sfValue = signatorycompany5
              , sfPlacements = signatorycompanyplacements5
              }
          , SignatoryField {
                sfType = PersonalNumberFT
              , sfValue = signatorypersonalnumber5
              , sfPlacements = signatorypersonalnumberplacements5
              }
          , SignatoryField {
                sfType = CompanyNumberFT
              , sfValue = signatorycompanynumber5
              , sfPlacements = signatorycompanynumberplacements5
              }
          , SignatoryField {
                sfType = EmailFT
              , sfValue = signatoryemail5
              , sfPlacements = signatoryemailplacements5
              }
            ] ++ map toSF signatoryotherfields5
        toSF FieldDefinition{fieldlabel, fieldvalue, fieldplacements, fieldfilledbyauthor} = SignatoryField {
            sfType = CustomFT fieldlabel fieldfilledbyauthor
          , sfValue = fieldvalue
          , sfPlacements = fieldplacements
          }

instance Migrate () SignatoryLink1 where
  migrate _ = error "no migration to SignatoryLink1"

instance Migrate SignatoryLink1 SignatoryLink2 where
    migrate (SignatoryLink1
             { signatorylinkid1
             , signatorydetails1
             , maybesignatory1
             , maybesigninfo1
             , maybeseentime1
             }) = SignatoryLink2
                { signatorylinkid2 = signatorylinkid1
                , signatorydetails2 = signatorydetails1
                , maybesignatory2 = maybesignatory1
                , maybesigninfo2 = maybesigninfo1
                , maybeseentime2 = maybeseentime1
                , signatorymagichash2 = MagicHash $
                                       fromIntegral (unSignatoryLinkID signatorylinkid1) +
                                                        0xcde156781937458e37
                }


instance Migrate SignatoryLink2 SignatoryLink3 where
      migrate (SignatoryLink2
          { signatorylinkid2
          , signatorydetails2
          , signatorymagichash2
          , maybesignatory2
          , maybesigninfo2
          , maybeseentime2
          }) = SignatoryLink3
          { signatorylinkid3    = signatorylinkid2
          , signatorydetails3   = signatorydetails2
          , signatorymagichash3 = signatorymagichash2
          , maybesignatory3     = maybesignatory2
          , maybesigninfo3      = maybesigninfo2
          , maybeseeninfo3      = maybe Nothing (\t -> Just (SignInfo t 0)) maybeseentime2
          }


instance Migrate SignatoryLink3 SignatoryLink4 where
      migrate (SignatoryLink3
          { signatorylinkid3
          , signatorydetails3
          , signatorymagichash3
          , maybesignatory3
          , maybesigninfo3
          , maybeseeninfo3
          }) = SignatoryLink4
          { signatorylinkid4    = signatorylinkid3
          , signatorydetails4   = signatorydetails3
          , signatorymagichash4 = signatorymagichash3
          , maybesignatory4     = maybesignatory3
          , maybesigninfo4      = maybesigninfo3
          , maybeseeninfo4      = maybeseeninfo3
          , invitationdeliverystatus4 = Delivered
          }

instance Migrate SignatoryLink4 SignatoryLink5 where
    migrate (SignatoryLink4
             { signatorylinkid4
             , signatorydetails4
             , signatorymagichash4
             , maybesignatory4
             , maybesigninfo4
             , maybeseeninfo4
             , invitationdeliverystatus4
             }) = SignatoryLink5
             { signatorylinkid5 = signatorylinkid4
             , signatorydetails5 = signatorydetails4
             , signatorymagichash5 = signatorymagichash4
             , maybesignatory5 = maybesignatory4
             , maybesigninfo5 = maybesigninfo4
             , maybeseeninfo5 = maybeseeninfo4
             , invitationdeliverystatus5 = invitationdeliverystatus4
             , signatorysignatureinfo5 = Nothing
             }

instance Migrate SignatoryLink5 SignatoryLink6 where
    migrate (SignatoryLink5
             { signatorylinkid5
             , signatorydetails5
             , signatorymagichash5
             , maybesignatory5
             , maybesigninfo5
             , maybeseeninfo5
             , invitationdeliverystatus5
             , signatorysignatureinfo5
             }) = SignatoryLink6
             { signatorylinkid6 = signatorylinkid5
             , signatorydetails6 = signatorydetails5
             , signatorymagichash6 = signatorymagichash5
             , maybesignatory6 = fmap unSignatory maybesignatory5
             , maybesigninfo6 = maybesigninfo5
             , maybeseeninfo6 = maybeseeninfo5
             , invitationdeliverystatus6 = invitationdeliverystatus5
             , signatorysignatureinfo6 = signatorysignatureinfo5
             }

instance Migrate SignatoryLink6 SignatoryLink7 where
    migrate (SignatoryLink6
             { signatorylinkid6
             , signatorydetails6
             , signatorymagichash6
             , maybesignatory6
             , maybesigninfo6
             , maybeseeninfo6
             , invitationdeliverystatus6
             , signatorysignatureinfo6
             }) = SignatoryLink7
                { signatorylinkid7           = signatorylinkid6
                , signatorydetails7          = signatorydetails6
                , signatorymagichash7        = signatorymagichash6
                , maybesignatory7            = maybesignatory6
                , maybesigninfo7             = maybesigninfo6
                , maybeseeninfo7             = maybeseeninfo6
                , invitationdeliverystatus7  = invitationdeliverystatus6
                , signatorysignatureinfo7    = signatorysignatureinfo6
                , signatorylinkdeleted7      = False
                , signatoryroles7            = [SignatoryPartner]
                }

instance Migrate SignatoryLink7 SignatoryLink8 where
    migrate (SignatoryLink7
             { signatorylinkid7
             , signatorydetails7
             , signatorymagichash7
             , maybesignatory7
             , maybesigninfo7
             , maybeseeninfo7
             , invitationdeliverystatus7
             , signatorysignatureinfo7
             , signatorylinkdeleted7
             , signatoryroles7
             }) = SignatoryLink8
                { signatorylinkid8           = signatorylinkid7
                , signatorydetails8          = signatorydetails7
                , signatorymagichash8        = signatorymagichash7
                , maybesignatory8            = maybesignatory7
                , maybesigninfo8             = maybesigninfo7
                , maybeseeninfo8             = maybeseeninfo7
                , maybereadinvite8           = Nothing
                , invitationdeliverystatus8  = invitationdeliverystatus7
                , signatorysignatureinfo8    = signatorysignatureinfo7
                , signatorylinkdeleted8      = signatorylinkdeleted7
                , signatoryroles8            = signatoryroles7
                }

instance Migrate SignatoryLink8 SignatoryLink9 where
    migrate (SignatoryLink8
             { signatorylinkid8
             , signatorydetails8
             , signatorymagichash8
             , maybesignatory8
             , maybesigninfo8
             , maybeseeninfo8
             , maybereadinvite8
             , invitationdeliverystatus8
             , signatorysignatureinfo8
             , signatorylinkdeleted8
             , signatoryroles8
             }) = SignatoryLink9
                { signatorylinkid9           = signatorylinkid8
                , signatorydetails9          = signatorydetails8
                , signatorymagichash9        = signatorymagichash8
                , maybesignatory9            = maybesignatory8
                , maybesupervisor9           = Nothing
                , maybesigninfo9             = maybesigninfo8
                , maybeseeninfo9             = maybeseeninfo8
                , maybereadinvite9           = maybereadinvite8
                , invitationdeliverystatus9  = invitationdeliverystatus8
                , signatorysignatureinfo9    = signatorysignatureinfo8
                , signatorylinkdeleted9      = signatorylinkdeleted8
                , signatoryroles9            = signatoryroles8
                }

instance Migrate SignatoryLink9 SignatoryLink10 where
    migrate (SignatoryLink9
             { signatorylinkid9
             , signatorydetails9
             , signatorymagichash9
             , maybesignatory9
             , maybesupervisor9
             , maybesigninfo9
             , maybeseeninfo9
             , maybereadinvite9
             , invitationdeliverystatus9
             , signatorysignatureinfo9
             , signatorylinkdeleted9
             , signatoryroles9
             }) = SignatoryLink10
                { signatorylinkid10            = signatorylinkid9
                , signatorydetails10           = signatorydetails9
                , signatorymagichash10         = signatorymagichash9
                , maybesignatory10             = maybesignatory9
                , maybesupervisor10            = maybesupervisor9
                , maybesigninfo10              = maybesigninfo9
                , maybeseeninfo10              = maybeseeninfo9
                , maybereadinvite10            = maybereadinvite9
                , invitationdeliverystatus10   = invitationdeliverystatus9
                , signatorysignatureinfo10     = signatorysignatureinfo9
                , signatorylinkdeleted10       = signatorylinkdeleted9
                , signatorylinkreallydeleted10 = False
                , signatoryroles10             = signatoryroles9
                }

instance Migrate SignatoryLink10 SignatoryLink where
    migrate (SignatoryLink10
             { signatorylinkid10
             , signatorydetails10
             , signatorymagichash10
             , maybesignatory10
             , maybesupervisor10
             , maybesigninfo10
             , maybeseeninfo10
             , maybereadinvite10
             , invitationdeliverystatus10
             , signatorysignatureinfo10
             , signatorylinkdeleted10
             , signatorylinkreallydeleted10
             , signatoryroles10
             }) = SignatoryLink
                { signatorylinkid            = signatorylinkid10
                , signatorydetails           = signatorydetails10
                , signatorymagichash         = signatorymagichash10
                , maybesignatory             = maybesignatory10
                , maybesupervisor            = maybesupervisor10
                , maybecompany               = Nothing
                , maybesigninfo              = maybesigninfo10
                , maybeseeninfo              = maybeseeninfo10
                , maybereadinvite            = maybereadinvite10
                , invitationdeliverystatus   = invitationdeliverystatus10
                , signatorysignatureinfo     = signatorysignatureinfo10
                , signatorylinkdeleted       = signatorylinkdeleted10
                , signatorylinkreallydeleted = signatorylinkreallydeleted10
                , signatoryroles             = signatoryroles10
                }

$(deriveSerialize ''SignatoryLinkID)
instance Version SignatoryLinkID

$(deriveSerialize ''DocumentID)
instance Version DocumentID

$(deriveSerialize ''TimeoutTime)
instance Version TimeoutTime

$(deriveSerialize ''Author)
instance Version Author

$(deriveSerialize ''Signatory)
instance Version Signatory where

$(deriveSerialize ''Supervisor)
instance Version Supervisor where

$(deriveSerialize ''DocumentHistoryEntry0)
instance Version DocumentHistoryEntry0

$(deriveSerialize ''DocumentHistoryEntry)
instance Version DocumentHistoryEntry where
    mode = extension 1 (Proxy :: Proxy DocumentHistoryEntry0)

$(deriveSerialize ''CSVUpload)
instance Version CSVUpload




$(deriveSerialize ''Document23)
instance Version Document23 where
    mode = extension 23 (Proxy :: Proxy ())

$(deriveSerialize ''Document24)
instance Version Document24 where
    mode = extension 24 (Proxy :: Proxy Document23)

$(deriveSerialize ''Document25)
instance Version Document25 where
    mode = extension 25 (Proxy :: Proxy Document24)

$(deriveSerialize ''Document26)
instance Version Document26 where
    mode = extension 26 (Proxy :: Proxy Document25)

$(deriveSerialize ''Document27)
instance Version Document27 where
    mode = extension 27 (Proxy :: Proxy Document26)

$(deriveSerialize ''Document28)
instance Version Document28 where
    mode = extension 28 (Proxy :: Proxy Document27)

$(deriveSerialize ''Document29)
instance Version Document29 where
    mode = extension 29 (Proxy :: Proxy Document28)

$(deriveSerialize ''Document30)
instance Version Document30 where
    mode = extension 30 (Proxy :: Proxy Document29)

$(deriveSerialize ''Document)
instance Version Document where
    mode = extension 31 (Proxy :: Proxy Document30)


instance Migrate DocumentHistoryEntry0 DocumentHistoryEntry where
        migrate (DocumentHistoryCreated0 { dochisttime0 }) =
            DocumentHistoryCreated dochisttime0
        migrate (DocumentHistoryInvitationSent0 { dochisttime0
                                                , ipnumber0
                                                })
            = DocumentHistoryInvitationSent dochisttime0 ipnumber0 []


instance Migrate () Document23 where
    migrate () = error "No way to migrate to Document22 to Document23"

instance Migrate Document23 Document24 where
    migrate (Document23
             { documentid23
             , documenttitle23
             , documentsignatorylinks23
             , documentfiles23
             , documentsealedfiles23
             , documentstatus23
             , documenttype23
             , documentfunctionality23
             , documentctime23
             , documentmtime23
             , documentdaystosign23
             , documenttimeouttime23
             , documentinvitetime23
             , documentlog23
             , documentinvitetext23
             , documenttrustweaverreference23
             , documentallowedidtypes23
             , documentcsvupload23
             , documentcancelationreason23
             , documentsharing23
             , documentrejectioninfo23
             , documenttags23
             , documentservice23
             , documentattachments23
             }) = Document24
                { documentid24                     = documentid23
                , documenttitle24                  = documenttitle23
                , documentsignatorylinks24         = documentsignatorylinks23
                , documentfiles24                  = documentfiles23
                , documentsealedfiles24            = documentsealedfiles23
                , documentstatus24                 = documentstatus23
                , documenttype24                   = documenttype23
                , documentfunctionality24          = documentfunctionality23
                , documentctime24                  = documentctime23
                , documentmtime24                  = documentmtime23
                , documentdaystosign24             = documentdaystosign23
                , documenttimeouttime24            = documenttimeouttime23
                , documentinvitetime24             = documentinvitetime23
                , documentlog24                    = documentlog23
                , documentinvitetext24             = documentinvitetext23
                , documenttrustweaverreference24   = documenttrustweaverreference23
                , documentallowedidtypes24         = documentallowedidtypes23
                , documentcsvupload24              = documentcsvupload23
                , documentcancelationreason24      = documentcancelationreason23
                , documentsharing24                = documentsharing23
                , documentrejectioninfo24          = documentrejectioninfo23
                , documenttags24                   = documenttags23
                , documentservice24                = documentservice23
                , documentattachments24            = documentattachments23
                , documentoriginalcompany24        = Nothing
                }

instance Migrate Document24 Document25 where
    migrate (Document24
             { documentid24
             , documenttitle24
             , documentsignatorylinks24
             , documentfiles24
             , documentsealedfiles24
             , documentstatus24
             , documenttype24
             , documentfunctionality24
             , documentctime24
             , documentmtime24
             , documentdaystosign24
             , documenttimeouttime24
             , documentinvitetime24
             , documentlog24
             , documentinvitetext24
             , documenttrustweaverreference24
             , documentallowedidtypes24
             , documentcsvupload24
             , documentcancelationreason24
             , documentsharing24
             , documentrejectioninfo24
             , documenttags24
             , documentservice24
             , documentoriginalcompany24
             , documentattachments24
             }) = Document25
                { documentid25                     = documentid24
                , documenttitle25                  = documenttitle24
                , documentsignatorylinks25         = documentsignatorylinks24
                , documentfiles25                  = documentfiles24
                , documentsealedfiles25            = documentsealedfiles24
                , documentstatus25                 = documentstatus24
                , documenttype25                   = documenttype24
                , documentfunctionality25          = documentfunctionality24
                , documentctime25                  = documentctime24
                , documentmtime25                  = documentmtime24
                , documentdaystosign25             = documentdaystosign24
                , documenttimeouttime25            = documenttimeouttime24
                , documentinvitetime25             = documentinvitetime24
                , documentlog25                    = documentlog24
                , documentinvitetext25             = documentinvitetext24
                , documenttrustweaverreference25   = documenttrustweaverreference24
                , documentallowedidtypes25         = documentallowedidtypes24
                , documentcsvupload25              = documentcsvupload24
                , documentcancelationreason25      = documentcancelationreason24
                , documentsharing25                = documentsharing24
                , documentrejectioninfo25          = documentrejectioninfo24
                , documenttags25                   = documenttags24
                , documentservice25                = documentservice24
                , documentoriginalcompany25        = documentoriginalcompany24
                , documentrecordstatus25           = LiveDocument
                , documentquarantineexpiry25       = Nothing
                , documentattachments25            = documentattachments24
                }


instance Migrate Document25 Document26 where
    migrate (Document25
             { documentid25
             , documenttitle25
             , documentsignatorylinks25
             , documentfiles25
             , documentsealedfiles25
             , documentstatus25
             , documenttype25
             , documentfunctionality25
             , documentctime25
             , documentmtime25
             , documentdaystosign25
             , documenttimeouttime25
             , documentinvitetime25
             , documentlog25
             , documentinvitetext25
             , documenttrustweaverreference25
             , documentallowedidtypes25
             , documentcsvupload25
             , documentcancelationreason25
             , documentsharing25
             , documentrejectioninfo25
             , documenttags25
             , documentservice25
             , documentoriginalcompany25
             , documentattachments25
             , documentrecordstatus25
             , documentquarantineexpiry25
             }) = Document26
                { documentid26                     = documentid25
                , documenttitle26                  = documenttitle25
                , documentsignatorylinks26         = documentsignatorylinks25
                , documentfiles26                  = documentfiles25
                , documentsealedfiles26            = documentsealedfiles25
                , documentstatus26                 = documentstatus25
                , documenttype26                   = documenttype25
                , documentfunctionality26          = documentfunctionality25
                , documentctime26                  = documentctime25
                , documentmtime26                  = documentmtime25
                , documentdaystosign26             = documentdaystosign25
                , documenttimeouttime26            = documenttimeouttime25
                , documentinvitetime26             = documentinvitetime25
                , documentlog26                    = documentlog25
                , documentinvitetext26             = documentinvitetext25
                , documenttrustweaverreference26   = documenttrustweaverreference25
                , documentallowedidtypes26         = documentallowedidtypes25
                , documentcsvupload26              = documentcsvupload25
                , documentcancelationreason26      = documentcancelationreason25
                , documentsharing26                = documentsharing25
                , documentrejectioninfo26          = documentrejectioninfo25
                , documenttags26                   = documenttags25
                , documentservice26                = documentservice25
                , documentoriginalcompany26        = documentoriginalcompany25
                , documentattachments26            = documentattachments25
                , documentrecordstatus26           = documentrecordstatus25
                , documentquarantineexpiry26       = documentquarantineexpiry25
                , documentauthorattachments26      = []
                , documentsignatoryattachments26   = []
                }

instance Migrate Document26 Document27 where
    migrate ( Document26
                { documentid26                 
                , documenttitle26             
                , documentsignatorylinks26    
                , documentfiles26            
                , documentsealedfiles26    
                , documentstatus26       
                , documenttype26          
                , documentfunctionality26  
                , documentctime26         
                , documentmtime26         
                , documentdaystosign26     
                , documenttimeouttime26    
                , documentinvitetime26    
                , documentlog26           
                , documentinvitetext26       
                , documenttrustweaverreference26  
                , documentallowedidtypes26    
                , documentcsvupload26       
                , documentcancelationreason26  
                , documentsharing26        
                , documentrejectioninfo26    
                , documenttags26          
                , documentservice26           
                , documentoriginalcompany26    
                , documentattachments26       
                , documentrecordstatus26     
                , documentquarantineexpiry26   
                , documentauthorattachments26 
                , documentsignatoryattachments26  
                }) = Document27
                { documentid27                     = documentid26
                , documenttitle27                  = documenttitle26
                , documentsignatorylinks27         = documentsignatorylinks26
                , documentfiles27                  = documentfiles26
                , documentsealedfiles27            = documentsealedfiles26
                , documentstatus27                 = documentstatus26
                , documenttype27                   = documenttype26
                , documentfunctionality27          = documentfunctionality26
                , documentctime27                  = documentctime26
                , documentmtime27                  = documentmtime26
                , documentdaystosign27             = documentdaystosign26
                , documenttimeouttime27            = documenttimeouttime26
                , documentinvitetime27             = documentinvitetime26
                , documentlog27                    = documentlog26
                , documentinvitetext27             = documentinvitetext26
                , documenttrustweaverreference27   = documenttrustweaverreference26
                , documentallowedidtypes27         = documentallowedidtypes26
                , documentcsvupload27              = documentcsvupload26
                , documentcancelationreason27      = documentcancelationreason26
                , documentsharing27                = documentsharing26
                , documentrejectioninfo27          = documentrejectioninfo26
                , documenttags27                   = documenttags26
                , documentservice27                = documentservice26
                , documentoriginalcompany27        = documentoriginalcompany26
                , documentattachments27            = documentattachments26
                , documentrecordstatus27           = documentrecordstatus26
                , documentquarantineexpiry27       = documentquarantineexpiry26
                , documentauthorattachments27      = documentauthorattachments26
                , documentsignatoryattachments27   = documentsignatoryattachments26
                , documentui27                     = emptyDocumentUI
                }

instance Migrate Document27 Document28 where
    migrate ( Document27
                { documentid27                 
                , documenttitle27             
                , documentsignatorylinks27    
                , documentfiles27            
                , documentsealedfiles27    
                , documentstatus27       
                , documenttype27          
                , documentfunctionality27  
                , documentctime27         
                , documentmtime27         
                , documentdaystosign27     
                , documenttimeouttime27    
                , documentinvitetime27    
                , documentlog27           
                , documentinvitetext27       
                , documenttrustweaverreference27  
                , documentallowedidtypes27    
                , documentcsvupload27       
                , documentcancelationreason27  
                , documentsharing27        
                , documentrejectioninfo27    
                , documenttags27          
                , documentservice27           
                , documentoriginalcompany27    
                , documentattachments27       
                , documentrecordstatus27   
                , documentauthorattachments27 
                , documentsignatoryattachments27
                , documentui27  
                }) = Document28
                { documentid28                     = documentid27
                , documenttitle28                  = documenttitle27
                , documentsignatorylinks28         = documentsignatorylinks27
                , documentfiles28                  = documentfiles27
                , documentsealedfiles28            = documentsealedfiles27
                , documentstatus28                 = documentstatus27
                , documenttype28                   = documenttype27
                , documentfunctionality28          = documentfunctionality27
                , documentctime28                  = documentctime27
                , documentmtime28                  = documentmtime27
                , documentdaystosign28             = documentdaystosign27
                , documenttimeouttime28            = documenttimeouttime27
                , documentinvitetime28             = documentinvitetime27
                , documentlog28                    = documentlog27
                , documentinvitetext28             = documentinvitetext27
                , documenttrustweaverreference28   = documenttrustweaverreference27
                , documentallowedidtypes28         = documentallowedidtypes27
                , documentcsvupload28              = documentcsvupload27
                , documentcancelationreason28      = documentcancelationreason27
                , documentsharing28                = documentsharing27
                , documentrejectioninfo28          = documentrejectioninfo27
                , documenttags28                   = documenttags27
                , documentservice28                = documentservice27
                , documentoriginalcompany28        = documentoriginalcompany27
                , documentattachments28            = documentattachments27
                , documentdeleted28                = documentrecordstatus27 == DeletedDocument
                , documentauthorattachments28      = documentauthorattachments27
                , documentsignatoryattachments28   = documentsignatoryattachments27
                , documentui28                     = documentui27
                }

instance Migrate Document28 Document29 where
    migrate ( Document28
                { documentid28                 
                , documenttitle28             
                , documentsignatorylinks28    
                , documentfiles28            
                , documentsealedfiles28    
                , documentstatus28       
                , documenttype28          
                , documentfunctionality28  
                , documentctime28         
                , documentmtime28         
                , documentdaystosign28     
                , documenttimeouttime28    
                , documentinvitetime28    
                , documentlog28           
                , documentinvitetext28       
                , documenttrustweaverreference28  
                , documentallowedidtypes28    
                , documentcsvupload28       
                , documentcancelationreason28  
                , documentsharing28        
                , documentrejectioninfo28    
                , documenttags28          
                , documentservice28           
                , documentoriginalcompany28    
                , documentattachments28       
                , documentdeleted28   
                , documentauthorattachments28 
                , documentsignatoryattachments28
                , documentui28  
                }) = Document29
                { documentid29                     = documentid28
                , documenttitle29                  = documenttitle28
                , documentsignatorylinks29         = map setOriginalCompanyIfAuthor documentsignatorylinks28
                , documentfiles29                  = documentfiles28
                , documentsealedfiles29            = documentsealedfiles28
                , documentstatus29                 = documentstatus28
                , documenttype29                   = documenttype28
                , documentfunctionality29          = documentfunctionality28
                , documentctime29                  = documentctime28
                , documentmtime29                  = documentmtime28
                , documentdaystosign29             = documentdaystosign28
                , documenttimeouttime29            = documenttimeouttime28
                , documentinvitetime29             = documentinvitetime28
                , documentlog29                    = documentlog28
                , documentinvitetext29             = documentinvitetext28
                , documenttrustweaverreference29   = documenttrustweaverreference28
                , documentallowedidtypes29         = documentallowedidtypes28
                , documentcsvupload29              = documentcsvupload28
                , documentcancelationreason29      = documentcancelationreason28
                , documentsharing29                = documentsharing28
                , documentrejectioninfo29          = documentrejectioninfo28
                , documenttags29                   = documenttags28
                , documentservice29                = documentservice28
                , documentattachments29            = documentattachments28
                , documentdeleted29                = documentdeleted28
                , documentauthorattachments29      = documentauthorattachments28
                , documentsignatoryattachments29   = documentsignatoryattachments28
                , documentui29                     = documentui28
                }
                where
                  {- |
                      Instead of storing the company on the document we want to store
                      it on the individual signatory links.  So each signatory link
                      has a maybesignatory storing the user, and maybecompany storing
                      the company the user is acting for.
                  -}
                  setOriginalCompanyIfAuthor :: SignatoryLink -> SignatoryLink
                  setOriginalCompanyIfAuthor sl@SignatoryLink{signatoryroles} =
                    if SignatoryAuthor `elem` signatoryroles
                      then sl { maybecompany = documentoriginalcompany28 }
                      else sl

instance Migrate Document29 Document30 where
    migrate ( Document29
                { documentid29                 
                , documenttitle29             
                , documentsignatorylinks29    
                , documentfiles29            
                , documentsealedfiles29    
                , documentstatus29       
                , documenttype29          
                , documentfunctionality29  
                , documentctime29         
                , documentmtime29         
                , documentdaystosign29     
                , documenttimeouttime29    
                , documentinvitetime29    
                , documentlog29           
                , documentinvitetext29       
                , documenttrustweaverreference29
                , documentallowedidtypes29    
                , documentcsvupload29       
                , documentcancelationreason29  
                , documentsharing29        
                , documentrejectioninfo29    
                , documenttags29          
                , documentservice29    
                , documentattachments29
                , documentdeleted29   
                , documentauthorattachments29 
                , documentsignatoryattachments29
                , documentui29  
                }) = Document30
                { documentid30                     = documentid29
                , documenttitle30                  = documenttitle29
                , documentsignatorylinks30         = documentsignatorylinks29
                , documentfiles30                  = documentfiles29
                , documentsealedfiles30            = documentsealedfiles29
                , documentstatus30                 = documentstatus29
                , documenttype30                   = documenttype29
                , documentfunctionality30          = documentfunctionality29
                , documentctime30                  = documentctime29
                , documentmtime30                  = documentmtime29
                , documentdaystosign30             = documentdaystosign29
                , documenttimeouttime30            = documenttimeouttime29
                , documentinvitetime30             = documentinvitetime29
                , documentlog30                    = documentlog29
                , documentinvitetext30             = documentinvitetext29
                , documenttrustweaverreference30   = documenttrustweaverreference29
                , documentallowedidtypes30         = documentallowedidtypes29
                , documentcsvupload30              = documentcsvupload29
                , documentcancelationreason30      = documentcancelationreason29
                , documentsharing30                = documentsharing29
                , documentrejectioninfo30          = documentrejectioninfo29
                , documenttags30                   = documenttags29
                , documentservice30                = documentservice29
                , documentattachments30            = documentattachments29
                , documentdeleted30                = documentdeleted29
                , documentauthorattachments30      = documentauthorattachments29
                , documentsignatoryattachments30   = documentsignatoryattachments29
                , documentui30                     = documentui29
                , documentregion30                 = REGION_SE
                }

instance Migrate Document30 Document where
    migrate ( Document30
        { documentid30                     
        , documenttitle30                  
        , documentsignatorylinks30         
        , documentfiles30                  
        , documentsealedfiles30            
        , documentstatus30                 
        , documenttype30                   
        , documentfunctionality30          
        , documentctime30                  
        , documentmtime30                  
        , documentdaystosign30             
        , documenttimeouttime30            
        , documentinvitetime30             
        , documentlog30                    
        , documentinvitetext30             
        , documenttrustweaverreference30 = _ -- dropped     
        , documentallowedidtypes30         
        , documentcsvupload30              
        , documentcancelationreason30      
        , documentsharing30                
        , documentrejectioninfo30          
        , documenttags30                   
        , documentservice30                
        , documentattachments30 = _ -- dropped              
        , documentdeleted30                
        , documentauthorattachments30      
        , documentsignatoryattachments30   
        , documentui30                     
        , documentregion30                 
        }) = Document
        { documentid                     = documentid30
        , documenttitle                  = documenttitle30
        , documentsignatorylinks         = documentsignatorylinks30
        , documentfiles                  = map (unsafePerformIO . update . PutFileUnchecked) documentfiles30
        , documentsealedfiles            = map (unsafePerformIO . update . PutFileUnchecked) documentsealedfiles30
        , documentstatus                 = documentstatus30
        , documenttype                   = documenttype30
        , documentfunctionality          = documentfunctionality30
        , documentctime                  = documentctime30
        , documentmtime                  = documentmtime30
        , documentdaystosign             = documentdaystosign30
        , documenttimeouttime            = documenttimeouttime30
        , documentinvitetime             = documentinvitetime30
        , documentlog                    = documentlog30
        , documentinvitetext             = documentinvitetext30
        , documentallowedidtypes         = documentallowedidtypes30
        , documentcsvupload              = documentcsvupload30
        , documentcancelationreason      = documentcancelationreason30
        , documentsharing                = documentsharing30
        , documentrejectioninfo          = documentrejectioninfo30
        , documenttags                   = documenttags30
        , documentservice                = documentservice30
        , documentdeleted                = documentdeleted30
        , documentauthorattachments      = documentauthorattachments30
        , documentsignatoryattachments   = documentsignatoryattachments30
        , documentui                     = documentui30
        , documentregion                 = documentregion30
        }

$(deriveSerialize ''DocumentStatus)
instance Version DocumentStatus where

$(deriveSerialize ''DocumentProcess)
instance Version DocumentProcess where

$(deriveSerialize ''DocumentType0)
instance Version DocumentType0 where

instance Migrate DocumentType0 DocumentType where
    migrate Contract0 = Signable Contract
    migrate ContractTemplate0 = Template Contract
    migrate Offer0 = Signable Offer
    migrate OfferTemplate0 = Template Offer
    migrate Attachment0 = Attachment
    migrate AttachmentTemplate0 = AttachmentTemplate

$(deriveSerialize ''DocumentType)
instance Version DocumentType where
    mode = extension 1 (Proxy :: Proxy DocumentType0)

$(deriveSerialize ''DocumentRecordStatus)
instance Version DocumentRecordStatus where

$(deriveSerialize ''DocumentFunctionality)
instance Version DocumentFunctionality where

$(deriveSerialize ''ChargeMode)
instance Version ChargeMode where

$(deriveSerialize ''DocumentSharing)
instance Version DocumentSharing where

$(deriveSerialize ''DocumentTag)
instance Version DocumentTag where

$(deriveSerialize ''DocumentUI)
instance Version DocumentUI where


$(deriveSerialize ''DocStats)
instance Version DocStats where



type Documents = IxSet Document


instance Indexable Document where
  empty = 
    ixSet [ ixFun (\x -> [documentid x] :: [DocumentID])
            -- wait, wait, wait: the following is wrong, signatory link ids are valid only in
            -- the scope of a single document! FIXME
          , ixFun (\x -> map signatorylinkid (documentsignatorylinks x) :: [SignatoryLinkID])           
#if 0
          , ixFun (\x -> map fileid (documentfiles x
                                       ++ documentsealedfiles x
                                       ++ map authorattachmentfile (documentauthorattachments x)
                                       ++ [f | SignatoryAttachment{signatoryattachmentfile = Just f} <- (documentsignatoryattachments x)]) :: [FileID])
#endif          
          , ixFun $ ifDocumentNotDeleted (maybeToList . documenttimeouttime)
          , ixFun $ ifDocumentNotDeleted (\x -> [documenttype x] :: [DocumentType])
          , ixFun $ ifDocumentNotDeleted (\x -> documenttags x :: [DocumentTag])
          , ixFun $ ifDocumentNotDeleted (\x -> [documentservice x] :: [Maybe ServiceID])
          , ixFun $ ifDocumentNotDeleted (\x -> [documentstatus x] :: [DocumentStatus])
          
          , ixFun $ ifDocumentNotDeleted (\x ->
                      (map Signatory . catMaybes . map maybesignatory $ undeletedSigLinks x) :: [Signatory])
          , ixFun $ ifDocumentNotDeleted (\x ->
                      (catMaybes . map maybecompany $ undeletedSigLinks x) :: [CompanyID])
          , ixFun $ ifDocumentNotDeleted (\x ->
                      (catMaybes . map maybesignatory $ undeletedSigLinks x) :: [UserID])
          , ixFun $ ifDocumentNotDeleted (\x ->
                      (map Author . catMaybes . map maybesignatory .
                         filter (\sl -> (SignatoryAuthor `elem` signatoryroles sl)) $ undeletedSigLinks x) :: [Author])
          ]
          where
            ifDocumentNotDeleted :: (Document -> [a]) -> Document -> [a]
            ifDocumentNotDeleted f doc
              | documentdeleted doc = []
              | otherwise = f doc
            undeletedSigLinks doc =
              filter (not . signatorylinkreallydeleted) $ documentsignatorylinks doc

instance Component Documents where
  type Dependencies Documents = End
  initialValue = empty

$(deriveSerialize ''SignatoryRole)

-- stuff for converting to pgsql

$(bitfieldDeriveConvertible ''SignatoryRole)
$(enumDeriveConvertible ''SignatureProvider)
$(enumDeriveConvertible ''MailsDeliveryStatus)
$(newtypeDeriveConvertible ''SignOrder)
$(jsonableDeriveConvertible [t| [SignatoryField] |])
$(jsonableDeriveConvertible [t| [DocumentLogEntry] |])
$(enumDeriveConvertible ''DocumentFunctionality)
$(enumDeriveConvertible ''DocumentProcess)
$(jsonableDeriveConvertible [t| DocumentStatus |])
$(bitfieldDeriveConvertible ''IdentificationType)
$(newtypeDeriveConvertible ''DocumentID)
$(enumDeriveConvertible ''DocumentSharing)
$(newtypeDeriveConvertible ''SignatoryLinkID)
$(jsonableDeriveConvertible [t| [DocumentTag] |])
$(jsonableDeriveConvertible [t| CancelationReason |])
$(jsonableDeriveConvertible [t| [[BS.ByteString ]] |])
