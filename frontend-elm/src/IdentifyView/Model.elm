module IdentifyView.Model exposing (..)

import Html exposing (Html)
import Http
import Json.Encode

import Lib.Types.Document exposing (Document(..))
import Lib.Types.SignatoryLink exposing (SignatoryLink, AuthenticationToViewMethod)
import Lib.Types.ID exposing (ID)
import Lib.Components.FlashMessage as FlashMessage
import Lib.Types.FlashMessage exposing (FlashMessage)
import Lib.Types.Localization exposing (Localization)
import Utils exposing (stringNonEmpty)

import IdentifyView.SMSPin.SMSPin as SMSPin
import IdentifyView.GenericEidService.GenericEidService as GenericEidService
import IdentifyView.Rejection.Rejection as Rejection

type Msg
  = AddFlashMessageMsg FlashMessage
  | ErrorTraceMsg (List (String, Json.Encode.Value))
  -- embedded messages
  | SMSPinMsg SMSPin.Msg
  | FlashMessageMsg FlashMessage.Msg
  | GenericEidServiceMsg GenericEidService.Msg
  | RejectionMsg Rejection.Msg
  | EnterRejectionClickedMsg

type alias Flags =
  { xtoken : String
  , localization : Localization
  , cdnBaseUrl : String
  , location : String
  , currentYear : Int
  , origin : String
  , logoUrl : String
  , welcomeText : String
  , entityTypeLabel : String
  , entityTitle : String
  , authenticationMethod : AuthenticationToViewMethod
  , authorName : String
  , participantEmail : String
  , participantMaskedMobile : String
  , genericEidServiceStartUrl : Maybe String
  , smsPinSendUrl : String
  , smsPinVerifyUrl : String
  , rejectionRejectUrl : String
  , rejectionAlreadyRejected : Bool
  , errorMessage : Maybe String
  , maxFailuresExceeded : Bool
  }

type alias Model =
  { flashMessages : FlashMessage.State
  , state : State
  }

type State
  = Loading Flags
  | Error { errorView : Html Msg }  -- better: semantic error view?
  | IdentifyView { flags : Flags, innerModel : ProviderModel }

type ProviderModel
  = IdentifySMSPin (SMSPin.Params Msg) SMSPin.State
  | IdentifyGenericEidService (GenericEidService.Params Msg) GenericEidService.State
  | IdentifyRejection (Rejection.Params Msg) Rejection.State

toRejectionParams : Flags -> Rejection.Params Msg
toRejectionParams f =
    { embed = RejectionMsg
    , addFlashMessageMsg = AddFlashMessageMsg
    , errorTraceMsg = ErrorTraceMsg
    , xtoken = f.xtoken
    , localization = f.localization
    , participantEmail = f.participantEmail
    , rejectUrl = f.rejectionRejectUrl
    }

toSMSPinParams : Flags -> Result String (SMSPin.Params Msg)
toSMSPinParams f =
    case stringNonEmpty f.participantMaskedMobile of
        Just participantMaskedMobile -> Ok
            { embed = SMSPinMsg
            , addFlashMessageMsg = AddFlashMessageMsg
            , errorTraceMsg = ErrorTraceMsg
            , xtoken = f.xtoken
            , localization = f.localization
            , participantMaskedMobile = participantMaskedMobile
            , sendUrl = f.smsPinSendUrl
            , verifyUrl = f.smsPinVerifyUrl
            }
        Nothing -> Err "Participant's (masked) mobile number is empty!"

toGenericEidServiceParams
    : Flags -> GenericEidService.Provider -> Result String (GenericEidService.Params Msg)
toGenericEidServiceParams f provider =
    case f.genericEidServiceStartUrl of
        Just startUrl -> Ok
            { embed = GenericEidServiceMsg
            , addFlashMessageMsg = AddFlashMessageMsg
            , errorTraceMsg = ErrorTraceMsg
            , provider = provider
            , xtoken = f.xtoken
            , location = f.location
            , localization = f.localization
            , cdnBaseUrl = f.cdnBaseUrl
            , participantEmail = f.participantEmail
            , startUrl = startUrl
            }
        Nothing ->
            Err "Required flag genericEidServiceStartUrl is null!"

