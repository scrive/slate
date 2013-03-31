{-# LANGUAGE NoImplicitPrelude #-}
module Doc.Action (
    postDocumentPreparationChange
  , postDocumentPendingChange
  , postDocumentRejectedChange
  , postDocumentCanceledChange
  , getCustomTextField
  , sendReminderEmail
  , sendInvitationEmail1
  , sendAllReminderEmails
  ) where

import Control.Applicative
import Control.Monad.Trans.Maybe
import Control.Monad.IO.Class
import Control.Logic
import Crypto.RNG
import Data.Char
import DB
import Utils.Monad
import Doc.DocSeal
import Doc.Model
import Doc.DocInfo
import Doc.DocStateData
import Doc.DocUtils
import Doc.DocView
import Doc.DocViewMail
import Doc.SignatoryLinkID
import Doc.DocumentID
import InputValidation
import File.Model
import File.Storage
import Kontra
import KontraLink
import Mails.SendMail
import OurPrelude
import User.Model
import Util.HasSomeUserInfo
import qualified Log
import Text.StringTemplates.Templates
import Util.Actor
import Util.SignatoryLinkUtils
import Util.MonadUtils
import Stats.Control
import ThirdPartyStats.Core
import ActionQueue.UserAccountRequest
import User.Action

import Control.Monad
import Data.List hiding (head, tail)
import Data.Maybe hiding (fromJust)
import qualified Data.ByteString as BS
import ForkAction
import Doc.API.Callback.Model

-- | Log a document event, adding some standard properties.
logDocEvent :: Kontrakcja m => EventName -> Document -> User -> [EventProperty] -> m ()
logDocEvent name doc user extraProps = do
  now <- getMinutesTime
  ip <- ctxipnumber <$> getContext
  let uid = userid user
      email = Email $ getEmail user
      fullname = getFullName user
  asyncLogEvent name $ extraProps ++ [
    UserIDProp uid,
    DocIDProp  (documentid doc),
    TimeProp   now,
    MailProp   email,
    IPProp     ip,
    NameProp   fullname,
    stringProp "Delivery" (show $ documentdeliverymethod doc),
    stringProp "Type" (show $ documenttype doc),
    stringProp "Language" (show $ documentlang doc),
    numProp "Days to sign" (fromIntegral $ documentdaystosign doc),
    numProp "Signatories" (fromIntegral $ length $ documentsignatorylinks doc),
    stringProp "Signup Method" (show $ usersignupmethod user)]

postDocumentPreparationChange :: Kontrakcja m => Document -> String -> m ()
postDocumentPreparationChange doc@Document{documenttitle} apistring = do
  let docid = documentid doc
  triggerAPICallbackIfThereIsOne doc
  unless (isPending doc) $
    stateMismatchError "postDocumentPreparationChange" Pending doc
  Log.docevent $ "Preparation -> Pending; Sending invitation emails: " ++ show docid
  ctx <- getContext
  msaveddoc <- saveDocumentForSignatories doc
  document' <- case msaveddoc of
    Left msg -> do
      Log.error $ "Failed to save document #" ++ (show docid) ++ " for signatories " ++ msg
      return doc
    Right saveddoc -> return saveddoc
  Log.server $ "Sending invitation emails for document #" ++ show docid ++ ": " ++ documenttitle

  -- Stat logging
  now <- getMinutesTime
  author <- getDocAuthor doc
  -- Log the current time as the last doc sent time
  asyncLogEvent SetUserProps [UserIDProp (userid author),
                              someProp "Last Doc Sent" now]
  json <- documentJSON False True False Nothing Nothing doc
  asyncLogEvent (UploadDocInfo json) [UserIDProp (userid author),
                                      DocIDProp (documentid doc)]
  logDocEvent "Doc Sent" doc author []

  edoc <- if (sendMailsDuringSigning document')
             then sendInvitationEmails ctx document'
             else return $ Right $ document'
  case edoc of
    Left _ -> do
      _ <- addDocumentSendStatEvents (documentid document') apistring
      forM_ (documentsignatorylinks document') $ \sl ->
        addSignStatInviteEvent document' sl (ctxtime ctx)
    Right doc2 -> do
      _ <- addDocumentSendStatEvents (documentid doc2) apistring
      forM_ (documentsignatorylinks doc2) $ \sl ->
        addSignStatInviteEvent doc2 sl (ctxtime ctx)

postDocumentPendingChange :: Kontrakcja m => Document -> Document -> String -> m ()
postDocumentPendingChange doc@Document{documentid, documenttitle} olddoc apistring = do
  triggerAPICallbackIfThereIsOne doc
  unless (isPending doc) $
    stateMismatchError "postDocumentPendingChange" Pending doc
  case undefined of
    _ | allSignatoriesSigned doc -> do
      Log.docevent $ "All have signed; " ++ show documentstatus ++ " -> Closed: " ++ show documentid
      ctx <- getContext
      let time = ctxtime ctx
      dbUpdate $ CloseDocument documentid (systemActor time)
      Just closeddoc <- dbQuery $ GetDocumentByDocumentID documentid

      Log.docevent $ "Pending -> Closed; Sending emails: " ++ show documentid
      _ <- addDocumentCloseStatEvents documentid apistring
      author <- getDocAuthor doc
      logDocEvent "Doc Closed" doc author []
      asyncLogEvent SetUserProps [UserIDProp (userid author),
                                  someProp "Last Doc Closed" time]
      kCommit
      forkAction ("Sealing document #" ++ show documentid ++ ": " ++ documenttitle) $ do
        enewdoc <- sealDocument closeddoc
        case enewdoc of
          Right newdoc -> sendClosedEmails newdoc
          Left errmsg -> do
            _ <- dbUpdate $ ErrorDocument documentid errmsg (systemActor time)
            Log.server $ "Sending seal error emails for document #" ++ show documentid ++ ": " ++ documenttitle
            sendDocumentErrorEmail closeddoc author
        return ()
    _ -> when (documentcurrentsignorder doc /= documentcurrentsignorder olddoc) $ do
      ctx <- getContext
      Log.server $ "Resending invitation emails for document #" ++ show documentid ++ ": " ++ documenttitle
      when_ (sendMailsDuringSigning doc) $
          sendInvitationEmails ctx doc
      return ()
  where
    allSignatoriesSigned = all (isSignatory =>>^ hasSigned) . documentsignatorylinks

postDocumentRejectedChange :: Kontrakcja m => Document -> SignatoryLinkID -> String -> m ()
postDocumentRejectedChange doc@Document{..} siglinkid apistring = do
  triggerAPICallbackIfThereIsOne doc
  unless (isRejected doc) $
    stateMismatchError "postDocumentRejectedChange" Rejected doc
  Log.docevent $ "Pending -> Rejected; send reject emails: " ++ show documentid
  _ <- addDocumentRejectStatEvents documentid apistring
  Log.server $ "Sending rejection emails for document #" ++ show documentid ++ ": " ++ documenttitle
  ctx <- getContext
  -- Log the fact that the current user rejected a document.
  maybe (return ())
        (\user -> logDocEvent "Doc Rejected" doc user [])
        (ctxmaybeuser ctx)
  customMessage <- getCustomTextField "customtext"
  when_ (sendMailsDuringSigning doc) $
    sendRejectEmails customMessage ctx doc ($(fromJust) $ getSigLinkFor doc siglinkid)
  return ()

postDocumentCanceledChange :: Kontrakcja m => Document -> String -> m ()
postDocumentCanceledChange doc@Document{..} apistring = do
  triggerAPICallbackIfThereIsOne doc
  unless (isCanceled doc) $
    stateMismatchError "postDocumentCanceledChange" Canceled doc
  Log.docevent $ "Pending -> Canceled (ElegDataMismatch); Sending cancelation emails: " ++ show documentid
  _ <- addDocumentCancelStatEvents documentid apistring
  -- if canceled because of ElegDataMismatch, send out emails
  author <- getDocAuthor doc
  let f sl = do
        msg <- signatorylinkelegdatamismatchmessage sl
        fn <- signatorylinkelegdatamismatchfirstname sl
        ln <- signatorylinkelegdatamismatchlastname sl
        pno <- signatorylinkelegdatamismatchpersonalnumber sl
        return (msg,fn,ln,pno)
  let issues = (catMaybes (map f (documentsignatorylinks)))
  mapM_ (\r -> logDocEvent "Doc Canceled" doc author [reasonProp r]) issues

  when (not (null issues)) $ do
      ctx <- getContext
      Log.server $ "Sending cancelation emails for document #" ++ show documentid ++ ": " ++ documenttitle
      sendElegDataMismatchEmails ctx doc author
  where
    reasonProp = stringProp "Reason" . show

stateMismatchError :: Kontrakcja m => String -> DocumentStatus -> Document -> m a
stateMismatchError funame expected Document{documentstatus, documentid} = do
  Log.debug $ funame ++ ": document #" ++ show documentid ++ " in " ++ show documentstatus ++ " state, expected " ++ show expected
  internalError

getDocAuthor :: Kontrakcja m => Document -> m User
getDocAuthor doc = do
  authorid <- guardJust $ getAuthorSigLink doc >>= maybesignatory
  guardJustM $ dbQuery $ GetUserByID authorid

{- |
    Goes through each signatory, and if a user exists this saves it for that user
    by linking the signatory to the user's account.
-}
saveDocumentForSignatories :: Kontrakcja m => Document -> m (Either String Document)
saveDocumentForSignatories doc@Document{documentsignatorylinks} =
  foldM foldSaveForSig (Right doc) . filter (not . isAuthor) $ documentsignatorylinks
  where
    {- |
        Wraps up the saveDocumentForSignatory so we can use it in a fold
    -}
    foldSaveForSig :: Kontrakcja m => (Either String Document) -> SignatoryLink -> m (Either String Document)
    foldSaveForSig (Left msg) _ = return $ Left msg
    foldSaveForSig (Right doc') siglink = saveDocumentForSignatory doc' siglink
    {- |
        Saves the document for the given signatorylink.  It does this by checking to see
        if there is a user with a matching email, and if there is it hooks up the signatory
        link to that user.
    -}
    saveDocumentForSignatory :: Kontrakcja m => Document -> SignatoryLink -> m (Either String Document)
    saveDocumentForSignatory doc'@Document{documentid}
                             SignatoryLink{signatorylinkid,signatorydetails} = do
      let sigemail = getEmail signatorydetails
      muser <- case (sigemail) of
                "" -> return Nothing
                _  -> dbQuery $ GetUserByEmail (Email sigemail)
      case muser of
        Nothing -> return $ Right doc'
        Just user -> do
          Context{ctxtime, ctxipnumber} <- getContext
          let actor = signatoryActor ctxtime ctxipnumber (Just $ userid user) sigemail signatorylinkid
          udoc <- do
            mdoc <- runMaybeT $ do
              True <- dbUpdate $ SaveDocumentForUser documentid user signatorylinkid actor
              Just newdoc <- dbQuery $ GetDocumentByDocumentID documentid
              return newdoc
            return $ maybe (Left "saveDocumentForSignatory failed") Right mdoc
          return udoc

-- EMAILS

sendElegDataMismatchEmails :: Kontrakcja m => Context -> Document -> User -> m ()
sendElegDataMismatchEmails ctx document author = do
    let signlinks = [sl | sl <- documentsignatorylinks document
                        , isActivatedSignatory (documentcurrentsignorder document) sl
                        , not $ isAuthor sl]
        badsig = $(fromJust) $ find (isJust . signatorylinkelegdatamismatchmessage) (documentsignatorylinks document)
        msg = $(fromJust) $ signatorylinkelegdatamismatchmessage badsig
        badname  = getFullName badsig
        bademail = getEmail badsig
    forM_ signlinks $ sendDataMismatchEmailSignatory ctx document (signatorylinkid badsig) badname msg
    sendDataMismatchEmailAuthor ctx document author (lines msg) badname bademail

sendDataMismatchEmailSignatory :: Kontrakcja m => Context -> Document -> SignatoryLinkID -> String -> String -> SignatoryLink -> m ()
sendDataMismatchEmailSignatory ctx document badid badname msg signatorylink = do
    let SignatoryLink { signatorylinkid, signatorydetails = sigdets } = signatorylink
        isbad = badid == signatorylinkid
    case getAuthorSigLink document of
      Nothing -> error "No author in Document"
      Just authorsl -> do
        mail <- mailMismatchSignatory
                ctx
                document
                (getEmail authorsl)
                (getFullName authorsl)
                (ctxhostpart ctx ++ (show $ LinkSignDoc document signatorylink))
                (getFullName signatorylink)
                badname
                msg
                isbad
        scheduleEmailSendout (ctxmailsconfig ctx) $ mail { to = [getMailAddress sigdets]}

sendDataMismatchEmailAuthor :: Kontrakcja m => Context -> Document -> User -> [String] -> String -> String -> m ()
sendDataMismatchEmailAuthor ctx document author messages badname bademail = do
    let authorname = getFullName $ $(fromJust) $ getAuthorSigLink document
        authoremail = getEmail $ $(fromJust) $ getAuthorSigLink document
    mail <- mailMismatchAuthor ctx document authorname messages badname bademail (getLang author)
    scheduleEmailSendout (ctxmailsconfig ctx) $ mail { to = [MailAddress {fullname = authorname, email = authoremail }]}

{- |
   Send emails to all of the invited parties saying that we fucked up the process.
   Say sorry about this to them.
   ??: Should this be in DocControl or in an email-sepecific file?
 -}
sendDocumentErrorEmail :: (CryptoRNG m, KontraMonad m , MonadDB m, TemplatesMonad m) => Document -> User -> m ()
sendDocumentErrorEmail document author = do
  let signlinks = documentsignatorylinks document
  forM_ signlinks (\sl -> if isAuthor sl
                            then sendDocumentErrorEmailToAuthor
                            else sendDocumentErrorEmailToSignatory sl)
  where
    sendDocumentErrorEmailToAuthor = do
      ctx <- getContext
      let authorlink = $(fromJust) $ getAuthorSigLink document
      mail <- mailDocumentErrorForAuthor ctx document (getLang author)
      scheduleEmailSendout (ctxmailsconfig ctx) $ mail {
          to = [getMailAddress authorlink]
      }
    -- | Helper function to send emails to invited parties
    -- ??: Should this be in DocControl or in an email-specific file?
    sendDocumentErrorEmailToSignatory signatorylink = do
      ctx <- getContext
      let SignatoryLink { signatorylinkid
                        , signatorydetails } = signatorylink
          Document { documentid } = document
      mail <- mailDocumentErrorForSignatory ctx document
      scheduleEmailSendout (ctxmailsconfig ctx) $ mail {
            to = [getMailAddress signatorydetails]
          , mailInfo = Invitation documentid  signatorylinkid
      }

{- |
   Send emails to all of the invited parties.
   ??: Should this be in DocControl or in an email-sepecific file?
 -}
sendInvitationEmails :: Kontrakcja m => Context -> Document -> m (Either String Document)
sendInvitationEmails ctx document = do
  let signlinks = [sl | sl <- documentsignatorylinks document
                      , isCurrentSignatory (documentcurrentsignorder document) sl
                      , not $ hasSigned sl]
  case signlinks of
    [] -> return $ Left $ "Document " ++ show (documentid document) ++ " has no signatories. Cannot send invitation emails."
    _ -> do
      edocs <- forM signlinks (sendInvitationEmail1 ctx document)
      return $ msum edocs


{- |
   Helper function to send emails to invited parties
   ??: Should this be in DocControl or in an email-specific file?
 -}
sendInvitationEmail1 :: Kontrakcja m => Context -> Document -> SignatoryLink -> m (Either String Document)
sendInvitationEmail1 ctx document signatorylink | not (isAuthor signatorylink) = do
  -- send invitation to sign to invited person
  let SignatoryLink { signatorylinkid
                    , signatorydetails } = signatorylink
      Document { documentid } = document
  mail <- mailInvitation True ctx (Sign <| isSignatory signatorylink |> View) document (Just signatorylink) False
  -- ?? Do we need to read in the contents? -EN
  -- _attachmentcontent <- liftIO $ documentFileID document >>= getFileContents ctx
  scheduleEmailSendout (ctxmailsconfig ctx) $
    mail { to = [getMailAddress signatorydetails]
         , mailInfo = Invitation documentid signatorylinkid
         }
  mdoc <- runMaybeT $ do
    True <- dbUpdate $ AddInvitationEvidence documentid signatorylinkid (Just (documentinvitetext document) <|documentinvitetext document /= "" |> Nothing) $ systemActor $ ctxtime ctx
    Just doc <- dbQuery $ GetDocumentByDocumentID documentid
    return doc
  return $ maybe (Left "sendInvitationEmail1 failed") Right mdoc

sendInvitationEmail1 ctx document authorsiglink =
  if (isSignatory authorsiglink)
     then do
        -- send invitation to sign to author when it is his turn to sign
        mail <- mailDocumentAwaitingForAuthor ctx document $ getLang document
        scheduleEmailSendout (ctxmailsconfig ctx) $
          mail { to = [getMailAddress authorsiglink] }
        return $ Right document
     else return $ Right document
{- |
    Send a reminder email (and update the modification time on the document)
-}
sendReminderEmail :: Kontrakcja m => Maybe String -> Context -> Actor -> Document -> SignatoryLink -> m SignatoryLink
sendReminderEmail custommessage ctx actor doc siglink = do
  mail <- mailDocumentRemind custommessage ctx doc siglink False
  mailattachments <- makeMailAttachments doc
  scheduleEmailSendout (ctxmailsconfig ctx) $ mail {
      to = [getMailAddress siglink]
    , mailInfo = Invitation (documentid doc) (signatorylinkid siglink)
    , attachments = if isJust $ maybesigninfo siglink
                      then mailattachments
                      else []
    }
  when (isPending doc &&  not (hasSigned siglink)) $ do
    Log.debug $ "Reminder mail send for signatory that has not signed " ++ show (signatorylinkid siglink)
    dbUpdate $ PostReminderSend doc siglink custommessage actor
  _ <- dbUpdate $ SetDocumentModificationDate (documentid doc) (ctxtime ctx)
  triggerAPICallbackIfThereIsOne doc
  return siglink

{- |
   Send emails to all parties when a document is closed.
 -}
sendClosedEmails :: (CryptoRNG m, KontraMonad m, MonadDB m, TemplatesMonad m) => Document -> m ()
sendClosedEmails document = do
    ctx <- getContext
    mailattachments <- makeMailAttachments document
    let signatorylinks = documentsignatorylinks document
    forM_ signatorylinks $ \sl -> do
      ml <- handlePostSignSignup (Email $ getEmail sl) (getFirstName sl) (getLastName sl)
      mail <- mailDocumentClosed ctx document ml sl
      scheduleEmailSendout (ctxmailsconfig ctx) $
        mail { to = [getMailAddress sl]
             , attachments = mailattachments
             }

makeMailAttachments :: (KontraMonad m, MonadDB m, MonadIO m) => Document -> m [(String, BS.ByteString)]
makeMailAttachments document = do
  let mainfile = documentsealedfile document `mplus` documentfile document
  let
      aattachments = map authorattachmentfile $ documentauthorattachments document
      sattachments = concatMap (maybeToList . signatoryattachmentfile) $ concatMap signatoryattachments $ documentsignatorylinks document
      allfiles' = maybeToList mainfile ++ aattachments ++ sattachments
  allfiles <- catMaybes `liftM` mapM (dbQuery . GetFileByFileID) allfiles'
  let dropPDFSuffix name | ".pdf" `isSuffixOf` (map toLower name) = reverse . drop 4 $ reverse name
                         | otherwise = name
  --use the doc title rather than file name for the main file (see jira #1152)
  let filenames = map dropPDFSuffix $ documenttitle document : map filename ($(tail) allfiles)

  filecontents <- mapM getFileContents allfiles
  return $ zip filenames filecontents

{- |
   Send an email to the author and to all signatories who were sent an invitation  when the document is rejected
 -}
sendRejectEmails :: Kontrakcja m => Maybe String -> Context -> Document -> SignatoryLink -> m ()
sendRejectEmails customMessage ctx document signalink = do
  let activatedSignatories = [sl | sl <- documentsignatorylinks document
                                 , isActivatedSignatory (documentcurrentsignorder document) sl || isAuthor sl]
  forM_ activatedSignatories $ \sl -> do
    mail <- mailDocumentRejected customMessage ctx document signalink False
    scheduleEmailSendout (ctxmailsconfig ctx) $ mail {
      to = [getMailAddress sl]
    }

{- |
   Send reminder to all parties in document. No custom text
 -}
sendAllReminderEmails :: Kontrakcja m => Context -> Actor -> User -> DocumentID -> m [SignatoryLink]
sendAllReminderEmails ctx actor user docid = do
    doc <- guardJustM $ dbQuery $ GetDocumentByDocumentID docid
    case (documentstatus doc) of
          Pending -> do
            let isEligible = isEligibleForReminder user doc
                unsignedsiglinks = filter isEligible $ documentsignatorylinks doc
            sequence . map (sendReminderEmail Nothing ctx actor doc) $ unsignedsiglinks
          _ -> return []

{- |
    If the custom text field is empty then that's okay, but if it's invalid
    then we want to fail.
-}
getCustomTextField :: Kontrakcja m => String -> m (Maybe String)
getCustomTextField = getValidateAndHandle asValidInviteText customTextHandler
    where
    customTextHandler textresult =
        logIfBad textresult
            >>= flashValidationMessage
            >>= withFailureIfBad

{- |
   Try to sign up a new user. Returns the confirmation link for the new user.
   Nothing means there is already an account or there was an error creating the user.
 -}
handlePostSignSignup :: (CryptoRNG m, KontraMonad m, MonadDB m, TemplatesMonad m) => Email -> String -> String -> m (Maybe KontraLink)
handlePostSignSignup email fn ln = do
  ctx <- getContext
  let lang = ctxlang ctx
  muser <- dbQuery $ GetUserByEmail email
  case (muser, muser >>= userhasacceptedtermsofservice) of
    (Just user, Nothing) -> do
      -- there is an existing user that hasn't been activated
      -- return the existing link
      l <- newUserAccountRequestLink lang (userid user) BySigning
      return $ Just l
    (Nothing, Nothing) -> do
      -- this email address is new to the system, so create the user
      -- and send an invite
      mnewuser <- createUser email (fn, ln) Nothing lang
      case mnewuser of
        Nothing -> return Nothing
        Just newuser -> do
          l <- newUserAccountRequestLink lang (userid newuser) BySigning
          return $ Just l
    (_, _) -> return Nothing

