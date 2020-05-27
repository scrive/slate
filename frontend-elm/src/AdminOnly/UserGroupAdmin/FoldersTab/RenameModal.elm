module AdminOnly.UserGroupAdmin.FoldersTab.RenameModal exposing
    ( Model
    , Msg
    , init
    , show
    , update
    , view
    )

import AdminOnly.UserGroupAdmin.FoldersTab.Types exposing (..)
import Bootstrap.Button as Button
import Bootstrap.Form as Form
import Bootstrap.Form.Input as Input
import Bootstrap.Grid.Col as Col
import Bootstrap.Modal as Modal
import FlashMessage
import Html exposing (Html, text)
import Html.Attributes exposing (class, value)
import Html.Events exposing (onClick, onInput)
import Http
import Http.Detailed
import Json.Encode as E
import Util.APIError exposing (apiErrorMessage)
import Utils exposing (..)


type alias Model =
    { modalVisibility : Modal.Visibility
    , folder : Folder
    , newFolderName : String
    }


type Msg
    = CloseModal
    | SubmitForm
    | GotResponse (Result (Http.Detailed.Error String) ( Http.Metadata, String ))
    | SetNewFolderName String


init : Folder -> ( Model, Cmd msg )
init folder =
    let
        model =
            { modalVisibility = Modal.hidden
            , folder = folder
            , newFolderName = ""
            }
    in
    ( model, Cmd.none )


update : (Msg -> msg) -> Globals msg -> Msg -> Cmd msg -> Model -> ( Model, Cmd msg )
update embed globals msg onSuccessCmd model =
    case msg of
        CloseModal ->
            ( { model | modalVisibility = Modal.hidden }, Cmd.none )

        SetNewFolderName name ->
            ( { model | newFolderName = name }, Cmd.none )

        SubmitForm ->
            let
                reqParams =
                    [ ( "folder_id", model.folder.id )
                    , ( "folder"
                      , E.encode 0 <|
                            E.object
                                [ ( "name", E.string model.newFolderName ) ]
                      )
                    ]
            in
            ( model
            , Http.post
                { url = "/api/frontend/folders/" ++ model.folder.id ++ "/update"
                , body = formBody globals reqParams
                , expect = Http.Detailed.expectString (embed << GotResponse)
                }
            )

        GotResponse result ->
            case result of
                Ok _ ->
                    ( { model | modalVisibility = Modal.hidden }
                    , Cmd.batch
                        [ globals.flashMessage <| FlashMessage.success "Folder was renamed"
                        , onSuccessCmd
                        ]
                    )

                Err error ->
                    ( model
                    , globals.flashMessage <|
                        FlashMessage.error (apiErrorMessage error "Error renaming the folder")
                    )


show : Model -> Model
show model =
    { model | modalVisibility = Modal.shown }


view : (Msg -> msg) -> Model -> Html msg
view embed model =
    let
        name =
            folderDisplayName model.folder
    in
    Modal.config CloseModal
        |> Modal.hideOnBackdropClick True
        |> Modal.h3 [] [ text <| "Rename folder " ++ name ]
        |> Modal.body []
            [ Form.row []
                [ Form.colLabel [ Col.sm4 ] [ text "New name" ]
                , Form.col [ Col.sm8 ] <|
                    [ Input.text <|
                        [ Input.attrs
                            [ onInput <| SetNewFolderName
                            , value model.newFolderName
                            ]
                        ]
                    ]
                ]
            ]
        |> Modal.footer []
            [ Button.button
                [ Button.secondary
                , Button.attrs
                    [ onClick <| CloseModal
                    , class "mr-auto"
                    ]
                ]
                [ text "Cancel" ]
            , Button.button
                [ Button.success
                , Button.attrs [ onClick <| SubmitForm ]
                ]
                [ text "Rename folder" ]
            ]
        |> Modal.view model.modalVisibility
        |> Html.map embed
