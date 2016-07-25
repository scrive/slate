module Cron.Migrations (cronMigrations) where

import Control.Monad.Catch
import DB.Checks
import qualified Data.Text as T

import Cron.Tables
import DB
import KontraPrelude

cronMigrations :: (MonadDB m, MonadThrow m) => [Migration m]
cronMigrations = [
    createCronWorkersTable
  , createCronJobsTable
  , addNameToCronWorkers
  , addOldLogsRemovalToCronJobs
  , addMarkFilesForPurge
  , removeFindAndDoPostDocumentClosedActionsNew
  ]

removeFindAndDoPostDocumentClosedActionsNew :: (MonadDB m, MonadThrow m) => Migration m
removeFindAndDoPostDocumentClosedActionsNew = Migration {
    mgrTable = tableCronJobs
  , mgrFrom = 3
  , mgrDo = do
      n <- runSQL "DELETE FROM cron_jobs WHERE id = 'find_and_do_post_document_closed_actions_new'"
      when (n /= 1) $ do
        $unexpectedErrorM "Wrong amount of rows deleted"
  }

addMarkFilesForPurge :: MonadDB m => Migration m
addMarkFilesForPurge = Migration {
  mgrTable = tableCronJobs
, mgrFrom = 2
, mgrDo = do
  runSQL_ "UPDATE cron_jobs SET id = 'purge_orphan_file' WHERE id = 'amazon_deletion'"
  runSQL_ "INSERT INTO cron_jobs (id, run_at) VALUES ('mark_orphan_files_for_purge', to_timestamp(0))"
}

addOldLogsRemovalToCronJobs :: MonadDB m => Migration m
addOldLogsRemovalToCronJobs = Migration {
  mgrTable = tableCronJobs
, mgrFrom = 1
, mgrDo = runSQL_ "INSERT INTO cron_jobs (id, run_at) VALUES ('old_logs_removal', to_timestamp(0))"
}

addNameToCronWorkers :: MonadDB m => Migration m
addNameToCronWorkers = Migration {
  mgrTable = tableCronWorkers
, mgrFrom = 1
, mgrDo = do
  runSQL_ "ALTER TABLE cron_workers ADD COLUMN name TEXT NOT NULL DEFAULT 'cron_jobs'"
  runSQL_ "ALTER TABLE cron_workers ALTER COLUMN name DROP DEFAULT"
}

createCronWorkersTable :: MonadDB m => Migration m
createCronWorkersTable = Migration {
  mgrTable = tableCronWorkers
, mgrFrom = 0
, mgrDo = createTable True tblTable {
    tblName = "cron_workers"
  , tblVersion = 1
  , tblColumns = [
      tblColumn { colName = "id", colType = BigSerialT, colNullable = False }
    , tblColumn { colName = "last_activity", colType = TimestampWithZoneT, colNullable = False }
    ]
  , tblPrimaryKey = pkOnColumn "id"
  }
}

createCronJobsTable :: MonadDB m => Migration m
createCronJobsTable = Migration {
  mgrTable = tableCronJobs
, mgrFrom = 0
, mgrDo = do
  createTable True tblTable {
    tblName = "cron_jobs"
  , tblVersion = 1
  , tblColumns = [
      tblColumn { colName = "id", colType = TextT, colNullable = False }
    , tblColumn { colName = "run_at", colType = TimestampWithZoneT, colNullable = False }
    , tblColumn { colName = "finished_at", colType = TimestampWithZoneT }
    , tblColumn { colName = "reserved_by", colType = BigIntT }
    , tblColumn { colName = "attempts", colType = IntegerT, colNullable = False, colDefault = Just "0" }
    ]
  , tblPrimaryKey = pkOnColumn "id"
  , tblForeignKeys = [
      (fkOnColumn "reserved_by" "cron_workers" "id") {
        fkOnDelete = ForeignKeySetNull
      }
    ]
  }
  forM_ tasks $ \task -> do
    runSQL_ $ "INSERT INTO cron_jobs (id, run_at) VALUES (" <?> task <> ", to_timestamp(0))"
}
  where
    tasks :: [T.Text]
    tasks = [
        "amazon_deletion"
      , "amazon_upload"
      , "async_events_processing"
      , "clock_error_collection"
      , "document_automatic_reminders_evaluation"
      , "documents_purge"
      , "documents_archive_idle"
      , "email_change_requests_evaluation"
      , "find_and_do_post_document_closed_actions"
      , "find_and_do_post_document_closed_actions_new"
      , "find_and_extend_digital_signatures"
      , "find_and_timeout_documents"
      , "mail_events_processing"
      , "old_drafts_removal"
      , "password_reminders_evaluation"
      , "recurly_synchronization"
      , "sessions_evaluation"
      , "sms_events_processing"
      , "user_account_request_evaluation"
      ]
