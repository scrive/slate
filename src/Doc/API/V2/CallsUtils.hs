module Doc.API.V2.CallsUtils (
      guardThatDocument
    , guardThatUserIsAuthor
    , guardThatDocumentCanBeStarted
    , guardThatObjectVersionMatchesIfProvided
    , checkAuthenticationMethodAndValue
    , getScreenshots
    , signDocument
    , getMagicHashAndUserForSignatoryAction
    , getValidPin
  ) where

import KontraPrelude
import Control.Conditional (unlessM, whenM)
import Data.Text (Text, pack)
import Happstack.Fields
import qualified Data.ByteString.Char8 as BS
import File.Model
import Doc.SignatoryScreenshots(SignatoryScreenshots, emptySignatoryScreenshots, resolveReferenceScreenshotNames)
import EID.Signature.Model
import MagicHash (MagicHash)
import Data.Unjson
import Doc.DocumentID
import Doc.DocStateQuery

import Doc.DocStateData
import API.Monad.V2
import Kontra
import Doc.DocumentMonad
import DB
import User.Model
import Doc.SignatoryLinkID
import Doc.API.V2.JSONMisc
import Util.SignatoryLinkUtils
import Control.Exception.Lifted
import Doc.DocUtils
import InputValidation
import Util.HasSomeUserInfo
import Doc.API.V2.JSONFields
import Doc.Model.Update
import Doc.Model.Query
import Util.Actor
import OAuth.Model
import Doc.Tokens.Model
import Doc.SMSPin.Model
import Doc.API.V2.Parameters

guardThatDocument :: (DocumentMonad m, Kontrakcja m) => (Document -> Bool) -> Text -> m ()
guardThatDocument f text = unlessM (f <$> theDocument) $ throwIO . SomeKontraException $ documentStateError text

guardThatUserIsAuthor :: (DocumentMonad m, Kontrakcja m) => User -> m ()
guardThatUserIsAuthor user = do
  auid <- apiGuardJustM (serverError "Document doesn't have author signatory link connected with user account") $ ((maybesignatory =<<) .getAuthorSigLink) <$> theDocument
  when (not $ (auid == userid user)) $ do
    throwIO $ SomeKontraException documentActionForbidden

guardThatObjectVersionMatchesIfProvided :: Kontrakcja m => DocumentID -> m ()
guardThatObjectVersionMatchesIfProvided did = do
  reqObjectVersion <- apiV2Parameter (ApiV2ParameterInt "object_version" Optional)
  case reqObjectVersion of
    Nothing -> return ()
    Just ov -> dbQuery $ CheckDocumentObjectVersionIs did (fromIntegral ov)

-- Checks if document can be strated. Throws matching API exception if it does not
guardThatDocumentCanBeStarted :: (DocumentMonad m, Kontrakcja m) => m ()
guardThatDocumentCanBeStarted = do
    whenM (isTemplate <$> theDocument) $ do
       throwIO . SomeKontraException $ (documentStateError "Document is not a draft")
    unlessM (((all signatoryHasValidDeliverySettings) . documentsignatorylinks) <$> theDocument) $ do
       throwIO . SomeKontraException $ documentStateError "Some signatories have invalid email address or phone number, and it is required for invitation delivery."
    whenM (isNothing . documentfile <$> theDocument) $ do
       throwIO . SomeKontraException $ documentStateError "File must be provided before document can be made ready."
    return ()
 where
    signatoryHasValidDeliverySettings sl = (isAuthor sl) || case (signatorylinkdeliverymethod sl) of
      EmailDelivery  ->  isGood $ asValidEmail $ getEmail sl
      MobileDelivery ->  isGood $ asValidPhoneForSMS $ getMobile sl
      EmailAndMobileDelivery -> (isGood $ asValidPhoneForSMS $ getMobile sl) && (isGood $ asValidEmail $ getEmail sl)
      _ -> True


{- | Check if provided authorization values for sign call patch -}
checkAuthenticationMethodAndValue :: (Kontrakcja m, DocumentMonad m) => SignatoryLinkID -> m ()
checkAuthenticationMethodAndValue slid = do
  mAuthType  :: Maybe String <- getField "authentication_type"
  mAuthValue :: Maybe String <- getField "authentication_value"
  case (mAuthType, mAuthValue) of
       (Just authType, Just authValue) -> do
           case (textToAuthenticationMethod $ pack authType) of
                Just authMethod -> do
                    siglink <- $fromJust . getSigLinkFor slid <$> theDocument
                    let authOK = authMethod == signatorylinkauthenticationmethod siglink
                    case (authOK, authMethod) of
                         (False, _) -> throwIO . SomeKontraException $
                             requestParameterInvalid "authentication_type" "`authentication_type` does not match on on document"
                         (True, StandardAuthentication) -> return ()
                         (True, ELegAuthentication)   ->
                             if (authValue == getPersonalNumber siglink || null (getPersonalNumber siglink))
                                then return ()
                                else throwIO . SomeKontraException $
                                    requestParameterInvalid "authentication_value" "`authentication_value` for personal number does not match"
                         (True, SMSPinAuthentication) ->
                             if (authValue == getMobile siglink || null (getMobile siglink))
                                then return ()
                                else throwIO . SomeKontraException $
                                    requestParameterInvalid "authentication_value" "`authentication_value` for phone number does not match"
                Nothing ->
                    throwIO . SomeKontraException $ requestParametersParseError "`authentication_type` was not a valid"
       (Nothing, Nothing) -> return ()
       (Just _, Nothing) ->  throwIO . SomeKontraException $ requestParametersMissing ["authentication_value"]
       (Nothing, Just _) ->  throwIO . SomeKontraException $ requestParametersMissing ["authentication_type"]

