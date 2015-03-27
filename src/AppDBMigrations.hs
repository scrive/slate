module AppDBMigrations (
    kontraMigrations
  ) where

import Control.Monad.Catch

import ActionQueue.Migrations
import Attachment.Migrations
import BrandedDomain.Migrations
import Chargeable.Migrations
import Company.Migrations
import CompanyAccounts.Migrations
import Cron.Migrations
import DB
import Doc.API.Callback.Migrations
import Doc.AutomaticReminder.Tables
import Doc.Migrations
import Doc.SMSPin.Tables
import EID.CGI.GRP.Transaction.Migrations
import EID.Signature.Migrations
import EvidenceLog.Migrations
import File.Migrations
import Mails.Migrations
import OAuth.Migrations
import Payments.Migrations
import Session.Migrations
import SMS.Migrations
import Theme.Migrations
import ThirdPartyStats.Migrations
import User.CallbackScheme.Migrations
import User.Migrations
import qualified Log

-- Note: ALWAYS append new migrations TO THE END of this list.
-- (mailerMigrations always stay at the end though. They are
-- disjoint with kontrakcja, so it can be done that way).
kontraMigrations :: (MonadDB m, MonadThrow m, Log.MonadLog m) => [Migration m]
kontraMigrations = [
    addRegionToUserSettings
  , removeSystemServer
  , addUserCustomFooter
  , addNameColumnInSignatoryAttachments
  , addCSVUploadDataFromDocumentToSignatoryLink
  , addColumnToRecordInternalInsertionOrder
  , addEmailBrandingToCompany
  , removeOldSignatoryLinkIDFromCancelationReason
  , addDocumentIdIndexOnSignatoryLinks
  , addSignatoryLinkIdToSignatoryAttachment
  , addTextColourToEmailBranding
  , addFileIdSequence
  , addIdSerialOnSignatoryLinks
  , addIdSerialOnDocuments
  , addIdSerialOnCompanies
  , addIdSerialOnUsers
  , addEmailDomainOnCompanies
  , addCompanyNameNumberOnUsers
  , updateDocumentStatusAfterRemovingAwaitingAuthor
  , moveDocumentTagsFromDocumentsTableToDocumentTagsTable
  , fixSignatoryLinksSwedishChars
  , setCascadeOnSignatoryAttachments
  , renumerateSignatoryLinkIDS
  , dropSLForeignKeyOnSignatoryAttachments
  , setSignatoryLinksPrimaryKeyToIDOnly
  , setSignatoryAttachmentsForeignKeyToSLIDOnly
  , dropDocumentIDColumntFromSignatoryAttachments
  , addCheckLowercaseEmailsUsers
  , moveSignatoryLinkFieldsToSeparateTable
  , migrateTempCredentialRemoveEmail -- for oauth
  , deprecateDocFunctionalityCol
  , removePreferedDesignMode
  , addDefaultEmptyStringsToSomeColumnsInCompaniesTable
  , addOCSPResponse
  , addCryptoColumnsToFilesTable
  , addForeignKeyToDocumentTags
  , addIsFree
  , moveAttachmentsFromDocumentsToAttachments
  , removeOldDocumentLog
  , splitIdentificationTypes
  , addSignRedirectURL
  , removeServiceIDFromCompanies
  , removeServiceIDFromDocuments
  , removeServiceIDFromUsers
  , removeDiskPathAndMakeNewColumnsNotNull
  , addApiCallbackUrlToDocument
  , removeSignatoryRoles
  , addSequenceOwnerToDocumentsId
  , addSequenceOwnerToSignatoryLinks
  , addBillingEndDateCache
  , setMandatoryExpirationTimeInDocument
  , removeRegionFromUsers
  , changeRegionToLang
  , removeCompanyIdFromSignatoryLinks
  , removeDeletedFromDocuments
  , attachUniqueContraintsToPaymentPlansColumns
  , removeSignatoryLinksInternalInsertOrder
  , addUnsavedDraftToDocument
  , expandEventsWithAffectedSignatoryAndTextMessage
  , addIPAddressMaskListToCompanies
  , dropTrustWeaverReferenceFromDocuments
  , dropCSVSignatoryIndexFromSignatoryLinks
  , moveRejectionInfoFromDocumentsToSignatoryLinks
  , dropRejectionInfoFromDocuments
  , moveAuthenticationMethodFromDocumentsToSignatoryLinks
  , dropAuthenticationMethodFromDocuments
  , moveCancelationReasonFromDocumentsToSignatoryLinks
  , dropCancelationReasonFromDocuments
  , addNewCompanyBrandingOptions
  , addSignviewBrandingOptions
  , dropCustomFooterFromUsers
  , dropMailFooterFromDocuments
  , moveDeliveryMethodFromDocumentsToSignatoryLinks
  , dropDeliveryMethodFromDocuments
  , addObjectVersionToDocuments
  , addShouldBeFilledBySenderColumnToSignatoryLinkFields
  , addCustomBrandingOptions
  , addAssociatedDomainToUsers
  , dropMobileFromUsers
  , removeExternalIDFromCompanies
  , addSealStatusToDocument
  , removeStatsTables
  , removeEmailDomainFromCompany
  , asyncEventQueueChangePrimaryKeyToBigSerial
  , removeProcessFromDocuments
  , moveCompanyUIsToSeparateTable
  , removeIsFree
  , setProperOwnerOnFilesIDSequence
  , moveBinaryDataForSignatoryScreenshotsToFilesTable
  , allUsersMustHaveCompany
  , paymentsPlansOnlyForCompanies
  , paymentsStatsOnlyForCompanies
  , migrateUsersDeletedTime
  , migrateSignatoryLinksDeletedTime
  , migrateSeparateDeliveryStatuses
  , removeCSVStuffFromDocuments
  , addPurgedTimeToFiles
  , migrateDocumentsAddPurgedTime
  , addRejectRedirectURL
  , createMainFilesTable
  , migrateDocumentsMoveFilesToMainFilesTable
  , removeDuplicateIndexFromPaymentPlans
  , removeDuplicateIndexFromAccessNewAccounts
  , removeDuplicateIndexFromPasswordReminders
  , removeDuplicateIndexFromEmailChangeRequests
  , removeDuplicateIndexFromUserAccountRequests
  , removeDuplicateIndexFromDocumentApiCallbacks
  , removeDuplicateIndexFromUsersCallbackScheme
  , removeDuplicateIndexFromCompanyUIs
  , addClientTimeNameToEvidenceLog
  , fixSignatureFieldsWithAnySize
  , migrateUsersUniqueIndexOnEmail
  , makeSealStatusNonNullInMainFiles
  , createDocumentAutomaticRemindersTable
  , migrateDocumentsAddDaysToRemind
  , normalizeCompanyInvites
  , addProbablyMissingIndexesOnAttachments
  , addPrimaryAndSecondaryColoursToCompanyUIs
  , evidenceLogFixColumns
  , signatoryLinksChangeVarcharColumnsToText
  , tempCredentialChangeVarcharColumnsToText
  , migrateDocumentsAddSignviewSettings
  , migrateDocumentsAddDocumentToken
  , addDomainToSession
  , addConfirmTextToDocuments
  , addConfirmationDeliveryMethodToSignatoryLinks
  , changeSomeStandardFieldsToOptional
  , createSignatorySMSPinsTable
  , createBrandedDomainsTable
  , usersTableChangeAssociatedDomainToForeignKey
  , addTimeZoneNameToDocuments
  , addLogoImageDataToBrandedDomain
  , addNoReplyEmailToBrandedDomain
  , addNoReplyEmailToBrandedDomainSetDefault
  , addMailsBorderColorToBrandedDomain
  , addAPIVersionToDocument
  , addUniqueContraintsTypeOnFields
  , addAllowSaveSafetyCopyToCompanies
  , addIdleDocTimeout
  , createChargeableItemsTable
  , signatoryLinkFieldsAddBinaryValue
  , createCgiGrpTransactionsTable
  , createEIDSignaturesTable
  , signatoryLinksMoveSignatures
  , companiesAddCgiDisplayName
  , addMtimeStatusIndexes
  , evidenceLogAddActor
  , createThemesTable
  , createThemeOwnersTable
  , addThemesToBrandedDomainAndMainDomain
  , makeAssociatedDomainObligatoryForUsers
  , addThemesAndOthersToCompanyUIs
  , removeSMSOriginatorFromCompany
  , changeScriveLoginLogo
  , createTableDocumentApiCallbackConsumers
  , updateApiCallbacksForNewConsumer
  , dropHTMLFromInvitationAndConfirmationMessages
  , dropHTMLFromMessagesInEvidenceLog
  , apiCallbacksAddIDColumn
  ] ++ cronMigrations
    ++ mailerMigrations
    ++ messengerMigrations
