{-# LANGUAGE FunctionalDependencies, ExtendedDefaultRules #-}
module API.Monad.V2Errors (
                 APIError(),
                 serverError,
                 endpointNotFound,
                 invalidAuthorisation,
                 insufficientPrivileges,
                 requestParametersMissing,
                 requestParametersParseError,
                 requestParameterInvalid,
                 documentObjectVersionMismatch,
                 documentStateError,
                 signatoryStateError,
                 documentActionForbidden,
                 documentNotFound,
                 resourceNotFound,
                 httpCodeFromSomeKontraException,
                 jsonFromSomeKontraException,
                 tryToConvertConditionalExpectionIntoAPIError
                 )
  where

import Data.Text
import Data.Typeable
import Text.JSON
import Text.JSON.Gen hiding (object)
import qualified Data.Text as T

import DB
import Doc.Conditions
import Doc.DocStateData
import Doc.DocumentID
import KontraPrelude

data APIError = APIError {
      errorType     :: APIErrorType
    , errorHttpCode :: Int
    , errorMessage  :: Text
  }
  deriving (Show, Eq, Typeable)



data APIErrorType = ServerError
               | EndpointNotFound
               | InvalidAuthorisation
               | InsufficientPrivileges
               | ResourceNotFound
               | DocumentActionForbidden
               | RequestParametersMissing
               | RequestParametersParseError
               | RequestParametersInvalid
               | DocumentObjectVersionMismatch
               | DocumentStateError
               | SignatoryStateError
  deriving (Show, Eq, Typeable)

instance KontraException APIError


instance ToJSValue APIError where
  toJSValue a = runJSONGen $ do
    value "error_type" (unpack $ errorIDFromAPIErrorType $ errorType a)
    value "error_message" (unpack $ errorMessage a)
    value "http_code" (errorHttpCode $ a)


errorIDFromAPIErrorType :: APIErrorType -> Text
errorIDFromAPIErrorType ServerError                   = "server_error"
errorIDFromAPIErrorType EndpointNotFound              = "endpoint_not_found"
errorIDFromAPIErrorType InvalidAuthorisation          = "invalid_authorisation"
errorIDFromAPIErrorType InsufficientPrivileges        = "insufficient_privileges"
errorIDFromAPIErrorType ResourceNotFound              = "resource_not_found"
errorIDFromAPIErrorType DocumentActionForbidden       = "document_action_forbidden"
errorIDFromAPIErrorType RequestParametersMissing      = "request_parameters_missing"
errorIDFromAPIErrorType RequestParametersParseError   = "request_parameters_parse_error"
errorIDFromAPIErrorType RequestParametersInvalid      = "request_parameters_invalid"
errorIDFromAPIErrorType DocumentObjectVersionMismatch = "document_object_version_mismatch"
errorIDFromAPIErrorType DocumentStateError            = "document_state_error"
errorIDFromAPIErrorType SignatoryStateError           = "signatory_state_error"

jsonFromSomeKontraException :: SomeKontraException -> JSValue
jsonFromSomeKontraException (SomeKontraException ex)  = toJSValue ex

httpCodeFromSomeKontraException :: SomeKontraException -> Int
httpCodeFromSomeKontraException (SomeKontraException ex) =
  case cast ex of
    Just (apierror :: APIError) -> errorHttpCode apierror
    Nothing -> 500


-- General errors
serverError :: Text -> APIError
serverError reason = APIError { errorType = ServerError, errorHttpCode = 500, errorMessage = msg}
  where msg = "We encountered an unexpected error. Please contact Scrive "
              `append` "support and include as much details about what caused "
              `append` "the error, including the document id or any other details. "
              `append` "Error details: " `append` reason

endpointNotFound :: Text -> APIError
endpointNotFound ep = APIError { errorType = EndpointNotFound, errorHttpCode = 404, errorMessage = msg}
  where msg = "The endpoint " `append` ep `append` " was not found. See our website for API documentation."

invalidAuthorisation :: Text -> APIError
invalidAuthorisation problem = APIError { errorType = InvalidAuthorisation, errorHttpCode = 401, errorMessage = msg}
  where msg = "No valid access credentials were provided. Please refer to our API documentation. " `append` problem

-- TODO JJ: convert this to the following type for proper error messages:
-- insufficientPrivileges :: [APIPrivilege] -> APIError
-- where [APIPrivilege] is the missing privileges, then we can use interal APIPrivilege -> Text to show these
insufficientPrivileges :: Text -> APIError
insufficientPrivileges msg = APIError { errorType = InsufficientPrivileges, errorHttpCode = 403, errorMessage = msg}

-- Request specific errors
requestParametersMissing :: [Text] -> APIError
requestParametersMissing missingParams = APIError { errorType = RequestParametersMissing, errorHttpCode = 400, errorMessage = msg}
  where msg = "The parameter(s) " `append` params `append` " were missing. Please refer to our API documentation."
        params = T.intercalate " " missingParams

-- TODO JJ: convert this to similar type as `requestParametersMissing`, but with optional params as we might not know them?
-- TODO JJ: then we can have constant msg
requestParametersParseError :: Text -> APIError
requestParametersParseError msg = APIError { errorType = RequestParametersParseError, errorHttpCode = 400, errorMessage = msg}

requestParameterInvalid :: Text -> Text -> APIError
requestParameterInvalid param reason = APIError { errorType = RequestParametersInvalid, errorHttpCode = 400, errorMessage = msg}
  where msg = "The parameter " `append` param `append` " had the following problems: " `append` reason

-- Document calls errors

documentObjectVersionMismatch :: Text -> APIError
documentObjectVersionMismatch msg = APIError { errorType = DocumentObjectVersionMismatch, errorHttpCode = 409, errorMessage = msg}

documentStateError :: Text -> APIError
documentStateError msg = APIError { errorType = DocumentStateError, errorHttpCode = 409, errorMessage = msg}

signatoryStateError :: Text -> APIError
signatoryStateError msg = APIError { errorType = SignatoryStateError, errorHttpCode = 409, errorMessage = msg}

documentActionForbidden :: APIError
documentActionForbidden = APIError { errorType = DocumentActionForbidden, errorHttpCode = 403, errorMessage = msg}
  where msg = "You do not have permission to perform this action on the document."

documentNotFound :: DocumentID -> APIError
documentNotFound did = resourceNotFound $ "A document with id " `append` didText `append` " was not found."
  where didText = pack (show did)

resourceNotFound :: Text -> APIError
resourceNotFound info = APIError { errorType = ResourceNotFound, errorHttpCode = 404, errorMessage = msg}
  where msg = "The resource was not found. " `append` info

-- Conversion of DB exception / document conditionals into API errors

tryToConvertConditionalExpectionIntoAPIError :: SomeKontraException -> SomeKontraException
tryToConvertConditionalExpectionIntoAPIError  =  compose [
      convertDocumentDoesNotExist
    , convertDocumentTypeShouldBe
    , convertDocumentStatusShouldBe
    , convertUserShouldBeSelfOrCompanyAdmin
    , convertUserShouldBeDirectlyOrIndirectlyRelatedToDocument
    , convertSignatoryLinkDoesNotExist
    , convertSignatoryHasNotYetSigned
    , convertSignatoryIsNotPartner
    , convertSignatoryIsAuthor
    , convertSignatoryHasAlreadySigned
    , convertSignatoryTokenDoesNotMatch
    , convertDocumentObjectVersionDoesNotMatch
    , convertDocumentWasPurged
    , convertDocumentIsDeleted
    , convertDocumentIsNotDeleted
    , convertDocumentIsReallyDeleted
    , convertSignatoryAuthenticationDoesNotMatch
  ]
  where
    compose [] = id
    compose (f:fs) = f . compose fs

convertDocumentDoesNotExist :: SomeKontraException -> SomeKontraException
convertDocumentDoesNotExist (SomeKontraException ex) =
  case cast ex of
    Just (DocumentDoesNotExist did) ->  SomeKontraException $ documentNotFound did
    Nothing -> (SomeKontraException ex)

convertDocumentTypeShouldBe :: SomeKontraException -> SomeKontraException
convertDocumentTypeShouldBe (SomeKontraException ex) =
  case cast ex of
    Just (DocumentTypeShouldBe  {documentTypeShouldBe = Template}) ->  SomeKontraException $ documentStateError $ "Document is not a template"
    Just (DocumentTypeShouldBe  {documentTypeShouldBe = Signable}) ->  SomeKontraException $ documentStateError $ "Document is a template"
    Nothing -> (SomeKontraException ex)

convertDocumentStatusShouldBe :: SomeKontraException -> SomeKontraException
convertDocumentStatusShouldBe (SomeKontraException ex) =
  case cast ex of
    Just (DocumentStatusShouldBe{}) ->  SomeKontraException $ documentStateError $ "Invalid document state "
    Nothing -> (SomeKontraException ex)

convertUserShouldBeSelfOrCompanyAdmin :: SomeKontraException -> SomeKontraException
convertUserShouldBeSelfOrCompanyAdmin (SomeKontraException ex) =
  case cast ex of
-- JJ: this is not a case of "invalid_authorisation", this looks like "insufficient_privileges"
-- JJ: "invalid_authorisation" is for "no valid credentials", not a permission issue
-- JJ: if you still think this is valid the function should be renamed
    Just (UserShouldBeSelfOrCompanyAdmin{}) ->  SomeKontraException $ invalidAuthorisation $ "You can not perform this action with current authorization."
    Nothing -> (SomeKontraException ex)

convertUserShouldBeDirectlyOrIndirectlyRelatedToDocument :: SomeKontraException -> SomeKontraException
convertUserShouldBeDirectlyOrIndirectlyRelatedToDocument (SomeKontraException ex) =
  case cast ex of
-- JJ: this is not a case of "invalid_authorisation", this looks like "insufficient_privileges"
-- JJ: "invalid_authorisation" is for "no valid credentials", not a permission issue
-- JJ: if you still think this is valid the function should be renamed
    Just (UserShouldBeDirectlyOrIndirectlyRelatedToDocument {}) ->  SomeKontraException $ invalidAuthorisation $ "You don't have rights not perform action on this document"
    Nothing -> (SomeKontraException ex)


convertSignatoryLinkDoesNotExist :: SomeKontraException -> SomeKontraException
convertSignatoryLinkDoesNotExist (SomeKontraException ex) =
  case cast ex of
    Just (SignatoryLinkDoesNotExist sig) ->  SomeKontraException $ signatoryStateError $ "Signatory"  `append` pack (show sig) `append` " does not exists"
    Nothing -> (SomeKontraException ex)


convertSignatoryHasNotYetSigned :: SomeKontraException -> SomeKontraException
convertSignatoryHasNotYetSigned (SomeKontraException ex) =
  case cast ex of
    Just (SignatoryHasNotYetSigned {}) ->  SomeKontraException $ signatoryStateError $ "Signatory has not signed yet"
    Nothing -> (SomeKontraException ex)

convertSignatoryIsNotPartner :: SomeKontraException -> SomeKontraException
convertSignatoryIsNotPartner (SomeKontraException ex) =
  case cast ex of
    Just (SignatoryIsNotPartner {}) ->  SomeKontraException $ signatoryStateError $ "Signatory should not sign this document "
    Nothing -> (SomeKontraException ex)

convertSignatoryIsAuthor :: SomeKontraException -> SomeKontraException
convertSignatoryIsAuthor (SomeKontraException ex) =
  case cast ex of
    Just (SignatoryIsAuthor {}) -> SomeKontraException $ signatoryStateError $ "Signatory is author"
    Nothing -> (SomeKontraException ex)

convertSignatoryHasAlreadySigned :: SomeKontraException -> SomeKontraException
convertSignatoryHasAlreadySigned (SomeKontraException ex) =
  case cast ex of
    Just (SignatoryHasAlreadySigned {}) ->  SomeKontraException $ signatoryStateError $ "Signatory already signed"
    Nothing -> (SomeKontraException ex)

convertSignatoryTokenDoesNotMatch :: SomeKontraException -> SomeKontraException
convertSignatoryTokenDoesNotMatch (SomeKontraException ex) =
  case cast ex of
-- JJ: this is not a case of "invalid_authorisation", this looks like "insufficient_privileges"
-- JJ: "invalid_authorisation" is for "no valid credentials", not a permission issue
-- JJ: if you still think this is valid the function should be renamed
    Just (SignatoryTokenDoesNotMatch {}) -> SomeKontraException $ invalidAuthorisation $ "Signatory token does not match"
    Nothing -> (SomeKontraException ex)

convertDocumentObjectVersionDoesNotMatch :: SomeKontraException -> SomeKontraException
convertDocumentObjectVersionDoesNotMatch (SomeKontraException ex) =
  case cast ex of
    Just (DocumentObjectVersionDoesNotMatch {..}) -> SomeKontraException $ documentObjectVersionMismatch $
      "The document has a different object_version to the one provided and so the request was not processed."
      `append` " You gave " `append` (pack $ show documentObjectVersionShouldBe)
      `append` " but the document had " `append` (pack $ show documentObjectVersionIs)
    Nothing -> (SomeKontraException ex)

convertDocumentWasPurged ::  SomeKontraException -> SomeKontraException
convertDocumentWasPurged (SomeKontraException ex) =
  case cast ex of
    Just (DocumentWasPurged {}) -> SomeKontraException $ documentStateError $ "Document was purged"
    Nothing -> (SomeKontraException ex)

convertDocumentIsDeleted ::  SomeKontraException -> SomeKontraException
convertDocumentIsDeleted (SomeKontraException ex) =
  case cast ex of
    Just (DocumentIsDeleted {}) -> SomeKontraException $ documentStateError $ "Document is deleted"
    Nothing -> (SomeKontraException ex)

convertDocumentIsNotDeleted ::  SomeKontraException -> SomeKontraException
convertDocumentIsNotDeleted (SomeKontraException ex) =
  case cast ex of
    Just (DocumentIsNotDeleted {}) -> SomeKontraException $ documentStateError $ "Document is not deleted"
    Nothing -> (SomeKontraException ex)


convertDocumentIsReallyDeleted ::  SomeKontraException -> SomeKontraException
convertDocumentIsReallyDeleted (SomeKontraException ex) =
  case cast ex of
    Just (DocumentIsReallyDeleted {}) -> SomeKontraException $ documentStateError $ "Document is really deleted. It is not avaialbe and will be purged soon"
    Nothing -> (SomeKontraException ex)


convertSignatoryAuthenticationDoesNotMatch ::  SomeKontraException -> SomeKontraException
convertSignatoryAuthenticationDoesNotMatch (SomeKontraException ex) =
  case cast ex of
-- JJ: this is really not a signatoryStateError if we are talking about authorisation
-- JJ: if this is related to SMS PIN then fine, but then the message is completely misleading
    Just (SignatoryAuthenticationDoesNotMatch {}) -> SomeKontraException $ signatoryStateError $ "Invalid authorization for signatory"
    Nothing -> (SomeKontraException ex)
