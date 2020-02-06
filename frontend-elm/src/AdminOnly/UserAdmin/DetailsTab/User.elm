module AdminOnly.UserAdmin.DetailsTab.User exposing
    ( User
    , decoder
    , enumAccountType
    , formValues
    )

import AdminOnly.UserAdmin.DetailsTab.UserGroup exposing (PadAppMode(..), SmsProvider(..), padAppModeDecoder, smsProviderDecoder)
import EnumExtra as Enum exposing (Enum, makeEnum)
import Json.Decode as D exposing (Decoder)
import Json.Decode.Pipeline as DP
import Language exposing (Language, enumLanguage)
import Time exposing (Month(..))
import Utils exposing (ite)



-- USER


type alias User =
    { id : String
    , firstName : String
    , secondName : String
    , personalNumber : String
    , email : String
    , phone : String
    , companyPosition : String
    , language : Language
    , userGroup : UserGroup
    , accountType : AccountType
    , callbackUrl : String
    , callbackUrlIsEditable : Bool
    , twoFAActive : Bool
    }


decoder : Decoder User
decoder =
    D.succeed User
        |> DP.required "id" D.string
        |> DP.required "fstname" D.string
        |> DP.required "sndname" D.string
        |> DP.required "personalnumber" D.string
        |> DP.required "email" D.string
        |> DP.required "phone" D.string
        |> DP.required "companyposition" D.string
        |> DP.required "lang" (D.string |> D.andThen Language.decoder)
        |> DP.required "company" userGroupDecoder
        |> DP.required "companyadmin" (D.bool |> D.andThen accountTypeDecoder)
        |> DP.required "callbackurl" D.string
        |> DP.required "callback_is_editable" D.bool
        |> DP.required "twofactor_active" D.bool


formValues : User -> List ( String, String )
formValues user =
    [ ( "userfstname", user.firstName )
    , ( "usersndname", user.secondName )
    , ( "userpersonalnumber", user.personalNumber )
    , ( "userphone", user.phone )
    , ( "useremail", user.email )
    , ( "usercompanyposition", user.companyPosition )
    , ( "userlang", Enum.toString enumLanguage user.language )
    , ( "useraccounttype", Enum.toString enumAccountType user.accountType )
    , ( "usercallbackurl", user.callbackUrl )
    ]



-- USER GROUP


type alias UserGroup =
    { id : String
    , name : String
    , address : String
    , city : String
    , country : String
    , zip : String
    , companynumber : String
    , ipAddressMaskList : String
    , cgiDisplayName : Maybe String
    , cgiServiceID : Maybe String
    , smsProvider : SmsProvider
    , padAppMode : PadAppMode
    , padEarchiveEnabled : Bool
    , idleDocTimeoutPreparation : Maybe Int
    , idleDocTimeoutClosed : Maybe Int
    , idleDocTimeoutCanceled : Maybe Int
    , idleDocTimeoutTimeout : Maybe Int
    , idleDocTimeoutRejected : Maybe Int
    , idleDocTimeoutError : Maybe Int
    , immediateTrash : Bool
    }


userGroupDecoder : Decoder UserGroup
userGroupDecoder =
    D.succeed UserGroup
        |> DP.required "companyid" D.string
        |> DP.required "companyname" D.string
        |> DP.required "address" D.string
        |> DP.required "city" D.string
        |> DP.required "country" D.string
        |> DP.required "zip" D.string
        |> DP.required "companynumber" D.string
        |> DP.required "ipaddressmasklist" D.string
        |> DP.required "cgidisplayname" (D.string |> D.nullable)
        |> DP.required "cgiserviceid" (D.string |> D.nullable)
        |> DP.required "smsprovider" (D.string |> D.andThen smsProviderDecoder)
        |> DP.required "padappmode" (D.string |> D.andThen padAppModeDecoder)
        |> DP.required "padearchiveenabled" D.bool
        |> DP.required "idledoctimeoutpreparation" (D.int |> D.nullable)
        |> DP.required "idledoctimeoutclosed" (D.int |> D.nullable)
        |> DP.required "idledoctimeoutcanceled" (D.int |> D.nullable)
        |> DP.required "idledoctimeouttimedout" (D.int |> D.nullable)
        |> DP.required "idledoctimeoutrejected" (D.int |> D.nullable)
        |> DP.required "idledoctimeouterror" (D.int |> D.nullable)
        |> DP.required "immediatetrash" D.bool



-- Account Type


accountTypeDecoder : Bool -> Decoder AccountType
accountTypeDecoder isUserGroupAdmin =
    D.succeed <| ite isUserGroupAdmin UserGroupAdmin UserGroupMember


allAccountTypes : List AccountType
allAccountTypes =
    [ UserGroupMember, UserGroupAdmin ]


encodeAccountType : AccountType -> String
encodeAccountType accountType =
    case accountType of
        UserGroupMember ->
            "companystandardaccount"

        UserGroupAdmin ->
            "companyadminaccount"


fromAccountType : AccountType -> String
fromAccountType accountType =
    case accountType of
        UserGroupMember ->
            "Company account"

        UserGroupAdmin ->
            "Company admin"


type AccountType
    = UserGroupMember
    | UserGroupAdmin


enumAccountType : Enum AccountType
enumAccountType =
    makeEnum allAccountTypes encodeAccountType fromAccountType
