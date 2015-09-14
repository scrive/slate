module Doc.API.V2.JSONList (
  toDocumentSorting
, toDocumentFilter
) where

import Control.Applicative.Free
import Data.Unjson
import qualified Data.Text as T

import DB
import Doc.API.V2.JSONMisc()
import Doc.API.V2.UnjsonUtils
import Doc.DocStateData
import Doc.Model.OrderBy
import KontraPrelude
import MinutesTime
import User.UserID
import qualified Doc.Model.Filter as DF

-- All sorting and filtering types defined in this module are internal to API V2.
-- Sorting and filtering used by API is different then sorting and filtering defined
-- in Doc.Model

-- Note that types defined here aren't even exported, since only Unjson instance is used, and result
-- of parsing is converted immediately to sorting and filtering defined in Doc.Model

data DocumentAPISort = DocumentAPISort DocumentAPISortOn DocumentAPISortOrder

data DocumentAPISortOn = DocumentAPISortStatus | DocumentAPISortTitle | DocumentAPISortTime| DocumentAPISortAuthor deriving Eq
data DocumentAPISortOrder = DocumentAPISortAsc | DocumentAPISortDesc  deriving Eq

instance Unjson DocumentAPISortOrder where
  unjsonDef = unjsonEnumBy "DocumentAPISortOrder" [
      (DocumentAPISortAsc, "ascending")
    , (DocumentAPISortDesc, "descending")
    ]

instance Unjson DocumentAPISortOn where
  unjsonDef = unjsonEnumBy "DocumentAPISortOn" [
      (DocumentAPISortStatus, "status")
    , (DocumentAPISortTitle, "title")
    , (DocumentAPISortTime, "mtime")
    , (DocumentAPISortAuthor, "author")
    ]

instance Unjson DocumentAPISort where
  unjsonDef = objectOf $ pure DocumentAPISort
    <*> field "sort_by" (\(DocumentAPISort v _) -> v) "How documents should be sorted"
    <*> fieldDef "order" DocumentAPISortAsc (\(DocumentAPISort _ o) -> o) "Descending or ascending sorting"


toDocumentSorting ::  DocumentAPISort -> AscDesc DocumentOrderBy
toDocumentSorting (DocumentAPISort DocumentAPISortStatus DocumentAPISortAsc) = Asc DocumentOrderByStatus
toDocumentSorting (DocumentAPISort DocumentAPISortTitle DocumentAPISortAsc) = Asc DocumentOrderByTitle
toDocumentSorting (DocumentAPISort DocumentAPISortTime DocumentAPISortAsc) = Asc DocumentOrderByMTime
toDocumentSorting (DocumentAPISort DocumentAPISortAuthor DocumentAPISortAsc) = Asc DocumentOrderByAuthor
toDocumentSorting (DocumentAPISort DocumentAPISortStatus DocumentAPISortDesc) = Desc DocumentOrderByStatus
toDocumentSorting (DocumentAPISort DocumentAPISortTitle DocumentAPISortDesc) = Desc DocumentOrderByTitle
toDocumentSorting (DocumentAPISort DocumentAPISortTime DocumentAPISortDesc) = Desc DocumentOrderByMTime
toDocumentSorting (DocumentAPISort DocumentAPISortAuthor DocumentAPISortDesc) = Desc DocumentOrderByAuthor

data DocumentAPIFilter = DocumentAPIFilterStatuses [DocumentStatus]
                    | DocumentAPIFilterTime (Maybe UTCTime) (Maybe UTCTime)
                    | DocumentAPIFilterTag T.Text T.Text
                    | DocumentAPIFilterIsAuthor
                    | DocumentAPIFilterIsAuthoredBy UserID
                    | DocumentAPIFilterIsSignableOnPad
                    | DocumentAPIFilterIsTemplate Bool
                    | DocumentAPIFilterIsInTrash Bool
                    | DocumentAPIFilterByText T.Text
                    | DocumentAPIFilterCanBeSignedBy UserID


