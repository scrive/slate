{-# LANGUAGE NoMonomorphismRestriction #-}
module Attachment.Model
  ( NewAttachment(..)
  , Attachment(..)
  , DeleteAttachments(..)
  , SetAttachmentTitle(..)
  , SetAttachmentsSharing(..)
  , GetAttachments(..)
  , AttachmentDomain(..)
  , AttachmentFilter(..)
  , AttachmentOrderBy(..)
  )
where

import Control.Monad.Catch
import Control.Monad.State.Class
import Data.ByteString (ByteString)

import Attachment.AttachmentID
import Crypto.RNG
import DB
import File.FileID
import File.Model
import KontraPrelude
import MinutesTime
import User.UserID
import Util.Actor

data Attachment = Attachment
  { attachmentid      :: AttachmentID
  , attachmenttitle   :: String
  , attachmentctime   :: UTCTime
  , attachmentmtime   :: UTCTime
  , attachmentfile    :: FileID
  , attachmentuser    :: UserID
  , attachmentshared  :: Bool
  , attachmentdeleted :: Bool
  }

sqlAttachmentResults :: (MonadState v m, SqlResult v) => m ()
sqlAttachmentResults = do
  sqlResult "id"
  sqlResult "title"
  sqlResult "ctime"
  sqlResult "mtime"
  sqlResult "file_id"
  sqlResult "user_id"
  sqlResult "shared"
  sqlResult "deleted"

fetchAttachment :: (AttachmentID, String, UTCTime, UTCTime, FileID, UserID, Bool, Bool) -> Attachment
fetchAttachment (aid, title, ctime, mtime, file_id, user_id, shared, deleted) = Attachment {
  attachmentid      = aid
, attachmenttitle   = title
, attachmentctime   = ctime
, attachmentmtime   = mtime
, attachmentfile    = file_id
, attachmentuser    = user_id
, attachmentshared  = shared
, attachmentdeleted = deleted
}

data NewAttachment = NewAttachment UserID String String (Binary ByteString) Actor
instance (MonadDB m, MonadThrow m) => DBUpdate m NewAttachment Attachment where
  update (NewAttachment uid title filename filecontents actor) = do
    let ctime = actorTime actor
    fileid <- update $ NewFile filename filecontents
    runQuery_ . sqlInsert "attachments" $ do
      sqlSet "user_id" uid
      sqlSet "title" title
      sqlSet "ctime" ctime
      sqlSet "mtime" ctime
      sqlSet "shared" False
      sqlSet "deleted" False
      sqlSet "file_id" fileid
      sqlAttachmentResults
    fetchOne fetchAttachment

data DeleteAttachments = DeleteAttachments UserID [AttachmentID] Actor
instance (CryptoRNG m, MonadDB m) => DBUpdate m DeleteAttachments () where
  update (DeleteAttachments uid attids actor) = do
    let atime = actorTime actor
    runQuery_ . sqlUpdate "attachments" $ do
      sqlSet "mtime" atime
      sqlSet "deleted" True
      sqlWhereIn "id" attids
      sqlWhereEq "user_id" uid
      sqlWhereEq "deleted" False

data SetAttachmentTitle = SetAttachmentTitle AttachmentID String Actor
instance (CryptoRNG m, MonadDB m) => DBUpdate m SetAttachmentTitle () where
  update (SetAttachmentTitle attid title actor) = do
    let atime = actorTime actor
    runQuery_ . sqlUpdate "attachments" $ do
      sqlSet "mtime" atime
      sqlSet "title" title
      sqlWhereEq "id" attid

data AttachmentFilter
  = AttachmentFilterByString String             -- ^ Contains the string in title, list of people involved or anywhere
  | AttachmentFilterByID [AttachmentID]         -- ^ Attachments with IDs on the list
  | AttachmentFilterByFileID [FileID]           -- ^ Attachments with IDs on the list

sqlWhereAttachmentFilter :: (MonadState v m, SqlWhere v) =>
                            AttachmentFilter -> m ()
sqlWhereAttachmentFilter (AttachmentFilterByString string) =
  sqlWhereILike "attachments.title" ("%" ++ string ++ "%")
sqlWhereAttachmentFilter (AttachmentFilterByID ids) =
  sqlWhereIn "attachments.id" ids
sqlWhereAttachmentFilter (AttachmentFilterByFileID fileids) =
  sqlWhereIn "attachments.file_id" fileids

data AttachmentDomain
  = AttachmentsOfAuthorDeleteValue UserID Bool   -- ^ Attachments of user, with deleted flag
  | AttachmentsSharedInUsersCompany UserID       -- ^ Attachments shared in the user company

-- | These are possible order by clauses that make documents sorted by.
data AttachmentOrderBy
  = AttachmentOrderByTitle       -- ^ Order by title, alphabetically, case insensitive
  | AttachmentOrderByMTime       -- ^ Order by modification time
  | AttachmentOrderByCTime       -- ^ Order by creation time

-- | GetAttachments is central switch for attachments list queries.
--
-- GetAttachments domains filters sorting pagination
--
-- * domains are connected with OR, so attachments falling into ANY of domains will be returned
-- * filters weed out attachments from domains, are connected with AND so a attachments must pass through ALL filters
-- * sortings returns attachments in order
-- * pagination is a place to put OFFSET and LIMIT values
--
-- GetAttachments returns attachments in proper order, no reverse is needed.
--
data GetAttachments = GetAttachments [AttachmentDomain] [AttachmentFilter] [AscDesc AttachmentOrderBy] (Int,Int)
instance MonadDB m => DBQuery m GetAttachments [Attachment] where
  query (GetAttachments domains filters orderbys (offset,limit)) = do
    runQuery_ . sqlSelect "attachments" $ do
      sqlAttachmentResults
      sqlWhereAny (map (sqlWhere . domainToSQLCommand) domains)
      mapM_ sqlWhereAttachmentFilter filters
      mapM_ (sqlOrderBy . orderToSQLCommand) orderbys
      sqlOffset offset
      sqlLimit limit
    fetchMany fetchAttachment
   where
    domainToSQLCommand (AttachmentsOfAuthorDeleteValue uid del) =
      "attachments.user_id =" <?> uid <+> "AND attachments.deleted =" <?> del
    domainToSQLCommand (AttachmentsSharedInUsersCompany uid) =
      "attachments.deleted = FALSE AND attachments.shared AND EXISTS (SELECT 1 FROM users, users AS users_2"
                                          <+> "WHERE attachments.user_id = users.id"
                                            <+> "AND users.company_id = users_2.company_id AND users_2.id =" <?> uid <+>")"
    orderToSQLCommand (Asc AttachmentOrderByTitle)  = "attachments.title ASC"
    orderToSQLCommand (Desc AttachmentOrderByTitle) = "attachments.title DESC"
    orderToSQLCommand (Asc AttachmentOrderByMTime)  = "attachments.mtime ASC"
    orderToSQLCommand (Desc AttachmentOrderByMTime) = "attachments.mtime DESC"
    orderToSQLCommand (Asc AttachmentOrderByCTime)  = "attachments.ctime ASC"
    orderToSQLCommand (Desc AttachmentOrderByCTime) = "attachments.ctime DESC"


data SetAttachmentsSharing = SetAttachmentsSharing UserID [AttachmentID] Bool
instance (MonadDB m) => DBUpdate m SetAttachmentsSharing () where
  update (SetAttachmentsSharing uid atts flag) = do
    runQuery_ . sqlUpdate "attachments" $ do
      sqlSet "shared" flag
      sqlWhereIn "id" atts
      sqlWhereEq "user_id" uid
