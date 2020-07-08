module Doc.Tokens.Model
  ( CheckDocumentSession(..)
  , AddDocumentSession(..)
  ) where

import Control.Monad.Catch

import DB
import Doc.SignatoryLinkID
import KontraMonad
import Session.SessionID

data CheckDocumentSession = CheckDocumentSession SessionID SignatoryLinkID
instance (KontraMonad m, MonadDB m, MonadThrow m) => DBQuery m CheckDocumentSession Bool where
  dbQuery (CheckDocumentSession sid slid) = do
    runQuery_ . sqlSelect "document_session_tokens" $ do
      sqlWhereEq "session_id"        sid
      sqlWhereEq "signatory_link_id" slid
      sqlResult "TRUE"
    result <- fetchMaybe runIdentity
    return $ result == Just True

data AddDocumentSession = AddDocumentSession SessionID SignatoryLinkID
instance MonadDB m => DBUpdate m AddDocumentSession () where
  dbUpdate (AddDocumentSession sid slid) = do
    runQuery_ . sqlInsert "document_session_tokens" $ do
      sqlSet "session_id"        sid
      sqlSet "signatory_link_id" slid
      sqlOnConflictOnColumnsDoNothing ["session_id", "signatory_link_id"]