filterType ::  DocumentAPIFilter -> T.Text
filterType (DocumentAPIFilterStatuses _) = "status"
filterType (DocumentAPIFilterTime _ _) = "mtime"
filterType (DocumentAPIFilterTag _ _) = "tag"
filterType (DocumentAPIFilterIsAuthor) = "is_author"
filterType (DocumentAPIFilterIsAuthoredBy _) = "author"
filterType (DocumentAPIFilterIsSignableOnPad) = "is_signable_on_pad"
filterType (DocumentAPIFilterIsTemplate _) = "template"
filterType (DocumentAPIFilterIsInTrash _) = "trash"
filterType (DocumentAPIFilterByText _) = "text"
filterType (DocumentAPIFilterCanBeSignedBy _) = "user_can_sign"

instance Unjson DocumentAPIFilter where
  unjsonDef = disjointUnionOf "filter_by" $ filterMatch <$> [
        (DocumentAPIFilterStatuses [], unjsonDocumentAPIFilterStatuses)
      , (DocumentAPIFilterTime Nothing Nothing, unjsonDocumentAPIFilterTime)
      , (DocumentAPIFilterTag "" "", unjsonDocumentAPIFilterTag)
      , (DocumentAPIFilterIsAuthor, unjsonDocumentAPIFilterIsAuthor)
      , (DocumentAPIFilterIsAuthoredBy (unsafeUserID 0), unjsonDocumentAPIFilterIsAuthoredBy)
      , (DocumentAPIFilterIsSignableOnPad, unjsonDocumentAPIFilterIsSignableOnPad)
      , (DocumentAPIFilterIsTemplate False, unjsonDocumentAPIFilterIsTemplate)
      , (DocumentAPIFilterIsInTrash False, unjsonDocumentAPIFilterIsInTrash)
      , (DocumentAPIFilterByText "", unjsonDocumentAPIFilterByText)
      , (DocumentAPIFilterCanBeSignedBy (unsafeUserID 0), unjsonDocumentAPIFilterCanBeSignedBy)
    ]
    where
      filterMatch :: (DocumentAPIFilter,Ap (FieldDef DocumentAPIFilter) DocumentAPIFilter) -> (T.Text, DocumentAPIFilter -> Bool, Ap (FieldDef DocumentAPIFilter) DocumentAPIFilter)
      filterMatch (df,a) = (filterType df, \f -> filterType df == filterType f, a)

unjsonDocumentAPIFilterStatuses:: Ap (FieldDef DocumentAPIFilter) DocumentAPIFilter
unjsonDocumentAPIFilterStatuses = pure DocumentAPIFilterStatuses
  <*  fieldReadonly "filter_by" filterType "Type of filter"
  <*> field "statuses" unsafeDocumentAPIFilterStatuses "Statuses to filter on"
  where
    unsafeDocumentAPIFilterStatuses:: DocumentAPIFilter ->  [DocumentStatus]
    unsafeDocumentAPIFilterStatuses(DocumentAPIFilterStatuses fs) = fs
    unsafeDocumentAPIFilterStatuses _ = $unexpectedError "unsafeDocumentAPIFilterStatus"

unjsonDocumentAPIFilterTime :: Ap (FieldDef DocumentAPIFilter) DocumentAPIFilter
unjsonDocumentAPIFilterTime = pure DocumentAPIFilterTime
  <*  fieldReadonly "filter_by" filterType "Type of filter"
  <*> fieldOpt "start_time" unsafeDocumentAPIFilterStartTime "Only documents after start time"
  <*> fieldOpt "end_time" unsafeDocumentAPIFilterEndTime "Only documents before end time"
  where
    unsafeDocumentAPIFilterStartTime :: DocumentAPIFilter ->  Maybe UTCTime
    unsafeDocumentAPIFilterStartTime (DocumentAPIFilterTime s _) = s
    unsafeDocumentAPIFilterStartTime _ = $unexpectedError "unsafeDocumentAPIFilterStartTime"
    unsafeDocumentAPIFilterEndTime :: DocumentAPIFilter ->  Maybe UTCTime
    unsafeDocumentAPIFilterEndTime (DocumentAPIFilterTime _ e) = e
    unsafeDocumentAPIFilterEndTime _ = $unexpectedError "unsafeDocumentAPIFilterEndTime"

