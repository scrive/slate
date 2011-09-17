module ELegitimation.BankID
    ( handleSignBankID
    , handleSignPostBankID
    , handleIssueBankID
    , handleIssuePostBankID
    , handleSignCanceledDataMismatch
    )
    where

import Redirect
import AppView
import qualified AppLogger as Log
import Control.Monad.State
import Data.List
import Data.Maybe
import DB.Types
import DB.Classes
import Doc.DocControl
import Doc.DocState
import Doc.DocUtils
import Doc.DocView
import ELegitimation.ELeg
import Happstack.Server
import Happstack.State
import Kontra
import KontraLink
import MinutesTime
import Misc
import SOAP.SOAP
import Templates.Templates
import Text.XML.HaXml.Posn (Posn)
import Text.XML.HaXml.XmlContent.Parser
import User.Model
import User.UserControl
import qualified Data.ByteString as BS
import qualified Data.ByteString.UTF8 as BS hiding (length, drop, break)
import GHC.Word
import GHC.Unicode (toLower)
import Data.Either (lefts, rights)
import Util.FlashUtil
import Util.HasSomeCompanyInfo
import Util.HasSomeUserInfo
import Util.SignatoryLinkUtils
import Util.MonadUtils
import Doc.DocStateQuery

import Util.StringUtil

{- |
   Handle the Ajax request for initiating a BankID transaction.
   URL: /s/{provider}/{docid}/{signid}/{magic}
   Method: GET
 -}
handleSignBankID :: Kontrakcja m => String -> DocumentID -> SignatoryLinkID -> MagicHash -> m Response
handleSignBankID provider docid signid magic = do
    Context{ctxtime} <- getContext
    let seconds = toSeconds ctxtime 

    -- sanity check
    document <- guardRightM $ getDocByDocIDSigLinkIDAndMagicHash docid signid magic

    unless (document `allowsIdentification` ELegitimationIdentification) mzero
    -- request a nonce
    providerCode <- providerStringToNumber provider
    nonceresponse <- generateChallenge providerCode
    case nonceresponse of
        Left (ImplStatus _a _b code msg) -> do
            Log.eleg $ "generateChallenge failed: " ++ toJSON [("status", JInt code), ("msg", JString msg)]
            return $ toResponse $ toJSON [("status", JInt code), ("msg", JString msg)]
        Right (nonce, transactionid) -> do
            -- encode the text to be signed
            tbs <- getTBS document
            encodetbsresponse <- encodeTBS providerCode tbs transactionid
            case encodetbsresponse of
                Left (ImplStatus _a _b code msg) -> do
                    Log.eleg $ "encodeTBS failed: " ++ toJSON [("status", JInt code), ("msg", JString msg)]
                    return $ toResponse $ toJSON [("status", JInt code), ("msg", JString msg)]
                Right txt -> do
                    -- store in session
                    addELegTransaction ELegTransaction
                                            { transactionservertime = ctxtime
                                            , transactiontransactionid = transactionid
                                            , transactiontbs = tbs
                                            , transactionencodedtbs = txt
                                            , transactionsignatorylinkid = Just signid
                                            , transactiondocumentid = docid
                                            , transactionmagichash = Just magic
                                            , transactionnonce = nonce
                                            }
                    Log.eleg $ "encoding successful: " ++
                        toJSON [("status", JInt 0)
                            ,("servertime", JString $ show seconds)
                            ,("nonce", JString nonce)
                            ,("tbs", JString txt)
                            ,("transactionid", JString transactionid)
                            ,("docid", JString $ show $ unDocumentID docid)
                            ,("siglinkid", JString $ show $ unSignatoryLinkID signid)]
                    return $ toResponse $ toJSON [("status", JInt 0)
                                                 ,("servertime", JString $ show seconds)
                                                 ,("nonce", JString nonce)
                                                 ,("tbs", JString txt)
                                                 ,("transactionid", JString transactionid)]

