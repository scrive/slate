-----------------------------------------------------------------------------
-- |
-- Module      :  Doc.DocUtils
-- Author      :  Eric Normand
-- Stability   :  development
-- Portability :  portable
--
-- Utility functions for accessing the innards of Documents and other
-- datatypes in Doc.DocStateData
-----------------------------------------------------------------------------

module Doc.DocUtils where

import Control.Logic
import Util.HasSomeCompanyInfo
import Util.HasSomeUserInfo
import Doc.DocStateData
import Text.StringTemplates.Templates
import Templates
import User.Model
import Doc.SignatoryLinkID
import Util.SignatoryLinkUtils
import Doc.DocInfo
import Company.Model
import DB
import qualified Text.StringTemplates.Fields as F

import Control.Monad
import Data.List hiding (insert)
import Data.Maybe
import File.Model
import Control.Applicative

{- |
   Given a Document, return all of the signatory details for all signatories (exclude viewers but include author if he must sign).
   See also: partyListButAuthor to exclude the author.
 -}
partyList :: Document -> [SignatoryDetails]
partyList document = [signatorydetails sl | sl <- documentsignatorylinks document
                                          , isSignatory sl]

partyListButAuthor :: Document -> [SignatoryDetails]
partyListButAuthor document = [signatorydetails sl | sl <- documentsignatorylinks document
                                          , isSignatory sl
                                          , not $ isAuthor sl
                                          ]
{- |
   Given a Document, return all of the signatory details for all signatories who have signed.
 -}
partySignedList :: Document -> [SignatoryDetails]
partySignedList document = [signatorydetails sl | sl <- documentsignatorylinks document
                                                , isSignatory sl
                                                ,  hasSigned sl]


renderListTemplateNormal :: TemplatesMonad m => [String] -> m String
renderListTemplateNormal = renderListTemplateNormalHelper renderTemplate

renderListTemplateNormalHelper :: TemplatesMonad m
                         => (String -> Fields m () -> m String)
                         -> [String]
                         -> m String
renderListTemplateNormalHelper renderFunc list =
  if length list > 1
     then renderFunc "morethenonelistnormal" $ do
         F.value "list" $ init list
         F.value "last" $ last list
     else renderFunc "nomorethanonelistnormal" $ F.value "list" list


-- where does this go? -EN
renderListTemplate :: TemplatesMonad m => [String] -> m String
renderListTemplate = renderListTemplateHelper renderTemplate

renderLocalListTemplate :: (HasLang a, TemplatesMonad m) => a -> [String] -> m String
renderLocalListTemplate = renderListTemplateHelper .renderLocalTemplate

renderListTemplateHelper :: TemplatesMonad m
                         => (String -> Fields m () -> m String)
                         -> [String]
                         -> m String
renderListTemplateHelper renderFunc list =
  if length list > 1
     then renderFunc "morethenonelist" $ do
         F.value "list" $ init list
         F.value "last" $ last list
     else renderFunc "nomorethanonelist" $ F.value "list" list

-- CHECKERS

{- |
  We introduce some types that basicly describes the user. No we want a unified way of comparring them.
-}
class MaybeUser u where
  getUserID:: u -> Maybe UserID

instance MaybeUser SignatoryLink where
  getUserID  = maybesignatory

instance MaybeUser User where
  getUserID = Just . userid

instance MaybeUser UserID where
  getUserID = Just

instance (MaybeUser u) => MaybeUser (Maybe u) where
  getUserID  = join . fmap getUserID

{- |  And this is a function for comparison -}
sameUser:: (MaybeUser u1, MaybeUser u2) =>  u1 ->  u2 -> Bool
sameUser u1 u2 = getUserID u1 == getUserID u2

class MaybeTemplate a where
   isTemplate :: a -> Bool
   isSignable :: a -> Bool

instance MaybeTemplate DocumentType where
   isTemplate (Template _) = True
   isTemplate _ = False
   isSignable (Signable _) = True
   isSignable _ = False

instance MaybeTemplate Document where
   isTemplate = isTemplate . documenttype
   isSignable = isSignable . documenttype

class HasFieldType a where
    fieldType :: a -> FieldType

instance HasFieldType FieldType where
    fieldType = id

instance HasFieldType SignatoryField where
    fieldType = sfType

matchingFieldType:: (HasFieldType a, HasFieldType b) => a -> b -> Bool
matchingFieldType a b = case (fieldType a, fieldType b) of
                        (CustomFT a' _, CustomFT b' _) -> a' == b'
                        (a',b') -> a' == b'

class HasFields a where
    replaceField :: SignatoryField -> a -> a
    getAllFields:: a ->  [SignatoryField]

instance HasFields  [SignatoryField] where
    getAllFields = id
    replaceField f fs = if (any (matchingFieldType f) fs)
                                then map (\f' ->  f <| (matchingFieldType f f') |> f' )  fs
                                else fs  ++ [f]

instance HasFields SignatoryDetails where
    getAllFields = getAllFields . signatoryfields
    replaceField f s = s {signatoryfields = replaceField f (signatoryfields s) }