unjsonDocumentAPIFilterTag:: Ap (FieldDef DocumentAPIFilter) DocumentAPIFilter
unjsonDocumentAPIFilterTag = pure DocumentAPIFilterTag
  <*  fieldReadonly "filter_by" filterType "Type of filter"
  <*> field "name" unsafeDocumentAPIFilterTagName "Name of tag to filter on"
  <*> field "value" unsafeDocumentAPIFilterTagValue "Value of such tag"
  where
    unsafeDocumentAPIFilterTagName:: DocumentAPIFilter ->  T.Text
    unsafeDocumentAPIFilterTagName (DocumentAPIFilterTag n _) = n
    unsafeDocumentAPIFilterTagName _ = $unexpectedError "unsafeDocumentAPIFilterTagName"
    unsafeDocumentAPIFilterTagValue:: DocumentAPIFilter ->  T.Text
    unsafeDocumentAPIFilterTagValue (DocumentAPIFilterTag _ v) = v
    unsafeDocumentAPIFilterTagValue _ = $unexpectedError "unsafeDocumentAPIFilterTagValue"

unjsonDocumentAPIFilterIsAuthor:: Ap (FieldDef DocumentAPIFilter) DocumentAPIFilter
unjsonDocumentAPIFilterIsAuthor = pure DocumentAPIFilterIsAuthor
  <*  fieldReadonly "filter_by" filterType "Type of filter"

unjsonDocumentAPIFilterIsAuthoredBy:: Ap (FieldDef DocumentAPIFilter) DocumentAPIFilter
unjsonDocumentAPIFilterIsAuthoredBy = pure DocumentAPIFilterIsAuthoredBy
  <*  fieldReadonly "filter_by" filterType "Type of filter"
  <*> field "user_id" unsafeDocumentAPIFilterUserID "Id of author"
  where
    unsafeDocumentAPIFilterUserID :: DocumentAPIFilter ->  UserID
    unsafeDocumentAPIFilterUserID (DocumentAPIFilterIsAuthoredBy uid) = uid
    unsafeDocumentAPIFilterUserID _ = $unexpectedError "unsafeDocumentAPIFilterStatus"

unjsonDocumentAPIFilterIsSignableOnPad :: Ap (FieldDef DocumentAPIFilter) DocumentAPIFilter
unjsonDocumentAPIFilterIsSignableOnPad = pure DocumentAPIFilterIsSignableOnPad
  <*  fieldReadonly "filter_by" filterType "Type of filter"


unjsonDocumentAPIFilterIsTemplate:: Ap (FieldDef DocumentAPIFilter) DocumentAPIFilter
unjsonDocumentAPIFilterIsTemplate = pure DocumentAPIFilterIsTemplate
  <*  fieldReadonly "filter_by" filterType "Type of filter"
  <*> field "is_template" unsafeDocumentAPIFilterIsTemplate "Filter documents that are templates"
  where
    unsafeDocumentAPIFilterIsTemplate :: DocumentAPIFilter ->  Bool
    unsafeDocumentAPIFilterIsTemplate (DocumentAPIFilterIsTemplate is_template) = is_template
    unsafeDocumentAPIFilterIsTemplate _ = $unexpectedError "unsafeDocumentAPIFilterIsTemplate"

