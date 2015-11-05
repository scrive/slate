module Purging.Files (
    MarkOrphanFilesForPurgeAfter(..)
  , purgeOrphanFile
  ) where

import Control.Monad.Catch
import Control.Monad.IO.Class
import Log
import qualified Data.Text as T

import Amazon
import DB
import File.Conditions
import File.Model
import KontraPrelude
import Log.Identifier

data MarkOrphanFilesForPurgeAfter = MarkOrphanFilesForPurgeAfter Int Interval
instance (MonadDB m, MonadThrow m) => DBUpdate m MarkOrphanFilesForPurgeAfter [FileID] where
  update (MarkOrphanFilesForPurgeAfter limit interval) = do
    -- Check if the database still looks similar to what the code below
    -- was written for.
    runSQL_ $ smconcat [
        "WITH file_constraints AS ("
      , "SELECT constraint_name AS name"
      , "  FROM information_schema.referential_constraints"
      , " WHERE unique_constraint_name = 'pk__files'"
      , ")"
      , "SELECT table_name::text, column_name::text"
      , "  FROM information_schema.key_column_usage"
      , " WHERE constraint_name IN (SELECT name FROM file_constraints)"
      ]
    refs :: [(T.Text, T.Text)] <- fetchMany id
    let expected_refs =
           [ ("attachments",           "file_id")
           , ("author_attachments",    "file_id")
           , ("main_files",            "file_id")
           , ("mail_attachments",      "file_id")
           , ("signatory_attachments", "file_id")
           , ("signatory_screenshots", "file_id")
           , ("signatory_link_fields", "value_file_id")
           ]

    when (sort expected_refs /= sort refs) $ do
      $unexpectedErrorM $ "PurgeFile: database layout has changed, update PurgeFile.expected_refs and check the code: " ++ show refs

    runSQL_ $ smconcat [
        "WITH files_to_purge AS ("
      , "SELECT id FROM files"
      , " WHERE purge_at IS NULL"
      , "   AND purged_time IS NULL"
      -- File is connected as a main file to a document that is
      -- available to somebody.
      , "EXCEPT ALL"
      , "SELECT f.id FROM files f"
      , "  JOIN main_files mf ON f.id = mf.file_id"
      , "  JOIN documents d ON mf.document_id = d.id"
      , " WHERE d.purged_time IS NULL"
      -- File is connected as a signatory attachment to a document
      -- that is available to somebody.
      , "EXCEPT ALL"
      , "SELECT f.id FROM files f"
      , "  JOIN signatory_attachments sa ON f.id = sa.file_id"
      , "  JOIN signatory_links sl ON sa.signatory_link_id = sl.id"
      , "  JOIN documents d ON sl.document_id = d.id"
      , " WHERE d.purged_time IS NULL"
      -- File is connected as an author attachment to a document
      -- that is available to somebody.
      , "EXCEPT ALL"
      , "SELECT f.id FROM files f"
      , "  JOIN author_attachments aa ON f.id = aa.file_id"
      , "  JOIN documents d ON aa.document_id = d.id"
      , " WHERE d.purged_time IS NULL"
      --  There is an email with this file as an attachment.
      , "EXCEPT ALL"
      , "SELECT f.id FROM files f"
      , "  JOIN mail_attachments ma ON f.id = ma.file_id"
      -- There is a screenshot useful for a non-deleted document.
      , "EXCEPT ALL"
      , "SELECT f.id FROM files f"
      , "  JOIN signatory_screenshots ss ON f.id = ss.file_id"
      , "  JOIN signatory_links sl ON ss.signatory_link_id = sl.id"
      , "  JOIN documents d ON sl.document_id = d.id"
      , " WHERE d.purged_time IS NULL"
      -- There is an attachment with this file referenced.
      , "EXCEPT ALL"
      , "SELECT f.id FROM files f"
      , "  JOIN attachments a ON f.id = a.file_id"
      , " WHERE NOT a.deleted"
      -- There is a signature (in signatory_link_fields) with this
      -- file referenced. On document purge reference is dropped.
      , "EXCEPT ALL"
      , "SELECT f.id FROM files f"
      , "  JOIN signatory_link_fields slf ON f.id = slf.value_file_id"
      , ")"
      , "UPDATE files"
      , "   SET purge_at = now() +" <?> interval
      , " WHERE id IN (SELECT id FROM files_to_purge LIMIT" <?> limit <> ")"
      , "RETURNING id"
      ]
    fetchMany runIdentity

purgeOrphanFile :: forall m. (MonadDB m, MonadThrow m, MonadLog m, MonadIO m, AmazonMonad m) => m Bool
purgeOrphanFile = do
  runQuery_ . sqlSelect "files" $ do
    sqlResult "id"
    sqlResult "amazon_bucket"
    sqlResult "amazon_url"
    sqlResult "content IS NULL"
    sqlWhereFileWasNotPurged
    sqlWhere "purge_at >= now()"
    sqlOrderBy "purge_at"
    sqlLimit 1
  fetchMaybe id >>= \case
    Nothing   -> return False
    Just file -> do
      purge file
      return True
  where
    purge :: (FileID, Maybe String, Maybe String, Bool) -> m ()
    purge (fid, mamazonBucket, mamazonUrl, isOnAmazon) = do
      purgedFromOtherSystems <- case (mamazonBucket, mamazonUrl, isOnAmazon) of
        (Just amazonBucket, Just amazonUrl, True) -> do
          conf <- getAmazonConfig
          deleteFile (mkAWSAction $ amazonConfig conf) amazonBucket amazonUrl
        _ -> return True
      if purgedFromOtherSystems
        then do
          dbUpdate $ PurgeFile fid
          commit
        else do
          logAttention "Purging file failed, it couldn't be removed from Amazon" $ object [
              identifier_ fid
            ]
          rollback