instance HasFields SignatoryLink where
    getAllFields =  getAllFields . signatorydetails
    replaceField f s = s {signatorydetails = replaceField f (signatorydetails s) }

replaceFieldValue :: HasFields a =>  FieldType -> String -> a -> a
replaceFieldValue ft v a = case (find (matchingFieldType ft) $ getAllFields a) of
                            Just f  -> replaceField (f { sfType = ft, sfValue = v}) a
                            Nothing -> replaceField (SignatoryField { sfType = ft, sfValue = v, sfPlacements =[], sfObligatory = True, sfShouldBeFilledBySender = False}) a

-- does this need to change now? -EN
checkCSVSigIndex :: [SignatoryLink] -> Int -> Either String Int
checkCSVSigIndex sls n
  | n < 0 || n >= length sls = Left $ "checkCSVSigIndex: signatory with index " ++ show n ++ " doesn't exist."
  | isAuthor (sls !! n) = Left $ "checkCSVSigIndex: signatory at index " ++ show n ++ " is an author and can't be set from csv"
  | otherwise = Right n

{- |
   Given a Document, return all of the undelivered signatorylinks.
 -}
undeliveredSignatoryLinks :: Document -> [SignatoryLink]
undeliveredSignatoryLinks doc = filter isUndelivered $ documentsignatorylinks doc

{- |
   Are there any undelivered signatory links?
 -}
anyInvitationUndelivered :: Document -> Bool
anyInvitationUndelivered doc =  any isUndelivered $ documentsignatorylinks doc

-- OTHER UTILS

-- | Indicates which signatories were activated (received
-- invitation email). All signatories with sign order
-- not greater than current sign order of the document
-- are considered to be activated.
documentcurrentsignorder :: Document -> SignOrder
documentcurrentsignorder doc =
    case filter notSigned sigs of
         [] -> maximum $ map signorder sigs
         xs -> minimum $ map signorder xs
    where
        signorder = signatorysignorder . signatorydetails
        sigs = documentsignatorylinks doc
        notSigned siglnk = isNothing (maybesigninfo siglnk)
          && signatoryispartner (signatorydetails siglnk) -- we exclude non-signatories

{- |
   Build a SignatoryDetails from a User with no fields
 -}
signatoryDetailsFromUser :: (MonadDB m) => User -> (Bool, Bool) -> m SignatoryDetails
signatoryDetailsFromUser user (is_author, is_partner) = do
  mcompany <- maybe (return Nothing) (dbQuery . GetCompany) (usercompany user)
  return $ SignatoryDetails
    { signatorysignorder = SignOrder 1
    , signatoryfields =
        [ toSF FirstNameFT $ getFirstName user
        , toSF LastNameFT $ getLastName user
        , toSF EmailFT $ getEmail user
        , toSF MobileFT $ getMobile user
        , toSF CompanyFT $ getCompanyName (user, mcompany)
        , toSF PersonalNumberFT $ getPersonalNumber user
        , toSF CompanyNumberFT $ getCompanyNumber (user, mcompany)
        ]
    , signatoryispartner = is_partner
    , signatoryisauthor = is_author
    }
    where
      toSF t v = SignatoryField
                 { sfType = t
                 , sfValue = v
                 , sfPlacements = []
                 , sfObligatory = True
                 , sfShouldBeFilledBySender = False
                 }


{- |
    Checks whether a signatory link is eligible for sending a reminder.
    The user must be the author, and the signatory musn't be the author.
    Also the signatory must be next in the signorder, and also not be a viewer.
    In addition the document must be in the correct state.  There's quite a lot to check!
-}
isEligibleForReminder :: User -> Document -> SignatoryLink -> Bool
isEligibleForReminder user document@Document{documentstatus} siglink =
       signatorylinkdeliverymethod siglink == EmailDelivery
    && signatoryActivated
    && userIsAuthor
    && not isUserSignator
    && not dontShowAnyReminder
    && invitationdeliverystatus siglink /= Undelivered
    && invitationdeliverystatus siglink /= Deferred
    && wasNotSigned
    && signatoryispartner (signatorydetails siglink)
  where
    userIsAuthor = isAuthor (document, user)
    isUserSignator = isSigLinkFor user siglink
    wasNotSigned = isNothing (maybesigninfo siglink)
    signatoryActivated = documentcurrentsignorder document >= signatorysignorder (signatorydetails siglink)
    dontShowAnyReminder = documentstatus `elem` [Timedout, Canceled, Rejected]

-- | Can author sign now according to sign order?
canAuthorSignNow :: Document -> Bool
canAuthorSignNow doc =
     isPending doc
  && documentcurrentsignorder doc >= signatorysignorder (signatorydetails author)
  && (not . hasSigned $ author)
  && isSignatory author
  where author = case getAuthorSigLink doc of
                   Just a -> a
                   _ -> error $ "Document " ++ show (documentid doc) ++ " does not have author"


-- Checks if signatory can sign now
canSignatorySignNow :: Document -> SignatoryLink -> Bool
canSignatorySignNow doc sl =
  isPending doc
  && documentcurrentsignorder doc >= signatorysignorder (signatorydetails sl)
  && (not . hasSigned $ sl)
  && isSignatory sl


