module AppDBTables (
    kontraComposites
  , kontraDomains
  , kontraExtensions
  , kontraFunctions
  , kontraTables
  ) where

import Database.PostgreSQL.PQTypes.Model

import Attachment.Tables
import BrandedDomain.Tables
import Chargeable.Tables
import Company.Tables
import CompanyAccounts.Tables
import Cron.Tables
import DB.SQLFunction
import Doc.API.Callback.Tables
import Doc.AutomaticReminder.Tables
import Doc.Extending.Tables
import Doc.Sealing.Tables
import Doc.Signing.Tables
import Doc.SMSPin.Tables
import Doc.Tables
import Doc.Tokens.Tables
import EID.Authentication.Tables
import EID.CGI.GRP.Transaction.Tables
import EID.Signature.Tables
import EvidenceLog.Tables
import File.Tables
import HostClock.Tables
import KontraPrelude
import Mails.FromKontra.Tables
import Mails.Tables
import OAuth.Tables
import Partner.Tables
import Session.Tables
import SMS.FromKontra.Tables
import SMS.Tables
import Theme.Tables
import ThirdPartyStats.Tables
import User.CallbackScheme.Tables
import User.EmailChangeRequest.Tables
import User.History.Tables
import User.PasswordReminder.Tables
import User.Tables
import User.UserAccountRequest.Tables

kontraComposites :: [CompositeType]
kontraComposites = [
    ctAuthorAttachment
  , ctSignatoryAttachment
  , ctPlacementAnchor
  , ctFieldPlacement
  , ctHighlightedPage
  , ctSignatoryField
  , ctDocumentTag
  , ctMainFile
  , ctSignatoryLink
  , ctDocument
  ] ++ mailerComposites

kontraDomains :: [Domain]
kontraDomains = [
    domainColor
  , domainFont
  ]

kontraExtensions :: [Extension]
kontraExtensions = [
    "pgcrypto"
  ]

kontraFunctions :: [SQLFunction]
kontraFunctions = [
    insertDocumentSessionToken
  ]

kontraTables :: [Table]
kontraTables =
  [ tableThemes
  , tableBrandedDomains
  , tablePartners
  , tableCompanies
  , tableUsers
  , tablePartnerAdmins
  , tableUsersHistory
  , tableCompanyInvites
  , tableFiles
  , tableDocuments
  , tableMainFiles
  , tableSignatoryLinks
  , tableAuthorAttachments
  , tableSignatoryAttachments
  , tableEvidenceLog
  , tableDocumentTags
  , tableSignatoryLinkFields
  , tableFieldPlacements
  , tablePlacementAnchors
  , tableSignatoryScreenshots
  , tableAPIToken
  , tableAccessToken
  , tablePrivilege
  , tableTempCredential
  , tableTempPrivileges
  , tablePasswordReminders
  , tableEmailChangeRequests
  , tableUserAccountRequests
  , tableAttachments
  , tableDocumentApiCallbackConsumers
  , tableDocumentApiCallbacks
  , tableDocumentExtendingConsumers
  , tableDocumentExtendingJobs
  , tableDocumentSealingConsumers
  , tableDocumentSealingJobs
  , tableDocumentSigningConsumers
  , tableDocumentSigningJobs
  , tableSessions
  , tableDocumentSessionTokens
  , tableCgiGrpTransactions
  , tableEIDSignatures
  , tableAsyncEventQueue
  , tableHostClock
  , tableUsersCallbackScheme
  , tableCompanyUIs
  , tableDocumentAutomaticReminders
  , tableSignatorySMSPins
  , tableChargeableItems
  , tableThemeOwnership
  , tableEIDAuthentications
  , tableHighlightedPages
  ] ++ cronTables
    ++ mailerTables
    ++ messengerTables
    ++ [
    tableKontraInfoForMails
  , tableKontraInfoForSMSes
  ]
