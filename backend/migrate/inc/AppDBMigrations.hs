module AppDBMigrations (
    kontraMigrations
  ) where

import Control.Monad.Catch
import Log

import AccessControl.Migrations
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
import File.Migrations
import Folder.Migrations
import Mails.FromKontra.Migrations
import Mails.Migrations
import Partner.Migrations
import SMS.FromKontra.Migrations
import SMS.Migrations
import Theme.Migrations
import ThirdPartyStats.Migrations
import User.APILog.Migrations
import User.History.Migrations
import User.Migrations
import UserGroup.Migrations
import UserGroupAccounts.Migrations

-- Note: ALWAYS append new migrations TO THE END of this list.
-- Current version has migrations created after VII.2016.
kontraMigrations :: (MonadDB m, MonadThrow m, MonadLog m) => [Migration m]
kontraMigrations = [
    documentSigningJobsUseJson
  , addIsReceiptToDocument
  , createTablePartners
  , createTablePartnerAdmins
  , companiesAddPartnerID
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
  , netsSignOrdersAddProviderAndSSN
  , featureFlagsAddDKAuthToSign
  , optimiseUsersHistoryIndexes
  , companiesDropAllowSaveSafetyCopy
  , removeSearchTermsIndex
  , createAmazonURLFixConsumers
  , createAmazonURLFixJobs
  , createTableUserGroups
  , createTableUserGroupSettings
  , createTableUserGroupAddresses
  , createTableUserGroupUIs
  , chargeableItemsAddUserGroupID
  , featureFlagsAddUserGroupID
  , themeOwnershipAddUserGroupID
  , usersAddUserGroupID
  , companiesAddUserGroupID
  , partnersAddUserGroupID
  , createTableUserGroupInvoicings
  , addUserGroupMigrationJob
  , removeUserGroupMigrationJob
  , createJointTypeUserGroupIDTimeIndexForChargeableItems
  , dropFKCascadeForUserGroupID
  , companiesMakeUserGroupIDNotNull
  , themeOwnershipMakeUserGroupIDMandatory
  , usersMakeUserGroupIDNotNull
  , userGroupsAdjustIDSequence
  , dropCompanyIDForChargeableItems
  , featureFlagsDropCompanyID
  , themeOwnershipDropCompanyID
  , changeCompanyToUserGroupInCompanyInvites
  , usersDropCompanyID
  , companyUIsDropTable
  , companiesDropTable
  , usergroupsBumpVersionAfterDroppingCompanies
  , actuallyDeletePreviouslyDeletedUser
  , usergroupsAddDeleted
  , addAttachmentsPurgeJob
  , userGroupSettingsAddLegalText
  , userGroupSettingsSplitIdleDocTimeout
  , userGroupSettingsAddImmediateTrash
  , usersAddDataRetentionPolicy
  , featureFlagsAddStandardAuthAndFlagsForAdmin
  , featureFlagsAddEmailInvitation
  , featureFlagsAddFIAuthToView
  , addFIAuthChecksToEIDAuthentications
  , addShareableLinkHashToDocuments
  , featureFlagsAddEmailConfirmation
  , addAuthenticationToViewArchivedMethodToSignatories
  , addGeneratedAtToSMSPin
  , addAuthenticationKindToEIDAuthentications
  , featureFlagsAddShareableLinks
  , userGroupAddGINIdx
  , changeIsPartnerColumnToSignatoryRole
  , createSignatoryLinkMagicHashes
  , addTemporaryMagicHashesPurgeJob
  , dropAmazonURLFixJobs
  , dropAmazonURLFixConsumers
  , dropAmazonUploadJobs
  , dropAmazonUploadConsumers
  , removeAmazonUploadJob
  , addTemplateInfoToDocuments
  , createTableAccessControl
  , migratePartnerAdmins
  , dropPartnerAdmins
  , accesscontrolBumpVersionAfterDroppingPartnerAdmins
  , createFilePurgeConsumers
  , createFilePurgeJobs
  , dropContentAndPurgeAtFromFiles
  , removePurgeOrphanFileJob
  , addCanBeForwardedToSignatories
  , featureFlagsAddForwarding
  , createApiCallbackResults
  , addShowArrow
  , createTemporaryLoginTokensTable
  , addTemporaryLoginTokensPurgeJob
  , addMailConfirmationDeliveryStatusToSignatoryLinks
  , featureFlagsRemoveDefaultValuesFromColumns
  , addNotificationDeliveryMethodToSignatories
  , featureFlagsAddNotificationDeliveryMethod
  , addIndexForEfficientJoinToSignatoryLinkMagicHashes
  , addMonthlyInvoiceJob
  , createTableFolders
  , addFolderTargetColumn
  , addTargetChecks
  , addUserGroupHomeFolderID
  , usersAddHomeFolderID
  , addFolderRolesChecks
  , addFolderIDColumnToDocuments
  , addIndexOnShareableLinkHash
  ]
