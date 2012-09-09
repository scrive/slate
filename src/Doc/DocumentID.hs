module Doc.DocumentID (
    DocumentID
  , unsafeDocumentID
  ) where

import Data.Int
import Data.SafeCopy
import Happstack.Server

import DB.Derive
import Utils.Read

newtype DocumentID = DocumentID Int64
  deriving (Eq, Ord)
$(newtypeDeriveUnderlyingReadShow ''DocumentID)

$(deriveSafeCopy 0 'base ''DocumentID)

instance FromReqURI DocumentID where
  fromReqURI = maybeRead

unsafeDocumentID :: Int64 -> DocumentID
unsafeDocumentID = DocumentID

$(newtypeDeriveConvertible ''DocumentID)