-- Please define this better. Maybe in the positive?
{- |
   Is this document eligible for a reminder (depends on documentstatus)?
 -}
isDocumentEligibleForReminder :: Document -> Bool
isDocumentEligibleForReminder doc = not $ documentstatus doc `elem` [Timedout, Canceled, Rejected]

{- |
   Has the signatory's sign order come up?
 -}
isActivatedSignatory :: SignOrder -> SignatoryLink -> Bool
isActivatedSignatory signorder siglink =
  signorder >= signatorysignorder (signatorydetails siglink)

{- |
   Given a SignOrder and a SignatoryLink, determine whether the
   SignatoryLink is the next one up.
 -}
isCurrentSignatory :: SignOrder -> SignatoryLink -> Bool
isCurrentSignatory signorder siglink =
  signorder == signatorysignorder (signatorydetails siglink)

isFieldCustom :: SignatoryField -> Bool
isFieldCustom SignatoryField{sfType = CustomFT{}} = True
isFieldCustom _ = False

findCustomField :: HasFields a => String -> a -> Maybe SignatoryField
findCustomField name = find (matchingFieldType (CustomFT name False)) . getAllFields

getSignatoryAttachment :: Document -> SignatoryLinkID -> String -> Maybe SignatoryAttachment
getSignatoryAttachment doc slid name = join $ find (\a -> name == signatoryattachmentname a)
                                       <$> signatoryattachments
                                       <$> (find (\sl -> slid == signatorylinkid sl) $ documentsignatorylinks doc)

isAuthorAdmin :: User -> Document -> Bool
isAuthorAdmin user doc =
  useriscompanyadmin user && (getAuthorSigLink doc >>= maybesignatory) == Just (userid user)

documentfileM :: MonadDB m => Document -> m (Maybe File)
documentfileM = maybe (return Nothing) (dbQuery . GetFileByFileID) . documentfile

documentsealedfileM :: MonadDB m => Document -> m (Maybe File)
documentsealedfileM = maybe (return Nothing) (dbQuery . GetFileByFileID) . documentsealedfile

fileInDocument :: Document -> FileID -> Bool
fileInDocument doc fid =
    elem fid $      maybeToList (documentfile doc)
                 ++ maybeToList (documentsealedfile doc)
                 ++ (fmap authorattachmentfile $ documentauthorattachments doc)
                 ++ (catMaybes $ fmap signatoryattachmentfile $ concatMap signatoryattachments $ documentsignatorylinks doc)

filterPlacementsByID :: [(String, String, FieldPlacement)]
                        -> String
                        -> String
                        -> [FieldPlacement]
filterPlacementsByID placements sigid fieldid =
    [x | (s, f, x) <- placements, s == sigid, f == fieldid]

filterFieldDefsByID :: [(String, SignatoryField)]
                    -> String
                    -> [SignatoryField]
filterFieldDefsByID fielddefs sigid =
    [x | (s, x) <- fielddefs, s == sigid]

makeSignatory ::[(String, String, FieldPlacement)]
                -> [(String, SignatoryField)]
                -> String
                -> String
                -> String
                -> String
                -> String
                -> SignOrder
                -> Bool
                -> Bool
                -> String
                -> String
                -> String
                -> SignatoryDetails
makeSignatory pls fds sid sfn  ssn  se sm sso sauthor spartner sc  spn  scn = SignatoryDetails {
    signatorysignorder = sso
  , signatoryfields = [
      sf FirstNameFT sfn "fstname"
    , sf LastNameFT ssn "sndname"
    , sf EmailFT se "email"
    , sf MobileFT sm "mobile"
    , sf CompanyFT sc "company"
    , sf PersonalNumberFT spn "personalnumber"
    , sf CompanyNumberFT scn "companynumber"
    ] ++ filterFieldDefsByID fds sid
  , signatoryisauthor = sauthor
  , signatoryispartner = spartner
  }
  where
    sf ftype value texttype = SignatoryField {
        sfType = ftype
      , sfValue = value
      , sfPlacements = filterPlacementsByID pls sid texttype
      , sfObligatory = True
      , sfShouldBeFilledBySender = False
    }

documentDeletedForUser :: Document -> UserID -> Bool
documentDeletedForUser doc uid = fromMaybe False (fmap signatorylinkdeleted $ (getSigLinkFor doc uid `mplus` getAuthorSigLink doc))

documentReallyDeletedForUser :: Document -> UserID -> Bool
documentReallyDeletedForUser doc uid = fromMaybe False (fmap signatorylinkreallydeleted $ (getSigLinkFor doc uid `mplus` getAuthorSigLink doc))

userCanPerformSigningAction :: UserID -> Document  -> Bool
userCanPerformSigningAction uid doc =
      (isJust msl && (canSignatorySignNow doc sl))
   || (isJust msl && isAuthor sl && any (canSignatorySignNow doc &&^ ((== PadDelivery) . signatorylinkdeliverymethod)) (documentsignatorylinks doc))
  where
    msl = getSigLinkFor doc uid
    sl  = fromJust msl
