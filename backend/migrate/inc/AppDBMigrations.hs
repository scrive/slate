module AppDBMigrations (
    kontraMigrations
  ) where

import Control.Monad.Catch
import Log

import Chargeable.Migrations
import Company.Migrations
import Cron.Migrations
import DB
import Doc.Migrations
import Doc.Signing.Migrations
import Partner.Migrations

-- Note: ALWAYS append new migrations TO THE END of this list.
-- Current version has migrations created after VII.2016.
kontraMigrations :: (MonadDB m, MonadThrow m, MonadLog m) => [Migration m]
kontraMigrations = [
    documentSigningJobsUseJson
  , addIsReceiptToDocument
  , createTablePartners
  , companiesAddPartnerID
  , createTablePartnerAdmins
  , addAllowsHighlightingToSignatories
  , createHighlightedPagesTable
  , normalizeCheckboxesSize
  , normalizeCheckboxesFSRel
  , companiesAddPadAppModeAndEArchiveEnabled
  , companiesAddPaymentPlan
  , removeRecurlySynchronizationFromCronJobs
  , removeFindAndDoPostDocumentClosedActions
  , createIndexesForChargeableItems
  , addInvoicingJob
  , addRequiredFlagToSignatoryAttachment
  , documentSigningJobsAddSignatoryAttachments
  ]
