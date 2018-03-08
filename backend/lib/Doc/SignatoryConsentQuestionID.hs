module Doc.SignatoryConsentQuestionID (
    SignatoryConsentQuestionID
  , unsafeSignatoryConsentQuestionID
  , fromSignatoryConsentQuestionID
  ) where

import Data.Aeson (toJSON)
import Data.Binary as B
import Data.Data
import Data.Int
import Data.Unjson
import Database.PostgreSQL.PQTypes
import Happstack.Server

import Log.Identifier

newtype SignatoryConsentQuestionID = SignatoryConsentQuestionID Int64
  deriving (Eq, Ord, PQFormat, Typeable, Data)
deriving newtype instance Read SignatoryConsentQuestionID
deriving newtype instance Show SignatoryConsentQuestionID

instance FromReqURI SignatoryConsentQuestionID where
  fromReqURI = maybeRead

deriving newtype instance Binary SignatoryConsentQuestionID
deriving newtype instance FromSQL SignatoryConsentQuestionID
deriving newtype instance ToSQL SignatoryConsentQuestionID
deriving newtype instance Unjson SignatoryConsentQuestionID

instance Identifier SignatoryConsentQuestionID Int64 where
  idDefaultLabel _ = "signatory_consent_question_id"
  idValue (SignatoryConsentQuestionID k) = toJSON k

unsafeSignatoryConsentQuestionID :: Int64 -> SignatoryConsentQuestionID
unsafeSignatoryConsentQuestionID = SignatoryConsentQuestionID

fromSignatoryConsentQuestionID :: SignatoryConsentQuestionID -> Int64
fromSignatoryConsentQuestionID (SignatoryConsentQuestionID did) = did
