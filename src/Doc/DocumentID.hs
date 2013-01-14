module Doc.DocumentID (
    DocumentID
  , unsafeDocumentID
  ) where

import Data.Binary
import Data.Int
import Happstack.Server

import DB.Derive
import Utils.Read

newtype DocumentID = DocumentID Int64
  deriving (Eq, Ord)
$(newtypeDeriveUnderlyingReadShow ''DocumentID)

instance FromReqURI DocumentID where
  fromReqURI = maybeRead

instance Binary DocumentID where
  put (DocumentID did) = put did
  get = fmap DocumentID get

unsafeDocumentID :: Int64 -> DocumentID
unsafeDocumentID = DocumentID

$(newtypeDeriveConvertible ''DocumentID)
