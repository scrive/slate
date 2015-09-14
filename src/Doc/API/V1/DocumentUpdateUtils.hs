{-# LANGUAGE ExtendedDefaultRules #-}
{-# OPTIONS_GHC -fno-warn-orphans #-}
module Doc.API.V1.DocumentUpdateUtils (
    applyDraftDataToDocument,
    draftIsChangingDocument
  ) where

import Control.Conditional (whenM, unlessM)
import Data.Functor
import Log
import qualified Control.Exception.Lifted as E
import Control.Monad.Catch

import API.Monad.V1 (serverError,badInput)
import DB
import DB.TimeZoneName
import Doc.DocInfo (isPreparation)
import Doc.DocStateData
import Doc.DocumentMonad (DocumentMonad, theDocument)
import Doc.DocUtils
import Doc.Model
import Doc.SignatoryFieldID
import Doc.SignatoryLinkID
import Kontra
import KontraPrelude
import Util.Actor
import Util.HasSomeUserInfo
import Util.SignatoryLinkUtils
import Utils.Monad

checkDraftTimeZoneName ::  (Kontrakcja m) =>  Document -> m ()
checkDraftTimeZoneName draft = do
  void $  (mkTimeZoneName $ toString (documenttimezonename draft))
    `E.catch` (\(_::E.SomeException) ->  throwM $ SomeKontraException $ badInput "Timezone name is invalid.")

applyDraftDataToDocument :: (Kontrakcja m, DocumentMonad m) =>  Document -> Actor -> m ()
applyDraftDataToDocument draft actor = do
    checkDraftTimeZoneName draft
    unlessM (isPreparation <$> theDocument) $ do
      theDocument >>= \doc -> logAttention "Document is not in preparation" $ object [
          "status" .= show (documentstatus doc)
        ]
      throwM $ SomeKontraException $ serverError "applyDraftDataToDocument failed"
    _ <- theDocument >>= \doc -> dbUpdate $ UpdateDraft doc{
                                  documenttitle = documenttitle draft
                                , documentinvitetext = documentinvitetext draft
                                , documentconfirmtext = documentconfirmtext draft
                                , documentdaystosign = documentdaystosign draft
                                , documentdaystoremind = documentdaystoremind draft
                                , documentshowheader = documentshowheader draft
                                , documentshowpdfdownload = documentshowpdfdownload draft
                                , documentshowrejectoption = documentshowrejectoption draft
                                , documentshowfooter = documentshowfooter draft
                                , documentlang = documentlang draft
                                , documenttags = documenttags draft
                                , documentapiv1callbackurl = documentapiv1callbackurl draft
                                , documenttimezonename = documenttimezonename draft
                                } actor
    -- Only allow transition from 'unsaveddraft: true' to 'unsaveddraft: false'
    whenM ((\doc -> (documentunsaveddraft doc) && not (documentunsaveddraft draft)) <$> theDocument) $ do
         dbUpdate $ SetDocumentUnsavedDraft False
    whenM ((\doc -> isTemplate draft && (not $ isTemplate doc)) <$> theDocument) $ do
         dbUpdate $ TemplateFromDocument actor
    documentauthorattachments <$> theDocument >>= \atts -> forM_ atts $ \att -> do
            when_ (not $ (authorattachmentfileid att) `elem` (authorattachmentfileid <$> documentauthorattachments draft)) $ do -- We need to compare fileid - since name is not parsed in V1
              dbUpdate $ RemoveDocumentAttachment (authorattachmentfileid att) actor
    documentsignatorylinks <$> theDocument >>= \siglinks -> case (mergeAuthorDetails siglinks (sortBy compareSL $ documentsignatorylinks draft)) of
         Nothing   -> throwM $ SomeKontraException $ serverError "Problem with author details while sending draft"
         Just sigs -> do
           -- Checking if some integrations depend on fact that we don't change fstname and lastname for author. To be removed till 20. II.
           let  (Just oldAuthor) = find isAuthor $ documentsignatorylinks $ draft
           let  (Just newAuthor) = find isAuthor sigs
           when (getFirstName oldAuthor /= getFirstName newAuthor || getLastName oldAuthor /= getLastName newAuthor) $ do
            logInfo "Checkup: Update could change author details" $ object [
                "details" .= getFullName oldAuthor
              , "new_details" .= getFullName newAuthor
              ]
           -- End testing

           res <- dbUpdate $ ResetSignatoryDetails (sortBy compareSL $ sigs) actor
           unless res $ throwM $ SomeKontraException $ serverError "applyDraftDataToDocument failed"


compareSL :: SignatoryLink -> SignatoryLink -> Ordering
compareSL s1 s2 | signatoryisauthor s1 = LT
                | signatoryisauthor s2 = GT
                | signatorylinkid s2 == unsafeSignatoryLinkID 0 = LT
                | signatorylinkid s1 == unsafeSignatoryLinkID 0 = GT
                | otherwise = compare (signatorylinkid s1) (signatorylinkid s2)




mergeAuthorDetails :: [SignatoryLink] ->[SignatoryLink] -> Maybe [SignatoryLink]
mergeAuthorDetails sigs nsigs =
          let
            (nasig', nsigs') = partition isAuthor nsigs
            (asig, _) = partition isAuthor sigs
            setConstantDetails a =  (\s -> s {signatoryfields = replaceName1 (getFirstName a) $ signatoryfields s}) .
                                    (\s -> s {signatoryfields = replaceName2 (getLastName a) $ signatoryfields s}) .
                                    (\s -> s {signatoryfields = replaceEmail (getEmail a) $ signatoryfields s}) .
                                    (\s -> s {maybesignatory = maybesignatory a}) .  -- We need to be sure that we will not disconnect author
                                    (\s -> s {signatorylinkid = signatorylinkid a})  -- And we try to keep original id of author signatory

            replaceName1 a [] = [SignatoryNameField $ NameField {
              snfID = unsafeSignatoryFieldID 0,
              snfValue = a,
              snfNameOrder = NameOrder 1,
              snfPlacements =[],
              snfObligatory = True,
              snfShouldBeFilledBySender = False
            }]
            replaceName1 a ((SignatoryNameField nf@(NameField {snfNameOrder = NameOrder 1})):fs) = ((SignatoryNameField $ nf {snfValue = a}):fs)
            replaceName1 a (f:fs) = f:(replaceName1 a fs)

            replaceName2 a [] = [SignatoryNameField $ NameField {
              snfID = unsafeSignatoryFieldID 0,
              snfValue = a,
              snfNameOrder = NameOrder 2,
              snfPlacements =[],
              snfObligatory = True,
              snfShouldBeFilledBySender = False
            }]
            replaceName2 a ((SignatoryNameField nf@(NameField {snfNameOrder = NameOrder 2})):fs) = ((SignatoryNameField $ nf {snfValue = a}):fs)
            replaceName2 a (f:fs) = f:(replaceName2 a fs)

            replaceEmail a [] = [SignatoryEmailField $ EmailField {
              sefID = unsafeSignatoryFieldID 0,
              sefValue = a,
              sefPlacements =[],
              sefObligatory = True,
              sefShouldBeFilledBySender = False
            }]
            replaceEmail a ((SignatoryEmailField ef):fs) = ((SignatoryEmailField $ ef {sefValue = a}):fs)
            replaceEmail a (f:fs) = f:(replaceEmail a fs)

          in case (asig, nasig') of
               ([asig'], [nasig'']) -> Just $ (setConstantDetails asig' nasig'') : nsigs'
               _ -> Nothing


-- TODO can't we refactor this to take a list of documenttitle, documentinvitetext etc?
draftIsChangingDocument :: Document -> Document -> Bool
draftIsChangingDocument draft doc =
        (documenttitle draft /= documenttitle doc)
     || (documentinvitetext draft /= documentinvitetext doc)
     || (documentlang draft /= documentlang doc)
     || (documenttags draft /= documenttags doc)
     || (documentapiv1callbackurl draft /= documentapiv1callbackurl doc)
     || (isTemplate draft /= isTemplate doc)
     || (documentdaystosign draft /= documentdaystosign doc)
     || (documentdaystoremind draft /= documentdaystoremind doc)
     || (documentshowheader draft /= documentshowheader doc)
     || (documentshowpdfdownload draft /= documentshowpdfdownload doc)
     || (documentshowrejectoption draft /= documentshowrejectoption doc)
     || (documentshowfooter draft /= documentshowfooter doc)
     || (documenttimezonename draft /= documenttimezonename doc)
     || (draftIsChangingDocumentSignatories (documentsignatorylinks draft) (documentsignatorylinks doc))
     || (documentunsaveddraft draft /= documentunsaveddraft doc)

draftIsChangingDocumentSignatories :: [SignatoryLink] -> [SignatoryLink] -> Bool
draftIsChangingDocumentSignatories (sl':sls') (sl:sls) = (newSignatorySignatoryLinkIsChangingSignatoryLink sl' sl) || (draftIsChangingDocumentSignatories sls' sls)
draftIsChangingDocumentSignatories [] [] = False
draftIsChangingDocumentSignatories _ _ = True


newSignatorySignatoryLinkIsChangingSignatoryLink :: SignatoryLink -> SignatoryLink -> Bool
newSignatorySignatoryLinkIsChangingSignatoryLink newsl sl =
        (signatorylinkid newsl /= signatorylinkid sl)
     || (not $ fieldsListsAreAlmoustEqual (signatoryfields newsl) (signatoryfields sl))
     || (signatoryisauthor newsl /= signatoryisauthor sl)
     || (signatoryispartner newsl /= signatoryispartner sl)
     || (signatorysignorder newsl /= signatorysignorder sl)
     || (signatoryattachments newsl /= signatoryattachments sl)
     || (signatorylinkcsvupload newsl /= signatorylinkcsvupload sl)
     || (signatorylinksignredirecturl newsl /= signatorylinksignredirecturl sl)
     || (signatorylinkauthenticationtoviewmethod newsl /= signatorylinkauthenticationtoviewmethod sl)
     || (signatorylinkauthenticationtosignmethod newsl /= signatorylinkauthenticationtosignmethod sl)
     || (signatorylinkdeliverymethod newsl /= signatorylinkdeliverymethod sl)
