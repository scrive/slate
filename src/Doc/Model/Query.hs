{-# OPTIONS_GHC -fcontext-stack=50  -fno-warn-orphans #-}
module Doc.Model.Query
  ( isTemplate -- fromUtils
  , DocumentFilter(..)
  , DocumentDomain(..)
  , DocumentOrderBy(..)
  , FileInDocument(..)
  , GetDocuments(..)
  , GetDocuments2(..)
  , GetDocumentsIDs(..)
  , GetDocumentByDocumentID(..)
  , GetDocumentBySignatoryLinkID(..)
  , GetDocumentsBySignatoryLinkIDs(..)
  , GetDocumentByDocumentIDSignatoryLinkIDMagicHash(..)
  , GetDocumentsByAuthor(..)
  , GetSignatoryScreenshots(..)
  , GetSignatoryLinkByID(..)
  , GetTemplatesByAuthor(..)
  , GetAvailableTemplates(..)
  , GetTimeoutedButPendingDocumentsChunk(..)
  , GetDocsSentBetween(..)
  , GetDocsSent(..)
  , GetDocumentTags(..)
  , GetSignatoriesByEmail(..)
  , CheckDocumentObjectVersionIs(..)
  ) where

import Control.Applicative
import Control.Monad
import Control.Monad.Catch
import Control.Monad.IO.Class
import Data.Int
import Data.List hiding (tail, head)
import Data.Maybe hiding (fromJust)
import Data.Monoid
import Data.Monoid.Space
import Prelude hiding (head, tail)
import qualified Control.Monad.State.Lazy as State
import qualified Data.ByteString as BS
import qualified Data.Map as M
import qualified Data.Set as S

import API.APIVersion
import Company.CompanyID
import DB
import DB.RowCache (GetRow(..))
import DB.TimeZoneName
import Doc.Conditions
import Doc.DocStateData
import Doc.DocumentID
import Doc.DocUtils
import Doc.Model.Domain
import Doc.Model.Expressions
import Doc.Model.Filter
import Doc.Model.OrderBy
import Doc.Screenshot
import Doc.SignatoryLinkID
import Doc.SignatoryScreenshots
import File.FileID
import File.Storage
import IPAddress
import MagicHash
import MinutesTime
import OurPrelude
import User.Email
import User.Model
import qualified Amazon
import qualified Log

selectTablesForDocumentSelectors :: State.State SqlSelect () -> SqlSelect
selectTablesForDocumentSelectors = sqlSelect2 "documents as documents LEFT JOIN document_automatic_reminders as document_automatic_reminders ON documents.id = document_automatic_reminders.document_id LEFT JOIN signatory_links AS signatory_links_authors ON documents.id = signatory_links_authors.document_id and signatory_links_authors.is_author = true LEFT JOIN users as user_authors ON signatory_links_authors.user_id = user_authors.id"

documentsSelectors :: [SQL]
documentsSelectors =
  [ "documents.id"
  , "documents.title"
  , "documents.status"
  , "documents.error_text"
  , "documents.type"
  , "documents.ctime"
  , "documents.mtime"
  , "documents.days_to_sign"
  , "documents.days_to_remind"
  , "documents.timeout_time"
  , "document_automatic_reminders.expires"
  , "documents.invite_time"
  , "documents.invite_ip"
  , "documents.invite_text"
  , "documents.confirm_text"
  , "documents.show_header"
  , "documents.show_pdf_download"
  , "documents.show_reject_option"
  , "documents.show_footer"
  , "documents.lang"
  , "documents.sharing"
  , "documents.api_callback_url"
  , "documents.unsaved_draft"
  , "documents.object_version"
  , "documents.token"
  , "documents.time_zone_name"
  , "documents.api_version"
  , "user_authors.company_id"
  , documentStatusClassExpression
  ]

fetchDocument :: (DocumentID, String, DocumentStatus, Maybe String, DocumentType, UTCTime, UTCTime, Int32, Maybe Int32, Maybe UTCTime, Maybe UTCTime, Maybe UTCTime, Maybe IPAddress, String, String, Bool, Bool, Bool, Bool, Lang, DocumentSharing, Maybe String, Bool, Int64, MagicHash, TimeZoneName, APIVersion,  Maybe CompanyID, StatusClass) -> Document
fetchDocument (did, title, status, error_text, doc_type, ctime, mtime, days_to_sign, days_to_remind, timeout_time, auto_remind_time, invite_time, invite_ip, invite_text, confirm_text,  show_header, show_pdf_download, show_reject_option, show_footer, lang, sharing, apicallback, unsaved_draft, objectversion, token, time_zone_name, api_version, author_company_id, status_class)
       = Document {
         documentid = did
       , documenttitle = title
       , documentsignatorylinks = []
       , documentmainfiles = []
       , documentstatus = case (status, error_text) of
           (DocumentError{}, Just text) -> DocumentError text
           (DocumentError{}, Nothing) -> DocumentError "document error"
           _ -> status
       , documenttype = doc_type
       , documentctime = ctime
       , documentmtime = mtime
       , documentdaystosign = days_to_sign
       , documentdaystoremind = days_to_remind
       , documenttimeouttime = timeout_time
       , documentautoremindtime = case status of
                                    Pending -> auto_remind_time
                                    _ -> Nothing
       , documentinvitetime = case invite_time of
           Nothing -> Nothing
           Just t -> Just (SignInfo t $ fromMaybe noIP invite_ip)
       , documentinvitetext = invite_text
       , documentconfirmtext = confirm_text
       , documentshowheader = show_header
       , documentshowpdfdownload = show_pdf_download
       , documentshowrejectoption = show_reject_option
       , documentshowfooter = show_footer
       , documentsharing = sharing
       , documenttags = S.empty
       , documentauthorattachments = []
       , documentlang = lang
       , documentstatusclass = status_class
       , documentapicallbackurl = apicallback
       , documentunsaveddraft = unsaved_draft
       , documentobjectversion = objectversion
       , documentmagichash = token
       , documentauthorcompanyid = author_company_id
       , documenttimezonename = time_zone_name
       , documentapiversion = api_version
       }

selectSignatoryLinksSQL :: SQL
selectSignatoryLinksSQL = toSQLCommand (selectSignatoryLinksX (return ())) <+> ""

documentTagsSelectors :: SQL
documentTagsSelectors = sqlConcatComma [
    "document_id"
  , "name"
  , "value"
  ]

selectDocumentTagsSQL :: SQL
selectDocumentTagsSQL = "SELECT" <+> documentTagsSelectors <+> "FROM document_tags "

authorAttachmentsSelectors :: SQL
authorAttachmentsSelectors = sqlConcatComma [
    "document_id"
  , "file_id"
  ]

selectAuthorAttachmentsSQL :: SQL
selectAuthorAttachmentsSQL = "SELECT" <+> authorAttachmentsSelectors <+> "FROM author_attachments "

selectMainFilesSQL :: SQL
selectMainFilesSQL = "SELECT" <+> sqlConcatComma mainFilesSelectors <+> "FROM main_files "

selectSignatoryLinkFieldsSQL :: SQL
selectSignatoryLinkFieldsSQL = "SELECT"
  <+> sqlConcatComma signatoryLinkFieldsSelectors
  <+> "FROM signatory_link_fields "

data GetSignatoryScreenshots = GetSignatoryScreenshots [SignatoryLinkID]
instance (MonadDB m, MonadThrow m, Log.MonadLog m, MonadIO m, Amazon.AmazonMonad m) => DBQuery m GetSignatoryScreenshots [(SignatoryLinkID, SignatoryScreenshots)] where
  query (GetSignatoryScreenshots l) = do
    runQuery_ . sqlSelect "signatory_screenshots" $ do
                sqlWhereIn "signatory_link_id" l
                sqlOrderBy "signatory_link_id"

                sqlResult "signatory_link_id"
                sqlResult "type"
                sqlResult "time"
                sqlResult "file_id"
    screenshotsWithoutBinaryData <- fetchMany id
    let getBinaries (slid, ty, time, fid) = do
           bin <- getFileIDContents fid
           return (slid, ty, time, Binary bin)
    screenshotsWithBinaryData <- mapM getBinaries screenshotsWithoutBinaryData

    let folder ((slid', s):a) (slid, ty, time, i) | slid' == slid = (slid, mkss ty time i s):a
        folder a (slid, ty, time, i) = (slid, mkss ty time i emptySignatoryScreenshots) : a

        mkss :: String -> UTCTime -> Binary BS.ByteString -> SignatoryScreenshots -> SignatoryScreenshots
        mkss "first"     time i s = s{ first = Just $ Screenshot time i }
        mkss "signing"   time i s = s{ signing = Just $ Screenshot time i }
        mkss "reference" time i s = s{ reference = Just $ Right $ Screenshot time i }
        mkss t           _    _ _ = error $ "GetSignatoryScreenshots: invalid type: " <> show t
    return $ foldl' folder [] screenshotsWithBinaryData

data FileInDocument = FileInDocument DocumentID FileID
instance (MonadDB m, MonadThrow m) => DBQuery m FileInDocument Bool where
  query (FileInDocument did fid) = do
    let s1 = sqlSelect "main_files" $ do
                   sqlWhereEq "file_id" fid
                   sqlWhereEq "document_id" did
                   sqlResult "TRUE"
    let s2 = sqlSelect "author_attachments" $ do
                   sqlWhereEq "file_id" fid
                   sqlWhereEq "document_id" did
                   sqlResult "TRUE"
    let s3 = sqlSelect "signatory_attachments" $ do
                   sqlJoinOn "signatory_links" "signatory_attachments.signatory_link_id = signatory_links.id"
                   sqlWhereEq "file_id" fid
                   sqlWhereEq "document_id" did
                   sqlResult "TRUE"
    runQuery_ $ "SELECT EXISTS (" <> toSQLCommand s1 <> ") OR " <>
                       "EXISTS (" <> toSQLCommand s2 <> ") OR " <>
                       "EXISTS (" <> toSQLCommand s3 <> ")"
    fetchOne unSingle

selectDocuments :: (MonadDB m, MonadThrow m) => SqlSelect -> m [Document]
selectDocuments sqlquery = snd <$> selectDocumentsWithSoftLimit True Nothing sqlquery

selectDocument :: (MonadDB m, MonadThrow m) => SqlSelect -> m Document
selectDocument sqlquery = $(head) . snd <$> selectDocumentsWithSoftLimit False Nothing sqlquery

selectDocumentsWithSoftLimit :: (MonadDB m, MonadThrow m) => Bool ->  Maybe Int -> SqlSelect -> m (Int,[Document])
selectDocumentsWithSoftLimit allowzeroresults softlimit sqlquery = do

    {-
    kRun_ $ "EXPLAIN (ANALYZE, VERBOSE, COSTS, BUFFERS)" <+> toSQLCommand sqlquery
    let fetchTextLines acc line = line:acc
    textlines <- kFold fetchTextLines []
    mapM_ Log.mixlog_ (reverse textlines)
    -}

    allDocumentsCount :: Int64 <- case softlimit of
      Nothing -> do
        runQuery_ $ "CREATE TEMP TABLE docs AS" <+> toSQLCommand sqlquery
        runSQL_ "SELECT count(*) FROM docs"
        fetchOne unSingle

      Just limit -> do
        runQuery_ $ "CREATE TEMP TABLE docs1 AS" <+> toSQLCommand sqlquery
        runSQL_ $ "CREATE TEMP TABLE docs AS SELECT * FROM docs1 LIMIT" <+> unsafeSQL (show limit)
        runSQL_ "SELECT count(*) FROM docs1"
        count :: Int64 <- fetchOne unSingle
        runSQL_ "DROP TABLE docs1"
        return count

    when (allDocumentsCount==0 && not allowzeroresults) $ do
      runSQL_ "DROP TABLE docs"
      exception <- kWhyNot1 sqlquery

      throwM exception

    runSQL_ "SELECT * FROM docs"
    docs <- fetchMany fetchDocument


    runQuery_ $ "CREATE TEMP TABLE links AS" <+>
         selectSignatoryLinksSQL <+>
         "WHERE EXISTS (SELECT 1 FROM docs WHERE signatory_links.document_id = docs.id) ORDER BY document_id DESC, signatory_links.id DESC"
    runSQL_ "SELECT * FROM links"
    sls <- fetchSignatoryLinks

    runQuery_ $ selectSignatoryLinkFieldsSQL <+> "WHERE EXISTS (SELECT 1 FROM links WHERE links.id = signatory_link_fields.signatory_link_id) ORDER BY signatory_link_fields.id DESC"
    fields <- fetchSignatoryLinkFields

    runQuery_ $ selectAuthorAttachmentsSQL <+> "WHERE EXISTS (SELECT 1 FROM docs WHERE author_attachments.document_id = docs.id) ORDER BY document_id DESC"
    ats <- fetchAuthorAttachments

    runQuery_ $ selectDocumentTagsSQL <+> "WHERE EXISTS (SELECT 1 FROM docs WHERE document_tags.document_id = docs.id)"
    tags <- fetchDocumentTags

    runQuery_ $ selectMainFilesSQL <+> "WHERE EXISTS (SELECT 1 FROM docs WHERE main_files.document_id = docs.id) ORDER BY document_id DESC, id ASC"
    mainfiles <- fetchMainFiles

    runSQL_ "DROP TABLE docs"
    runSQL_ "DROP TABLE links"

    let extendSignatoryLinkWithFields sl =
           sl{ signatoryfields = M.findWithDefault [] (signatorylinkid sl) fields }


    let fill doc = doc
                   { documentsignatorylinks    = extendSignatoryLinkWithFields <$> M.findWithDefault [] (documentid doc) sls
                   , documentauthorattachments = M.findWithDefault [] (documentid doc) ats
                   , documenttags              = M.findWithDefault S.empty (documentid doc) tags
                   , documentmainfiles         = M.findWithDefault [] (documentid doc) mainfiles
                   }

    return (fromIntegral allDocumentsCount, map fill docs)

data GetDocumentTags = GetDocumentTags DocumentID
instance MonadDB m => DBQuery m GetDocumentTags (S.Set DocumentTag) where
  query (GetDocumentTags did) = do
    runQuery_ $ selectDocumentTagsSQL <+> "WHERE document_id =" <?> did
    fromMaybe S.empty . listToMaybe . map snd . M.toList <$> fetchDocumentTags

data GetSignatoryLinkByID = GetSignatoryLinkByID DocumentID SignatoryLinkID (Maybe MagicHash)
instance (MonadDB m, MonadThrow m) => DBQuery m GetSignatoryLinkByID SignatoryLink where
  query (GetSignatoryLinkByID did slid mmh) = do
    let queryx = selectSignatoryLinksX $ do
                  sqlWhereDocumentIDIs did
                  sqlWhereSignatoryLinkIDIs slid
                  case mmh of
                    Nothing -> return ()
                    Just mh -> sqlWhereSignatoryLinkMagicHashIs mh
    runQuery_ queryx
    mlink <- listToMaybe . concatMap snd . M.toList <$> fetchSignatoryLinks
    case mlink of
      Just link -> do
         runQuery_ $ selectSignatoryLinkFieldsSQL
               <+> "WHERE signatory_link_id =" <?> slid
         fields <- fetchSignatoryLinkFields
               >>= return . concatMap snd . M.toList
         return $ link { signatoryfields = fields }
      Nothing -> do
         exception <- kWhyNot1 queryx

         throwM exception

data GetDocumentByDocumentID = GetDocumentByDocumentID DocumentID
instance (MonadDB m, MonadThrow m) => DBQuery m GetDocumentByDocumentID Document where
  query (GetDocumentByDocumentID did) = do
    selectDocument $ selectTablesForDocumentSelectors $ do
      mapM_ sqlResult documentsSelectors
      sqlWhereDocumentIDIs did

data GetDocumentBySignatoryLinkID = GetDocumentBySignatoryLinkID SignatoryLinkID
instance (MonadDB m, MonadThrow m) => DBQuery m GetDocumentBySignatoryLinkID (Maybe Document) where
  query (GetDocumentBySignatoryLinkID slid) =
     (Just <$> (selectDocument $ selectTablesForDocumentSelectors $ do
       mapM_ sqlResult documentsSelectors
       sqlWhereExists $ sqlSelect "signatory_links" $ do
         sqlWhereEq "signatory_links.id" slid
         sqlWhere "signatory_links.document_id = documents.id"))

data GetDocumentsBySignatoryLinkIDs = GetDocumentsBySignatoryLinkIDs [SignatoryLinkID]
instance (MonadDB m, MonadThrow m) => DBQuery m GetDocumentsBySignatoryLinkIDs [Document] where
  query (GetDocumentsBySignatoryLinkIDs slids) =
     selectDocuments $ selectTablesForDocumentSelectors $ do
       mapM_ sqlResult documentsSelectors
       sqlWhereExists $ sqlSelect "signatory_links" $ do
         sqlWhereIn "signatory_links.id" slids
         sqlWhere "signatory_links.document_id = documents.id"

-- TODO: it should return Maybe.
data GetDocumentByDocumentIDSignatoryLinkIDMagicHash = GetDocumentByDocumentIDSignatoryLinkIDMagicHash DocumentID SignatoryLinkID MagicHash
instance (MonadDB m, MonadThrow m) => DBQuery m GetDocumentByDocumentIDSignatoryLinkIDMagicHash Document where
  query (GetDocumentByDocumentIDSignatoryLinkIDMagicHash did slid mh) = do
    selectDocument $ selectTablesForDocumentSelectors $ do
      mapM_ sqlResult documentsSelectors
      sqlWhereDocumentIDIs did
      sqlWhereExists $ sqlSelect "signatory_links" $ do
         sqlWhere "signatory_links.document_id = documents.id"
         -- Thought for later: Here we might actually check if
         -- visibility rules allow a person to see this document, for
         -- example if sign order allows to see the document. For now
         -- we are sloppy and let a person see the document.
         sqlWhereSignatoryLinkIDIs slid
         sqlWhereSignatoryLinkMagicHashIs mh

-- | GetDocuments is central switch for documents list queries.
--
-- GetDocuments domains filters sorting pagination
--
-- * domains are connected with OR, so documents falling into ANY of domains will be returned
-- * filters weed out documents from domains, are connected with AND so a document must pass through ALL filters
-- * sortings returns documents in order
-- * pagination is a place to put OFFSET and LIMIT values
--
-- GetDocuments returns documents in proper order, no reverse is needed.
--
data GetDocuments = GetDocuments [DocumentDomain] [DocumentFilter] [AscDesc DocumentOrderBy] (Int,Int)
instance (MonadDB m, MonadThrow m) => DBQuery m GetDocuments [Document] where
  query (GetDocuments domains filters orderbys (offset,limit)) =
    snd <$> query (GetDocuments2 True domains filters orderbys (offset,limit,Nothing))

data GetDocuments2 = GetDocuments2 Bool [DocumentDomain] [DocumentFilter] [AscDesc DocumentOrderBy] (Int,Int,Maybe Int)
instance (MonadDB m, MonadThrow m) => DBQuery m GetDocuments2 (Int,[Document]) where
  query (GetDocuments2 allowZeroResults domains filters orderbys (offset,limit,softlimit)) = do
    selectDocumentsWithSoftLimit allowZeroResults softlimit $ selectTablesForDocumentSelectors $ do
      mapM_ sqlResult documentsSelectors
      mapM_ (sqlOrderBy . documentOrderByAscDescToSQL) orderbys
      sqlOffset $ fromIntegral offset
      sqlLimit $ fromIntegral limit
      sqlWhereExists $ sqlSelect "signatory_links" $ do
        sqlWhere "documents.id = signatory_links.document_id"
        sqlLeftJoinOn "users" "signatory_links.user_id = users.id"
        sqlLeftJoinOn "companies" "users.company_id = companies.id"
        sqlLeftJoinOn "users AS same_company_users" "users.company_id = same_company_users.company_id OR users.id = same_company_users.id"
        sqlWhereAny (map documentDomainToSQL domains)
        mapM_ documentFilterToSQL filters

data GetDocumentsIDs = GetDocumentsIDs [DocumentDomain] [DocumentFilter] [AscDesc DocumentOrderBy]
instance MonadDB m => DBQuery m GetDocumentsIDs [DocumentID] where
  query (GetDocumentsIDs domains filters orderbys) = do
    runQuery_ $ toSQLCommand $ selectTablesForDocumentSelectors $ do
      sqlResult "documents.id"
      mapM_ (sqlOrderBy . documentOrderByAscDescToSQL) orderbys
      sqlWhereExists $ sqlSelect "signatory_links" $ do
        sqlWhere "documents.id = signatory_links.document_id"
        sqlLeftJoinOn "users" "signatory_links.user_id = users.id"
        sqlLeftJoinOn "companies" "users.company_id = companies.id"
        sqlLeftJoinOn "users AS same_company_users" "users.company_id = same_company_users.company_id OR users.id = same_company_users.id"
        sqlWhereAny (map documentDomainToSQL domains)
        mapM_ documentFilterToSQL filters
    fetchMany unSingle

{- |
    All documents authored by the user that have never been deleted.
-}
data GetDocumentsByAuthor = GetDocumentsByAuthor UserID
instance (MonadDB m, MonadThrow m) => DBQuery m GetDocumentsByAuthor [Document] where
  query (GetDocumentsByAuthor uid) =
    query (GetDocuments [DocumentsVisibleToUser uid] [DocumentFilterByAuthor uid, DocumentFilterDeleted False] [Asc DocumentOrderByMTime] (0,maxBound))

data GetTemplatesByAuthor = GetTemplatesByAuthor UserID
instance (MonadDB m, MonadThrow m) => DBQuery m GetTemplatesByAuthor [Document] where
  query (GetTemplatesByAuthor uid) =
    query (GetDocuments [DocumentsVisibleToUser uid] [DocumentFilterByAuthor uid, DocumentFilterDeleted False, DocumentFilterTemplate] [Asc DocumentOrderByMTime] (0,maxBound))

data GetAvailableTemplates = GetAvailableTemplates UserID
instance (MonadDB m, MonadThrow m) => DBQuery m GetAvailableTemplates [Document] where
  query (GetAvailableTemplates uid) =
    query (GetDocuments [DocumentsVisibleToUser uid]
                            [DocumentFilterTemplate, DocumentFilterDeleted False]
                            [Asc DocumentOrderByMTime]
                            (0,maxBound))

data GetTimeoutedButPendingDocumentsChunk = GetTimeoutedButPendingDocumentsChunk UTCTime Int
instance (MonadDB m, MonadThrow m) => DBQuery m GetTimeoutedButPendingDocumentsChunk [Document] where
  query (GetTimeoutedButPendingDocumentsChunk mtime size) = do
    selectDocuments $ selectTablesForDocumentSelectors $ do
      mapM_ sqlResult documentsSelectors
      sqlWhereEq "documents.status" Pending
      sqlWhere $ "timeout_time IS NOT NULL AND timeout_time < " <?> mtime
      sqlLimit (fromIntegral size)

data GetDocsSentBetween = GetDocsSentBetween CompanyID UTCTime UTCTime
instance MonadDB m => DBQuery m GetDocsSentBetween Int64 where
  query (GetDocsSentBetween cid start end) = do
    runQuery_ $ "SELECT count(documents.id) " <>
               "FROM documents " <>
               "JOIN signatory_links ON documents.id = signatory_links.document_id " <>
               "JOIN users ON signatory_links.user_id = users.id " <>
               "WHERE users.company_id =" <?> cid <>
               "AND is_author " <>
               "AND documents.invite_time >=" <?> start <>
               "AND documents.invite_time <" <?> end <>
               "AND documents.type =" <?> Signable <>
               "AND documents.status <>" <?> Preparation
    foldlM (\acc (Single n) -> return $ acc + n) 0

data GetDocsSent = GetDocsSent UserID
instance MonadDB m => DBQuery m GetDocsSent Int64 where
  query (GetDocsSent uid) = do
    runQuery_ $ "SELECT count(documents.id) " <>
               "FROM documents " <>
               "JOIN signatory_links ON documents.id = signatory_links.document_id " <>
               "WHERE signatory_links.user_id =" <?> uid <>
               "AND is_author " <>
               "AND documents.type =" <?> Signable <>
               "AND documents.status <>" <?> Preparation
    foldlM (\acc (Single n) -> return $ acc + n) 0

-- | Get the signatories that belong to this email that were viewed or signed
--   since time
data GetSignatoriesByEmail = GetSignatoriesByEmail Email UTCTime
instance MonadDB m => DBQuery m GetSignatoriesByEmail [(DocumentID, SignatoryLinkID)] where
  query (GetSignatoriesByEmail email time) = do
    runQuery_ $ "SELECT DISTINCT signatory_links.document_id, signatory_links.id " <+>
            "FROM signatory_links " <+>
            "JOIN signatory_link_fields ON (signatory_link_fields.signatory_link_id = signatory_links.id " <+>
            "                           AND signatory_link_fields.type = " <?> EmailFT <+>
            "                           AND signatory_link_fields.value_text = " <?> email <+>
            "                              )" <+>
            "WHERE sign_time > " <?> time <+>
            "   OR seen_time > " <?> time
    fetchMany id

data CheckDocumentObjectVersionIs = CheckDocumentObjectVersionIs DocumentID Int64
instance (MonadDB m, MonadThrow m) => DBQuery m CheckDocumentObjectVersionIs () where
  query (CheckDocumentObjectVersionIs did ov) = do
    _ :: Bool <- kRunAndFetch1OrThrowWhyNot unSingle $ sqlSelect "documents" $ do
       sqlResult "TRUE"
       sqlWhereDocumentIDIs did
       sqlWhereDocumentObjectVersionIs ov
    return ()

instance (MonadDB m, MonadThrow m) => GetRow Document m where
  getRow did = dbQuery $ GetDocumentByDocumentID did
