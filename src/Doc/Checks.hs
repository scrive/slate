module Doc.Checks (
    checkPreparationToPending
  , checkCancelDocument
  , checkCloseDocument
  , checkRejectDocument
  , checkSignDocument
  ) where

import Control.Applicative
import Data.Monoid

import DB
import Doc.DocStateData
import MagicHash
import Misc

checkPreparationToPending :: MonadDB m => DocumentID -> DBEnv m [String]
checkPreparationToPending did = checkDocument did [
    isSignable
  , isPreparation
  , hasOneAuthor
  , hasSignatories
  , hasOneFile
  ]

checkCancelDocument :: MonadDB m => DocumentID -> DBEnv m [String]
checkCancelDocument did = checkDocument did [
    isSignable
  , isPending
  ]

checkCloseDocument :: MonadDB m => DocumentID -> DBEnv m [String]
checkCloseDocument did = checkDocument did [
    isSignable
  , isPending
  , allHaveSigned
  ]

checkRejectDocument :: MonadDB m => DocumentID -> SignatoryLinkID -> DBEnv m [String]
checkRejectDocument did slid = checkDocument did [
    isSignable
  , isPending
  , hasSignatory slid
  ]

checkSignDocument :: MonadDB m => DocumentID -> SignatoryLinkID -> MagicHash -> DBEnv m [String]
checkSignDocument did slid mh = checkDocument did [
    isPending
  , isSignable
  , hasSignatory slid
  , hasNotSigned slid
  --, hasSeenDoc slid
  , hasMagicHash slid mh
  ]

-- internal stuff

checkDocument :: MonadDB m => DocumentID -> [(SQL, String)] -> DBEnv m [String]
checkDocument did conditions = do
  _ <- kRun $ mconcat [
      SQL "SELECT regexp_split_to_table(" []
    , helper conditions
    , SQL ", '[\\n\\r]+') FROM documents d WHERE id = ?" [toSql did]
    ]
  filter (not . null) <$> foldDB (flip (:)) []
  where
    helper = mintercalate (\a b -> a <++> SQL " || '\n' || " [] <++> b)
      . map (\(s, msg) -> mconcat [
        SQL "(CASE WHEN (" []
      , s
      , SQL ") THEN '' ELSE " []
      , SQL "?" [toSql msg]
      , SQL " END)" []
      ])

isSignable :: (SQL, String)
isSignable = (SQL "type = ?" [toSql $ Signable undefined], "Document is not Signable")

isPending :: (SQL, String)
isPending = (SQL "status = ?" [toSql Pending], "Document is not Pending")

isPreparation :: (SQL, String)
isPreparation = (SQL "status = ?" [toSql Preparation], "Document is not Preparation")

allHaveSigned :: (SQL, String)
allHaveSigned = (SQL "(SELECT COUNT(*) FROM signatory_links WHERE document_id = d.id AND (roles & ?) <> 0 AND sign_time IS NULL) = 0" [toSql [SignatoryPartner]], "Not all signatories have signed")

hasOneAuthor :: (SQL, String)
hasOneAuthor = (SQL "(SELECT COUNT(*) FROM signatory_links WHERE document_id = d.id AND (roles & ?) <> 0) = 1" [toSql [SignatoryAuthor]], "Number of authors was not 1")

hasSignatories :: (SQL, String)
hasSignatories = (SQL "(SELECT COUNT(*) FROM signatory_links WHERE document_id = d.id AND (roles & ?) <> 0) > 0" [toSql [SignatoryPartner]], "Document has no signatories")

hasOneFile :: (SQL, String)
hasOneFile = (SQL "file_id IS NOT NULL AND sealed_file_id IS NULL" [], "Document doesn't have exactly one file")

hasSignatory :: SignatoryLinkID -> (SQL, String)
hasSignatory slid = (SQL "(SELECT COUNT(*) FROM signatory_links sl WHERE sl.id = ? AND document_id = d.id AND (roles & ?) <> 0) = 1" [toSql slid, toSql [SignatoryPartner]], "Signatory #" ++ show slid ++ " either doesn't belong to this document or is not signatory partner")

hasNotSigned :: SignatoryLinkID -> (SQL, String)
hasNotSigned slid = (SQL "(SELECT COUNT(*) FROM signatory_links sl WHERE sl.id = ? AND document_id = d.id AND sign_time IS NULL) = 1" [toSql slid], "Signatory #" ++ show slid ++ " has already signed")

-- delete Oct 1, 2012 -Eric
--hasSeenDoc :: SignatoryLinkID -> (SQL, String)
--hasSeenDoc slid = (SQL "(SELECT COUNT(*) FROM signatory_links sl WHERE sl.id = ? AND document_id = d.id AND seen_time IS NOT NULL) = 1" [toSql slid], "Signatory #" ++ show slid ++ " didn't see the document")

hasMagicHash :: SignatoryLinkID -> MagicHash -> (SQL, String)
hasMagicHash slid mh = (SQL "SELECT token = ? FROM signatory_links sl WHERE sl.id = ? AND document_id = d.id" [toSql mh, toSql slid], "Magic hash for signatory #" ++ show slid ++ " doesn't match")
