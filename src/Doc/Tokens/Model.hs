module Doc.Tokens.Model (
    GetDocumentSessionToken(..)
  , AddDocumentSessionToken(..)
  ) where

import Control.Monad
import Context
import Crypto.RNG
import DB
import Doc.SignatoryLinkID
import KontraMonad
import MagicHash
import Session.Model

data GetDocumentSessionToken = GetDocumentSessionToken SignatoryLinkID
instance (KontraMonad m, MonadDB m) => DBQuery m GetDocumentSessionToken (Maybe MagicHash) where
  query (GetDocumentSessionToken slid) = do
    sid <- ctxsessionid `liftM` getContext
    getOne $ "SELECT token FROM document_session_tokens"
         <+> "WHERE session_id =" <?> sid <+> "AND signatory_link_id =" <?> slid

data AddDocumentSessionToken = AddDocumentSessionToken SignatoryLinkID MagicHash
instance (CryptoRNG m, KontraMonad m, MonadDB m) => DBUpdate m AddDocumentSessionToken () where
  update (AddDocumentSessionToken slid token) = do
    sid <- getNonTempSessionID
    kRun_ $ SQL "SELECT insert_document_session_token(?, ?, ?)" [
        toSql sid
      , toSql slid
      , toSql token
      ]