unjsonDocumentAPIFilterIsInTrash:: Ap (FieldDef DocumentAPIFilter) DocumentAPIFilter
unjsonDocumentAPIFilterIsInTrash = pure DocumentAPIFilterIsInTrash
  <*  fieldReadonly "filter_by" filterType "Type of filter"
  <*> field "is_trashed" unsafeDocumentAPIFilterIsTrashed "Filter documents that are in trash"
  where
    unsafeDocumentAPIFilterIsTrashed :: DocumentAPIFilter ->  Bool
    unsafeDocumentAPIFilterIsTrashed (DocumentAPIFilterIsInTrash is_trashed) = is_trashed
    unsafeDocumentAPIFilterIsTrashed _ = $unexpectedError "unsafeDocumentAPIFilterIsTrashed"

unjsonDocumentAPIFilterByText:: Ap (FieldDef DocumentAPIFilter) DocumentAPIFilter
unjsonDocumentAPIFilterByText = pure DocumentAPIFilterByText
  <*  fieldReadonly "filter_by" filterType "Type of filter"
  <*> field "text" unsafeDocumentAPIFilterText "Text to filter on"
  where
    unsafeDocumentAPIFilterText :: DocumentAPIFilter ->  T.Text
    unsafeDocumentAPIFilterText (DocumentAPIFilterByText text) = text
    unsafeDocumentAPIFilterText _ = $unexpectedError "unsafeDocumentAPIFilterText"

unjsonDocumentAPIFilterCanBeSignedBy:: Ap (FieldDef DocumentAPIFilter) DocumentAPIFilter
unjsonDocumentAPIFilterCanBeSignedBy = pure DocumentAPIFilterCanBeSignedBy
  <*  fieldReadonly "filter_by" filterType "Type of filter"
  <*> field "user_id" unsafeDocumentAPIFilterUserID "Id of user that can sign"
  where
    unsafeDocumentAPIFilterUserID :: DocumentAPIFilter ->  UserID
    unsafeDocumentAPIFilterUserID (DocumentAPIFilterCanBeSignedBy uid) = uid
    unsafeDocumentAPIFilterUserID _ = $unexpectedError "unsafeDocumentAPIFilterStatus"


toDocumentFilter :: UserID -> DocumentAPIFilter -> [DF.DocumentFilter]
toDocumentFilter _ (DocumentAPIFilterStatuses ss) = [DF.DocumentFilterStatuses ss]
toDocumentFilter _ (DocumentAPIFilterTime (Just start) (Just end)) = [DF.DocumentFilterByTimeAfter start, DF.DocumentFilterByTimeBefore end]
toDocumentFilter _ (DocumentAPIFilterTime Nothing (Just end)) = [DF.DocumentFilterByTimeBefore end]
toDocumentFilter _ (DocumentAPIFilterTime (Just start) Nothing) = [DF.DocumentFilterByTimeAfter start]
toDocumentFilter _ (DocumentAPIFilterTime Nothing Nothing) = []
toDocumentFilter _ (DocumentAPIFilterTag name value) = [DF.DocumentFilterByTags [DocumentTag (T.unpack name) (T.unpack value)]]
toDocumentFilter uid (DocumentAPIFilterIsAuthor) = [DF.DocumentFilterByAuthor uid]
toDocumentFilter _ (DocumentAPIFilterIsAuthoredBy uid) = [DF.DocumentFilterByAuthor uid]
toDocumentFilter _ (DocumentAPIFilterIsSignableOnPad) = [DF.DocumentFilterSignNowOnPad]
toDocumentFilter _ (DocumentAPIFilterIsTemplate True)  = [DF.DocumentFilterTemplate]
toDocumentFilter _ (DocumentAPIFilterIsTemplate False) = [DF.DocumentFilterSignable]
toDocumentFilter _ (DocumentAPIFilterIsInTrash bool) = [DF.DocumentFilterDeleted bool]
toDocumentFilter _ (DocumentAPIFilterByText text) = [DF.DocumentFilterByString (T.unpack text)]
toDocumentFilter _ (DocumentAPIFilterCanBeSignedBy uid) = [DF.DocumentFilterByCanSign uid]