getScreenshots :: (Kontrakcja m) => m SignatoryScreenshots
getScreenshots = do
  screenshots <- apiV2Parameter' (ApiV2ParameterJSON "screenshots" (OptionalWithDefault (Just emptySignatoryScreenshots)) unjsonDef)
  resolvedScreenshots <- resolveReferenceScreenshotNames screenshots
  case resolvedScreenshots of
    Nothing -> throwIO . SomeKontraException $ requestParameterInvalid "screenshots" "Could not resolve reference screenshot"
    Just res -> return res



signDocument :: (Kontrakcja m, DocumentMonad m)
             => SignatoryLinkID
             -> MagicHash
             -> [(FieldIdentity, SignatoryFieldTMPValue)]
             -> Maybe ESignature
             -> Maybe String
             -> SignatoryScreenshots
             -> m ()
signDocument slid mh fields mesig mpin screenshots = do
  switchLang =<< getLang <$> theDocument
  ctx <- getContext
  -- Note that the second 'getSigLinkFor' call below may return a
  -- different result than the first one due to the field update, so
  -- don't attempt to replace the calls with a single call, or the
  -- actor identities may get wrong in the evidence log.
  fieldsWithFiles <- fieldsToFieldsWithFiles fields
  getSigLinkFor slid <$> theDocument >>= \(Just sl) -> dbUpdate . UpdateFieldsForSigning sl (fst fieldsWithFiles) (snd fieldsWithFiles) =<< signatoryActor ctx sl
  getSigLinkFor slid <$> theDocument >>= \(Just sl) -> dbUpdate . SignDocument slid mh mesig mpin screenshots =<< signatoryActor ctx sl


fieldsToFieldsWithFiles :: (Kontrakcja m)
                           => [(FieldIdentity,SignatoryFieldTMPValue)]
                           -> m ([(FieldIdentity,FieldValue)],[(FileID,BS.ByteString)])
fieldsToFieldsWithFiles [] = return ([],[])
fieldsToFieldsWithFiles (f:fs) = do
  (changeFields,files') <- fieldsToFieldsWithFiles fs
  case f of
    (fi,StringFTV s) -> return ((fi,StringFV s):changeFields,files')
    (fi,BoolFTV b)   -> return ((fi,BoolFV b):changeFields,files')
    (fi,FileFTV bs)  -> if (BS.null bs)
                          then return $ ((fi,FileFV Nothing):changeFields,files')
                          else do
                            fileid <- dbUpdate $ NewFile "signature.png" (Binary bs)
                            return $ ((fi,FileFV (Just fileid)):changeFields,(fileid,bs):files')

getMagicHashAndUserForSignatoryAction :: (Kontrakcja m) =>  DocumentID -> SignatoryLinkID -> m (MagicHash,Maybe User)
getMagicHashAndUserForSignatoryAction did sid = do
    mh' <- dbQuery $ GetDocumentSessionToken sid
    case mh' of
      Just mh'' ->  return (mh'',Nothing)
      Nothing -> do
         (user, _) <- getAPIUser APIPersonal
         mh'' <- getMagicHashForDocumentSignatoryWithUser  did sid user
         case mh'' of
           Nothing -> throwIO . SomeKontraException $ documentActionForbidden
           Just mh''' -> return (mh''',Just $ user)


getValidPin :: (Kontrakcja m, DocumentMonad m) => SignatoryLinkID -> [(FieldIdentity, SignatoryFieldTMPValue)] -> m (Maybe String)
getValidPin slid fields = do
  pin <- apiGuardJustM (requestParametersMissing ["pin"]) $ getField "pin"
  phone <- case (lookup MobileFI fields) of
    Just (StringFTV v) -> return v
    _ ->  getMobile <$> $fromJust . getSigLinkFor slid <$> theDocument
  pin' <- dbQuery $ GetSignatoryPin slid phone
  if (pin == pin')
    then return $ Just pin
    else return $ Nothing