{- |
   Handle POST when invitee wants to sign with BankID
   URL: /s/{docid}/{sigid}/{magic}
   Method: POST
   params
     provider -- the eleg provider (bankid, nordea, telia)
     signature -- signature generated by BankID plugin
     transactionid -- the id of the transaction from the BankID Ajax request
     fieldname -- zero or more names of fields filled out by author
     fieldvalues -- zero or more (same as # of fieldnames) of values filled out by author
 -}
handleSignPostBankID :: Kontrakcja m => DocumentID -> SignatoryLinkID -> MagicHash -> m KontraLink
handleSignPostBankID docid signid magic = do
    Context { ctxelegtransactions
            , ctxtime
            , ctxipnumber } <- getContext
    -- POST values
    provider      <- getDataFnM $ look "eleg"
    signature     <- getDataFnM $ look "signature"
    transactionid <- getDataFnM $ look "transactionid"
    fieldnames    <- getAndConcat "fieldname"
    fieldvalues   <- getAndConcat "fieldvalue"

    -- request validation
    document <- guardRightM $ getDocByDocIDSigLinkIDAndMagicHash docid signid magic

    unless (document `allowsIdentification` ELegitimationIdentification) mzero
    siglink <- guardJust $ getSigLinkFor document signid

    -- valid transaction?
    ELegTransaction { transactionsignatorylinkid = mtsignid
                    , transactionmagichash       = mtmagic
                    , transactiondocumentid      = tdocid
                    , transactiontbs
                    , transactionencodedtbs
                    , transactionnonce
                    } <- findTransactionByIDOrFail ctxelegtransactions transactionid

    guard (tdocid   == docid      )
    guard (mtsignid == Just signid)
    guard (mtmagic  == Just magic )
    -- end validation
    Log.eleg $ "Successfully found eleg transaction: " ++ show transactionid
    providerCode <- providerStringToNumber provider
    -- send signature to ELeg
    res <- verifySignature providerCode
                transactionencodedtbs
                signature
                (if providerCode == 6
                    then Just transactionnonce
                    else Nothing)
                transactionid
    case res of
        -- error state
        Left (ImplStatus _a _b code msg) -> do
            Log.eleg $ "verifySignature failed: " ++ toJSON [("status", JInt code), ("msg", JString msg), ("provider", JInt providerCode), ("sig", JString signature)]
            addFlash (OperationFailed, "E-legitimationstjänsten misslyckades att verifiera din signatur")
            return $ LinkSignDoc document siglink
        -- successful request
        Right (cert, attrs) -> do
            Log.eleg $ "Successfully identified using eleg. (Omitting private information)."
            providerType <- providerStringToType provider
            let fields = zip fieldnames fieldvalues
            -- compare information from document (and fields) to that obtained from BankID
            let contractFirst  = getFirstName siglink
                contractLast   = getLastName siglink
                contractNumber = getPersonalNumber siglink

                elegFirst  = fieldvaluebyid (BS.fromString "Subject.GivenName")    attrs
                elegLast   = fieldvaluebyid (BS.fromString "Subject.Surname")      attrs
                elegNumber = fieldvaluebyid (BS.fromString "Subject.SerialNumber") attrs

                mfinal = mergeInfo
                            (contractFirst, contractLast, contractNumber)
                            (elegFirst,     elegLast,     elegNumber)
            case mfinal of
                -- either number or name do not match
                Left (msg, sfn, sln, spn) -> do
                    let Just authorsiglink = getAuthorSigLink document
                        authorname = getSmartName authorsiglink
                        authoremail = getEmail authorsiglink
                    Log.eleg $ "Information from eleg did not match information stored for signatory in document." ++ show msg
                    txt <- renderTemplateFM "signCanceledDataMismatchModal" $ do
                        field "authorname"  authorname
                        field "authoremail" authoremail
                        field "message"     $ concat $ map para $ lines msg
                    -- send to canceled with reason msg
                    addFlash (Modal, txt)
                    Right newdoc <- update $ CancelDocument docid (ELegDataMismatch msg signid sfn sln spn) ctxtime ctxipnumber
                    postDocumentChangeAction newdoc document (Just signid)

                    return $ LinkSignDoc document siglink
                -- we have merged the info!
                Right (bfn, bln, bpn) -> do
                    Log.eleg $ "Successfully merged info for transaction: " ++ show transactionid
                    let signinfo = SignatureInfo    { signatureinfotext = transactiontbs
                                                    , signatureinfosignature = signature
                                                    , signatureinfocertificate = cert
                                                    , signatureinfoprovider = providerType
                                                    , signaturefstnameverified = bfn
                                                    , signaturelstnameverified = bln
                                                    , signaturepersnumverified = bpn
                                                    }

                    newdocument <- update $ SignDocument docid
                                                signid
                                                ctxtime
                                                ctxipnumber
                                                (Just signinfo)
                                                fields
                    case newdocument of
                        -- signature failed
                        Left message -> do
                            Log.eleg $ "SignDocument failed: " ++ message
                            addFlash (OperationFailed, message)
                            return LinkMain -- where should we go?
                        Right document2 -> do
                            postDocumentChangeAction document2 document (Just signid)
                            handleAfterSigning document2 signid

{- |
    Handle the ajax request for an eleg signature for the author.
    URL: /d/{provider}/{docid}
    Method: GET

    Validation:
    the document absolutely must exist. If the docid is not found, 404
    the tbs text must exist
-}
handleIssueBankID :: Kontrakcja m => String -> DocumentID -> m (Either KontraLink Response)
handleIssueBankID provider docid = withUserGet $ do
    Context { ctxtime, ctxmaybeuser = Just author } <- getContext
    let seconds = toSeconds ctxtime

    document <- guardRightM $ getDocByDocID docid

    tbs <- case documentstatus document of
        Preparation    -> getDataFnM $ look "tbs" -- tbs will be sent as post param
        AwaitingAuthor -> getTBS document         -- tbs is stored in document
        _              -> mzero

    guard $ isAuthor (document, author) -- necessary because friend of author cannot initiate eleg

    providerCode <- providerStringToNumber provider
    nonceresponse <- generateChallenge providerCode
    case nonceresponse of
        Left (ImplStatus _a _b code msg) -> do
            Log.eleg $ "generateChallenge failed: " ++ toJSON [("status", JInt code), ("msg", JString msg)]
            return $ toResponse $ toJSON [("status", JInt code), ("msg", JString msg)]
        Right (nonce, transactionid) -> do
            -- encode the text to be signed

            encodetbsresponse <- encodeTBS providerCode tbs transactionid
            case encodetbsresponse of
                Left (ImplStatus _a _b code msg) -> do
                    Log.eleg $ "encodeTBS failed: " ++ toJSON [("status", JInt code), ("msg", JString msg)]
                    return $ toResponse $ toJSON [("status", JInt code), ("msg", JString msg)]
                Right txt -> do
                    -- store in session
                    addELegTransaction ELegTransaction
                                        { transactionservertime      = ctxtime
                                        , transactiontransactionid   = transactionid
                                        , transactiontbs             = tbs
                                        , transactionencodedtbs      = txt
                                        , transactionsignatorylinkid = Nothing
                                        , transactiondocumentid      = docid
                                        , transactionmagichash       = Nothing
                                        , transactionnonce           = nonce
                                        }
                    return $ toResponse $ toJSON [("status", JInt 0)
                                                 ,("servertime", JString $ show seconds)
                                                 ,("nonce", JString nonce)
                                                 ,("tbs", JString txt)
                                                 ,("transactionid", JString transactionid)]

{- |
   Handle POST when author wants to sign+issue document
   URL: /d/{docid}
   Method: POST
   params
     provider -- the eleg provider (bankid, nordea, telia)
     signature -- signature generated by BankID plugin
     transactionid -- the id of the transaction from the BankID Ajax request

    Validation:
    the document absolutely must exist. If the docid is not found, 404
    the author should be logged in, otherwise 404
    provider, signature, transactionid must exist (or 404)
    there must be a valid eleg transaction
        the transaction must use the same docid

 -}
handleIssuePostBankID :: Kontrakcja m => DocumentID -> m KontraLink
handleIssuePostBankID docid = withUserPost $ do
    ctx@Context { ctxmaybeuser = Just author
                , ctxelegtransactions
                , ctxtime
                , ctxipnumber } <- getContext

    provider      <- getDataFnM $ look "eleg"
    signature     <- getDataFnM $ look "signature"
    transactionid <- getDataFnM $ look "transactionid"
    signlast <- isFieldSet "signlast"
    document <- guardRightM $ getDocByDocID docid

    guard $ isAuthor (document, author) -- necessary because friend of author cannot initiate eleg

    -- valid transaction?
    ELegTransaction { transactiondocumentid
                    , transactiontbs
                    , transactionencodedtbs
                    , transactionnonce
                    } <- findTransactionByIDOrFail ctxelegtransactions transactionid

    guard $ transactiondocumentid == docid
    -- end validation
    eudoc <- case documentstatus document of
                Preparation -> updateDocument ctx document
                AwaitingAuthor -> return $ Right document
                s -> return $ Left $ "Wrong status: " ++ show s
    case eudoc of
        Left msg -> do
            Log.eleg $ "updateDocument failed: " ++ msg
            addFlash (OperationFailed, "Could not save document.")
            return LinkMain
        Right udoc -> do
            unless (udoc `allowsIdentification` ELegitimationIdentification) mzero
            providerCode <- providerStringToNumber provider
            res <- verifySignature providerCode
                    transactionencodedtbs
                    signature
                    (if providerCode == 6
                    then Just transactionnonce
                    else Nothing)
                    transactionid

            case res of
                Left (ImplStatus _a _b code msg) -> do
                    Log.eleg $ "verifySignature failed: " ++ toJSON [("status", JInt code), ("msg", JString msg)]
                    addFlash (OperationFailed, "E-legitimationstjänsten misslyckades att verifiera din signatur")
                    -- change me! I should return back to the same page
                    return $ LinkDesignDoc $ DesignStep3 docid signlast
                Right (cert, attrs) -> do
                    Log.debug $ show attrs
                    providerType <- providerStringToType provider
                    -- compare information from document (and fields) to that obtained from BankID
                    let contractFirst  = getFirstName      author
                        contractLast   = getLastName       author
                        contractNumber = getPersonalNumber author

                        elegFirst  = fieldvaluebyid (BS.fromString "Subject.GivenName")    attrs
                        elegLast   = fieldvaluebyid (BS.fromString "Subject.Surname")      attrs
                        elegNumber = fieldvaluebyid (BS.fromString "Subject.SerialNumber") attrs

                        mfinal = mergeInfo
                                    (contractFirst, contractLast, contractNumber)
                                    (elegFirst,     elegLast,     elegNumber)
                    Log.debug $ show (contractFirst, contractLast, contractNumber)
                    Log.debug $ show (elegFirst,     elegLast,     elegNumber)
                    case mfinal of
                        Left (msg, _, _, _) -> do
                            Log.eleg $ "merge failed: " ++ msg
                            addFlash (OperationFailed, "Dina personuppgifter matchade inte informationen från e-legitimationsservern: " ++ msg)
                            return $ LinkDesignDoc $ DesignStep3 docid signlast
                        -- we have merged the info!
                        Right (bfn, bln, bpn) -> do
                            Log.eleg $ "author merge succeeded. (details omitted)"
                            let signinfo = SignatureInfo    { signatureinfotext        = transactiontbs
                                                            , signatureinfosignature   = signature
                                                            , signatureinfocertificate = cert
                                                            , signatureinfoprovider    = providerType
                                                            , signaturefstnameverified = bfn
                                                            , signaturelstnameverified = bln
                                                            , signaturepersnumverified = bpn
                                                            }
                                signInd d = do
                                    mndoc <- case documentstatus document of
                                                Preparation -> update $ AuthorSignDocument (documentid d) ctxtime ctxipnumber $ Just signinfo
                                                AwaitingAuthor -> do
                                                    ed <- update $ CloseDocument (documentid d) ctxtime ctxipnumber $ Just signinfo
                                                    case ed of
                                                        Nothing -> return $ Left "could not close document"
                                                        Just d2 -> return $ Right d2
                                                _ -> do {Log.debug "should not have other status" ; mzero}
                                    case mndoc of
                                        Left msg -> do
                                            Log.eleg $ "AuthorSignDocument failed: " ++ msg
                                            return ()
                                        Right newdocument -> do
                                            postDocumentChangeAction newdocument udoc Nothing
                                            return ()
                                    return mndoc
                            mdocs <- splitUpDocument udoc
                            case mdocs of
                                Right docs -> do
                                    mndocs <- mapM signInd docs
                                    case (lefts mndocs, rights mndocs) of
                                        ([], [d]) -> do
                                            case documentstatus d of
                                                Pending -> addFlashM $ modalSendConfirmationView d
                                                Closed  -> addFlashM modalSignAwaitingAuthorLast
                                                _ -> mzero -- should not be possible but necessary for compiling
                                            return $ LinkIssueDoc (documentid d)
                                        ([], _) -> return $ LinkContracts 
                                        _ -> mzero
                                Left link -> return link

handleSignCanceledDataMismatch :: Kontrakcja m => DocumentID -> SignatoryLinkID -> m Response
handleSignCanceledDataMismatch docid signatorylinkid = do
    ctx <- getContext
    document <- queryOrFail $ GetDocumentByDocumentID docid
    signatorylink <- guardJust $ getSigLinkFor document signatorylinkid
    let mcancelationreason = documentcancelationreason document
    case mcancelationreason of
        Just (ELegDataMismatch msg sid _ _ _)
            | sid == signatorylinkid -> do
                maybeuser <- runDBQuery $ GetUserByEmail (currentServiceID ctx) (Email $ getEmail signatorylink)
                content1 <- signCanceledDataMismatch document signatorylink (isJust maybeuser) msg
                renderFromBody TopEmpty kontrakcja content1
        _ -> sendRedirect $ LinkSignDoc document signatorylink

signCanceledDataMismatch :: TemplatesMonad m
                         => Doc.DocState.Document
                         -> SignatoryLink
                         -> Bool
                         -> String
                         -> m String
signCanceledDataMismatch _document _signatorylink _hasaccount msg =
    renderTemplateFM "signCanceledDataMismatch" $
        field "cancelationMessage" msg

-- JSON - just enough to get things working

data JSONValue = JString String
               | JInt Int

kvJson :: (String, JSONValue) -> String
kvJson (k, JInt v) = "\"" ++ k ++ "\" : " ++ show v
kvJson (k, JString v) = "\"" ++ k ++ "\" : \"" ++ v ++ "\""

toJSON :: [(String, JSONValue)] -> String
toJSON kvs = "{ " ++ intercalate ", " (map kvJson kvs) ++ " }"

-- SOAP

endpoint :: String
endpoint = "https://eid.funktionstjanster.se:8890/osif" -- production
--endpoint = "https://eidt.funktionstjanster.se:18898/osif" -- test

serviceid :: String
serviceid = "skrivapa9421" -- production
--serviceid = "logtest004" -- test

data ImplStatus = ImplStatus Int String Int String

data GenerateChallengeRequest = GenerateChallengeRequest Int String

instance HTypeable (GenerateChallengeRequest) where
    toHType _x = Defined "GenerateChallengeRequest" [] []
instance XmlContent (GenerateChallengeRequest) where
    toContents (GenerateChallengeRequest provider policy) =
        [CElem (Elem "generateChallengeRequest"
                [mkAttr "xmlns" "urn:www.sll.se/wsdl/soap/osif"]
                [CElem (Elem "provider"
                                 [mkAttr "xmlns" ""]
                                 (toText $ show provider)) ()
                ,CElem (Elem "policy"
                                 [mkAttr "xmlns" ""]
                                 (toText policy)) ()
                ])
         ()]
    parseContents = error "Please do not parse GenerateChallengeRequest"

data GenerateChallengeResponse = GenerateChallengeResponse ImplStatus String String

instance HTypeable (GenerateChallengeResponse) where
    toHType _x = Defined "GenerateChallengeResponse" [] []
instance XmlContent (GenerateChallengeResponse) where
    toContents _ = error "Do not serialize GenerateChallengeResponse"
    parseContents =  do
        { e <- elementNS "generateChallengeResponse"
        ; interior e $ do
            { s <- elementNS "status"
            ; status <- interior s $ do
                          { errorGroup <- inElementNS "errorGroup" text
                          ; errorGroupDescription <- optional $ inElementNS "errorGroupDescription" text
                          ; errorCode <- inElementNS "errorCode" text
                          ; errorCodeDescription <- optional $ inElementNS "errorCodeDescription" text
                          ; return (ImplStatus (read errorGroup)
                                               (fromMaybe "" errorGroupDescription)
                                               (read errorCode)
                                               (fromMaybe "" errorCodeDescription))
                          }

            ; challenge <- optional $ inElementNS "challenge" text
            ; transactionid <- optional $ inElementNS "transactionID" text
            ; return (GenerateChallengeResponse status
                                                (fromMaybe "" challenge)
                                                (fromMaybe "" transactionid))
            }
        } `adjustErr` ("in <GenerateChallengeResponse>, "++)

data EncodeTBSRequest = EncodeTBSRequest Int String String String

instance HTypeable (EncodeTBSRequest) where
    toHType _x = Defined "EncodeTBSRequest" [] []
instance XmlContent (EncodeTBSRequest) where
    toContents (EncodeTBSRequest provider policy tbs transactionID) =
        [CElem (Elem "encodeTBSRequest"
                [mkAttr "xmlns" "urn:www.sll.se/wsdl/soap/osif"]
                [CElem (Elem "provider"
                                 [mkAttr "xmlns" ""]
                                 (toText $ show provider)) ()
                ,CElem (Elem "policy"
                                 [mkAttr "xmlns" ""]
                                 (toText policy)) ()
                ,CElem (Elem "transactionID"
                                 [mkAttr "xmlns" ""]
                                 (toText transactionID)) ()
                ,CElem (Elem "tbsText"
                                 [mkAttr "xmlns" ""]
                                 (toText tbs)) ()
                ])
         ()]
    parseContents = error "Please do not parse EncodeTBSRequest"

data EncodeTBSResponse = EncodeTBSResponse ImplStatus String String

instance HTypeable (EncodeTBSResponse) where
    toHType _x = Defined "EncodeTBSResponse" [] []
instance XmlContent (EncodeTBSResponse) where
    toContents _ = error "Do not serialize EncodeTBSResponse"
    parseContents =  do
        { e <- elementNS "encodeTBSResponse"
        ; interior e $ do
            { s <- elementNS "status"
            ; status <- interior s $ do
                          { errorGroup <- inElementNS "errorGroup" text
                          ; errorGroupDescription <- optional $ inElementNS "errorGroupDescription" text
                          ; errorCode <- inElementNS "errorCode" text
                          ; errorCodeDescription <- optional $ inElementNS "errorCodeDescription" text
                          ; return (ImplStatus (read errorGroup)
                                               (fromMaybe "" errorGroupDescription)
                                               (read errorCode)
                                               (fromMaybe "" errorCodeDescription))
                          }

            ; text2 <- optional $ inElementNS "text" text
            ; transactionid <- optional $ inElementNS "transactionID" text
            ; return (EncodeTBSResponse status
                                                (fromMaybe "" text2)
                                                (fromMaybe "" transactionid))
            }
        } `adjustErr` ("in <EncodeTBSResponse>, "++)

data VerifySignatureRequest = VerifySignatureRequest Int String String String (Maybe String) String

instance HTypeable (VerifySignatureRequest) where
    toHType _x = Defined "VerifySignatureRequest" [] []
instance XmlContent (VerifySignatureRequest) where
    toContents (VerifySignatureRequest provider policy tbs signature mnonce transactionID) =
        [CElem (Elem "verifySignatureRequest"
                [mkAttr "xmlns" "urn:www.sll.se/wsdl/soap/osif"]
                ([CElem (Elem "provider"
                                 [mkAttr "xmlns" ""]
                                 (toText $ show provider)) ()
                ,CElem (Elem "policy"
                                 [mkAttr "xmlns" ""]
                                 (toText policy)) ()
                ,CElem (Elem "transactionID"
                                 [mkAttr "xmlns" ""]
                                 (toText transactionID)) ()
                ,CElem (Elem "tbsText"
                                 [mkAttr "xmlns" ""]
                                 (toText tbs)) ()
                ,CElem (Elem "signature"
                                 [mkAttr "xmlns" ""]
                                 (toText signature)) ()
                                 ]
                                 ++ if isJust mnonce
                                        then [CElem (Elem "nonce"
                                                [mkAttr "xmlns" ""]
                                                (toText $ fromJust mnonce)) ()]
                                        else [])
                )
         ()]
    parseContents = error "Please do not parse VerifySignatureRequest"

slurpAttributes :: Parser (Content Text.XML.HaXml.Posn.Posn) [(BS.ByteString, BS.ByteString)]
slurpAttributes = slurpAttributes' []

slurpAttributes' :: [(BS.ByteString, BS.ByteString)]
                        -> Parser (Content Text.XML.HaXml.Posn.Posn)
                                [(BS.ByteString, BS.ByteString)]
slurpAttributes' ls = do
  att <- optional $ inElementNS "attributes" $ do
                        name <- inElementNS "name" text
                        value <- inElementNS "value" text
                        return (BS.fromString name, BS.fromString value)
  case att of
    Nothing -> return ls
    Just nv -> slurpAttributes' $ nv : ls


data VerifySignatureResponse = VerifySignatureResponse ImplStatus [(BS.ByteString, BS.ByteString)] String

instance HTypeable (VerifySignatureResponse) where
    toHType _x = Defined "VerifySignatureResponse" [] []
instance XmlContent (VerifySignatureResponse) where
    toContents _ = error "Do not serialize VerifySignatureResponse"
    parseContents =  do
        { e <- elementNS "verifySignatureResponse"
        ; interior e $ do
            { s <- elementNS "status"
            ; status <- interior s $ do
                          { errorGroup <- inElementNS "errorGroup" text
                          ; errorGroupDescription <- optional $ inElementNS "errorGroupDescription" text
                          ; errorCode <- inElementNS "errorCode" text
                          ; errorCodeDescription <- optional $ inElementNS "errorCodeDescription" text
                          ; return (ImplStatus (read errorGroup)
                                               (fromMaybe "" errorGroupDescription)
                                               (read errorCode)
                                               (fromMaybe "" errorCodeDescription))
                          }
            ; attrs <- slurpAttributes
            ; _transactionid <- optional $ inElementNS "transactionID" text
            ; certificate <- optional $ inElementNS "certificate" text
            ; return (VerifySignatureResponse status attrs (fromMaybe "" certificate))
            }
        } `adjustErr` ("in <VerifySignatureResponse>, "++)

certfile :: String
certfile = "certs/steria3.pem"

generateChallenge :: Kontrakcja m => Int -> m (Either ImplStatus (String, String))
generateChallenge pid = do
    eresponse <- liftIO $ makeSoapCallCA endpoint certfile "GenerateChallenge" $ GenerateChallengeRequest pid serviceid
    case eresponse of
        Left msg -> do
            liftIO $ print msg
            error msg
        Right (GenerateChallengeResponse (ImplStatus a b status msg) challenge transactionid) ->
            if status == 0
            then return $ Right (challenge, transactionid)
            else return $ Left (ImplStatus a b status msg)

encodeTBS :: Kontrakcja m => Int -> String -> String -> m (Either ImplStatus String)
encodeTBS provider tbs transactionID = do
    eresponse <- liftIO $ makeSoapCallCA endpoint certfile "EncodeTBS" $ EncodeTBSRequest provider serviceid tbs transactionID
    case eresponse of
        Left msg -> do
            liftIO $ print msg
            error msg
        Right (EncodeTBSResponse (ImplStatus a b status msg) txt _c) ->
            if status == 0
            then return $ Right txt
            else return $ Left (ImplStatus a b status msg)

verifySignature :: Kontrakcja m
                => Int
                -> String
                -> String
                -> Maybe String
                -> String
                -> m (Either ImplStatus (String, [(BS.ByteString, BS.ByteString)]))
verifySignature provider tbs signature mnonce transactionID = do
    eresponse <- liftIO $
        makeSoapCallCA endpoint certfile
            "VerifySignature" $
            VerifySignatureRequest provider
                serviceid
                tbs
                signature
                mnonce
                transactionID
    case eresponse of
        Left msg -> do
            liftIO $ print msg
            error msg
        Right (VerifySignatureResponse (ImplStatus a b status msg) attrs certificate) ->
            if status == 0
            then return $ Right (certificate, attrs)
            else return $ Left (ImplStatus a b status msg)

data MergeResult = MergeMatch
                 | MergeKeep
                 | MergeFail String
     deriving (Eq, Show)

{- | Compare signatory information from contract with that from the
     E-Legitimation provider. Returns Either and error message or the
     correct value.
 -}
mergeInfo :: (BS.ByteString, BS.ByteString, BS.ByteString)
                -> (BS.ByteString, BS.ByteString, BS.ByteString)
                -> Either (String, BS.ByteString, BS.ByteString, BS.ByteString) (Bool, Bool, Bool)
mergeInfo (contractFirst, contractLast, contractNumber) (elegFirst, elegLast, elegNumber) =
    let results = [ compareFirstNames contractFirst  elegFirst
                  , compareLastNames  contractLast   elegLast
                  , compareNumbers    contractNumber elegNumber]
        failmsgs = [msg | MergeFail msg <- results]
        matches  = map (== MergeMatch) results
    in if not $ null failmsgs
        then Left  (intercalate "\n" failmsgs, elegFirst, elegLast, elegNumber)
        else Right (matches !! 0, matches !! 1, matches !! 2)

findTransactionByIDOrFail :: Kontrakcja m => [ELegTransaction] -> String -> m ELegTransaction
findTransactionByIDOrFail transactions transactionsid =
    guardJust $ find ((==) transactionsid . transactiontransactionid) transactions

getTBS :: TemplatesMonad m => Doc.DocState.Document -> m String
getTBS doc = do
    entries <- getSigEntries doc
    renderTemplateFM "tbs" $ do
        field "documentname"   $ documenttitle doc
        field "documentnumber" $ show $ documentid doc
        field "tbssigentries"  entries

getSigEntries :: TemplatesMonad m => Doc.DocState.Document -> m String
getSigEntries doc = do
    s <- mapM (getSigEntry . signatorydetails) $ documentsignatorylinks doc
    return $ intercalate "\n" s

getSigEntry :: TemplatesMonad m => SignatoryDetails -> m String
getSigEntry signatorydetails =
    renderTemplateFM "tbssig" $ do
        field "firstname" $ getFirstName signatorydetails
        field "lastname"  $ getLastName signatorydetails
        field "company"   $ getCompanyName signatorydetails
        field "number"    $ getPersonalNumber signatorydetails

fieldvaluebyid :: BS.ByteString -> [(BS.ByteString, BS.ByteString)] -> BS.ByteString
fieldvaluebyid _ [] = BS.fromString ""
fieldvaluebyid fid ((k, v):xs)
    | k == fid  = v
    | otherwise = fieldvaluebyid fid xs

providerStringToNumber :: Kontrakcja m => String -> m Int
providerStringToNumber provider
    | provider == "bankid" = return 6
    | provider == "nordea" = return 4
    | provider == "telia"  = return 5
    | otherwise            = mzero

providerStringToType :: Kontrakcja m => String -> m SignatureProvider
providerStringToType provider
    | provider == "bankid" = return BankIDProvider
    | provider == "nordea" = return NordeaProvider
    | provider == "telia"  = return TeliaProvider
    | otherwise            = mzero

compareFirstNames :: BS.ByteString -> BS.ByteString -> MergeResult
compareFirstNames fnContract fnEleg
    | BS.null fnContract = MergeFail "Du har inte fyllt i förnamn, vänligen försök igen."
    | BS.null fnEleg = MergeKeep
    | otherwise =
        let fnsc = words $ map toLower $ BS.toString fnContract
            fnse = words $ map toLower $ BS.toString fnEleg
            difs = [levenshtein a b | a <- fnsc, b <- fnse]
        in if any (<= 1) difs
            then MergeMatch
            else MergeFail $ "Förnamn matchar inte: \"" ++ BS.toString fnContract ++ "\" och \"" ++ BS.toString fnEleg ++ "\"."

bsdigits :: BS.ByteString
bsdigits = BS.fromString "0123456789"

isBSDigit :: Word8 -> Bool
isBSDigit x = x `BS.elem` bsdigits

normalizeNumber :: BS.ByteString -> BS.ByteString
normalizeNumber n | BS.null n = n
normalizeNumber n
    | isBSDigit (BS.head n) = BS.cons (BS.head n) $ normalizeNumber (BS.tail n)
    | otherwise = normalizeNumber (BS.tail n)

compareNumbers :: BS.ByteString -> BS.ByteString -> MergeResult
compareNumbers nContract nEleg
    | BS.null nContract = MergeFail "Du har inte fyllt i personnnummer, vänligen försök igen."
    | BS.null nEleg     = MergeKeep
    | otherwise =
        let nsc = normalizeNumber nContract
            nse = normalizeNumber nEleg
            dif = levenshtein (BS.toString nsc) (BS.toString nse)
        in if dif <= 3
            then MergeMatch
            else MergeFail $ "Personnnummer matchar inte: \"" ++ BS.toString nContract ++ "\" och \"" ++ BS.toString nEleg ++ "\"."

compareLastNames :: BS.ByteString -> BS.ByteString -> MergeResult
compareLastNames lnContract lnEleg
    | BS.null lnContract = MergeFail "Du har inte fyllt i efternamn, vänligen försök igen."
    | BS.null lnEleg = MergeKeep
    | levenshtein (map toLower (BS.toString lnContract)) (map toLower (BS.toString lnEleg)) <= 1 = MergeMatch
    | otherwise = MergeFail $ "Efternamn matchar inte: \"" ++ BS.toString lnContract ++ "\" och \"" ++ BS.toString lnEleg ++"\"."

--GHC.Unicode.toLower
-- import GHC.Unicode ( toLower )
--import qualified Data.ByteString.Lazy.Char8 as B


