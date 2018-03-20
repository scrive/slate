module AppDBMigrations (
    kontraMigrations
  ) where

import Control.Monad.Catch
import Log

import Amazon.Migrations
import BrandedDomain.Migrations
import Chargeable.Migrations
import Company.Migrations
import Cron.Migrations
import DB
import Doc.Extending.Migrations
import Doc.Migrations
import Doc.Signing.Migrations
import Doc.SMSPin.Migrations
import EID.Authentication.Migrations
import EID.Nets.Migrations
import EID.Signature.Migrations
import FeatureFlags.Migrations
import Mails.FromKontra.Migrations
import Mails.Migrations
import Partner.Migrations
import SMS.FromKontra.Migrations
import SMS.Migrations
import ThirdPartyStats.Migrations
import User.APILog.Migrations
import User.History.Migrations
import User.Migrations

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
  , createKontraInfoForMailsTable
  , createKontraInfoForSMSesTable
  , removeXSMTPAttrsFromMailEvents
  , removeDataFromSmses
  , createDocumentExtendingConsumers
  , createDocumentExtendingJobs
  , signatoryLinkFieldsAddRadioGroupValues
  , voidTableAsyncEventQueue
  , addPlanhatJob
  , addEditableBySignatoryFlag
  , brandedDomainDropNoreplyEmail
  , createAmazonUploadConsumers
  , createAmazonUploadJobs
  , createJointTypeCompanyIDTimeIndexForChargeableItems
  , removeFindAndExtendDigitalSignaturesFromCronJobs
  , signatoryLinkFieldsAddCustomValidation
  , createFeatureFlags
  , createAPILogsTable
  , addSearchColumnsToDocument
  , addDocumentSearchUpdateJob
  , addPKToAsyncEventQueue
  , addPKToSignatorySMSPin
  , addPKToDocumentTags
  , addPKToUsersHistory
  , addAuthorUserIDToDocuments
  , addDocumentAuthorUserIDUpdateJob
  , createAPILogsTablePK
  , addPasswordAlgorithmVersionColumn
  , addPasswordAlgorithmUpgradeJob
  , addHidePnElogToSignatories
  , documentSigningJobsAddSignatureProvider
  , createNetsSignOrdersTable
  , featureFlagsAddNOAuthToSign
  , eidSignaturesAddProviderNetsNOBankID
  , addSignatoryIPToEIDSignatures
  , addSignatoryIPToEIDAuthentications
  , netsSignOrdersDropSSN
  , addUserTOTPKeyColumn
  , createSignatoryLinkConsentQuestionsTable
  , addConsentTitleToSignatoryLink
  , documentSigningJobsAddConsentResponses
  , featureFlagsAddSMSPinAuthToView
  , addSMSPinTypeToSMSMSPin
  , addSMSPinAuthAdjustmentsToEIDAuthentications
  ]
