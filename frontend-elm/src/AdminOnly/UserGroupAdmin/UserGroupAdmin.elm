module AdminOnly.UserGroupAdmin.UserGroupAdmin exposing
    ( Model
    , Msg(..)
    , Page
    , fromPage
    , init
    , pageFromModel
    , routeParser
    , update
    , updatePage
    , view
    )

import AdminOnly.UserAdmin.DocumentsTab.DocumentsTab as DocumentsTab exposing (Config(..))
import AdminOnly.UserGroupAdmin.DetailsTab.DetailsTab as DetailsTab
import AdminOnly.UserGroupAdmin.PaymentsTab as PaymentsTab
import AdminOnly.UserGroupAdmin.StatisticsTab as StatisticsTab exposing (Config(..))
import AdminOnly.UserGroupAdmin.StructureTab as StructureTab
import AdminOnly.UserGroupAdmin.UserGroupBrandingTab as UserGroupBrandingTab
import AdminOnly.UserGroupAdmin.UsersTab as UsersTab
import Bootstrap.Tab as Tab
import Bootstrap.Utilities.Spacing as Spacing
import Dict
import Either exposing (Either(..))
import Html exposing (Html,text)
import Maybe as M
import Url.Parser as UP exposing ((</>), (<?>), Parser)
import Url.Parser.Query as UPQ
import Utils exposing (..)
import EnumExtra as Enum


type alias Page =
    { ugid : String
    , tab : Tab
    }


type Tab
    = DetailsTab
    | UsersTab UsersTab.Page
    | StructureTab
    | BrandingTab UserGroupBrandingTab.Page
    | PaymentsTab
    | StatisticsTab StatisticsTab.Page
    | TemplatesTab DocumentsTab.Page
    | DocumentsTab DocumentsTab.Page


type alias Model =
    { page : Page
    , tabState : Tab.State
    , mDetailsTab : Maybe DetailsTab.Model
    , mUsersTab : Maybe UsersTab.Model
    , mStructureTab : Maybe StructureTab.Model
    , mBrandingTab : Maybe UserGroupBrandingTab.State
    , mPaymentsTab : Maybe PaymentsTab.Model
    , mStatisticsTab : Maybe StatisticsTab.Model
    , mTemplatesTab : Maybe DocumentsTab.Model
    , mDocumentsTab : Maybe DocumentsTab.Model
    , xtoken : String
    }


type Msg
    = TabMsg Tab.State
    | DetailsTabMsg DetailsTab.Msg
    | UsersTabMsg UsersTab.Msg
    | StructureTabMsg StructureTab.Msg
    | BrandingTabMsg UserGroupBrandingTab.Msg
    | PaymentsTabMsg PaymentsTab.Msg
    | StatisticsTabMsg StatisticsTab.Msg
    | TemplatesTabMsg DocumentsTab.Msg
    | DocumentsTabMsg DocumentsTab.Msg


init : (Msg -> msg) -> Globals msg -> Page -> ( Model, Cmd msg )
init embed globals page =
    let model =
            { page = Page "" DetailsTab
            , mDetailsTab = Nothing
            , mUsersTab = Nothing
            , mStructureTab = Nothing
            , mBrandingTab = Nothing
            , mPaymentsTab = Nothing
            , mStatisticsTab = Nothing
            , mTemplatesTab = Nothing
            , mDocumentsTab = Nothing
            , tabState = Tab.customInitialState DetailsTab.tabName
            , xtoken = globals.xtoken
            }

    in updatePage embed page model


fromPage : Page -> PageUrl
fromPage page =
    let
        ( tabName, pageUrl ) =
            case page.tab of
                DetailsTab ->
                    ( DetailsTab.tabName, emptyPageUrl )

                UsersTab tabPage ->
                    ( UsersTab.tabName, UsersTab.fromPage tabPage )

                StructureTab ->
                    ( StructureTab.tabName, emptyPageUrl )

                BrandingTab UserGroupBrandingTab.EditBrandingTab  ->
                    ( Enum.toString UserGroupBrandingTab.enumEditTab UserGroupBrandingTab.EditBrandingTab
                    , emptyPageUrl )

                BrandingTab UserGroupBrandingTab.EditThemeTab  ->
                    ( Enum.toString UserGroupBrandingTab.enumEditTab UserGroupBrandingTab.EditThemeTab
                    , emptyPageUrl )

                PaymentsTab ->
                    ( PaymentsTab.tabName, emptyPageUrl )

                StatisticsTab tabPage ->
                    ( StatisticsTab.tabName
                    , StatisticsTab.fromPage tabPage
                    )

                TemplatesTab tabPage ->
                    ( DocumentsTab.tabTemplates, DocumentsTab.fromPage tabPage )

                DocumentsTab tabPage ->
                    ( DocumentsTab.tabName, DocumentsTab.fromPage tabPage )
    in
    { pageUrl | path = [ page.ugid ], fragment = Just tabName }


routeParser : Parser (Page -> a) a
routeParser =
    UP.map
        (\ugid mFragment mSearch mSortBy mOrder mSubTab mSettingsTab mPreviewTab mCurrentThemeID ->
            parseTab mFragment mSearch mSortBy mOrder mSubTab mSettingsTab mPreviewTab mCurrentThemeID
                |> M.withDefault DetailsTab
                |> Page ugid
        )
        (UP.string
            </> UP.fragment identity
            <?> UPQ.string "search"
            <?> UPQ.string "sort_by"
            <?> UPQ.string "order"
            <?> UPQ.string "subTab"
            <?> UPQ.string "settingsTab"
            <?> UPQ.string "previewTab"
            <?> UPQ.string "theme"
        )


parseTab :
    Maybe String
    -> Maybe String
    -> Maybe String
    -> Maybe String
    -> Maybe String
    -> Maybe String
    -> Maybe String
    -> Maybe String
    -> Maybe Tab
parseTab mFragment mSearch mSortBy mOrder mSubTab _ _ _ =
    let
        maping =
            Dict.fromList
                [ ( DetailsTab.tabName, DetailsTab )
                , ( UsersTab.tabName
                  , UsersTab <| UsersTab.pageFromSearchSortByOrder mSearch mSortBy mOrder
                  )
                , ( StructureTab.tabName, StructureTab )
                , ( Enum.toString UserGroupBrandingTab.enumEditTab UserGroupBrandingTab.EditBrandingTab
                  , BrandingTab UserGroupBrandingTab.EditBrandingTab
                  )
                , ( Enum.toString UserGroupBrandingTab.enumEditTab UserGroupBrandingTab.EditThemeTab
                  , BrandingTab UserGroupBrandingTab.EditThemeTab
                  )
                , ( PaymentsTab.tabName, PaymentsTab )
                , ( StatisticsTab.tabName
                  , StatisticsTab <| StatisticsTab.pageFromTab mSubTab
                  )
                , ( DocumentsTab.tabTemplates
                  , TemplatesTab <| DocumentsTab.pageFromSearchSortByOrder mSearch mSortBy mOrder
                  )
                , ( DocumentsTab.tabName
                  , DocumentsTab <| DocumentsTab.pageFromSearchSortByOrder mSearch mSortBy mOrder
                  )
                ]
    in
    mFragment |> Maybe.andThen (\fragment -> Dict.get fragment maping)


pageFromModel : Model -> Maybe Page
pageFromModel model =
    case model.page.tab of
        DetailsTab ->
            Just model.page

        UsersTab _ ->
            model.mUsersTab
                |> M.andThen UsersTab.pageFromModel
                |> M.map (Page model.page.ugid << UsersTab)

        StructureTab ->
            Just model.page

        BrandingTab _ ->
            model.mBrandingTab
                |> M.map (Page model.page.ugid << BrandingTab << UserGroupBrandingTab.pageFromModel)

        PaymentsTab ->
            Just model.page

        StatisticsTab _ ->
            model.mStatisticsTab
                |> M.andThen StatisticsTab.pageFromModel
                |> M.map (Page model.page.ugid << StatisticsTab)

        TemplatesTab _ ->
            model.mTemplatesTab
                |> M.andThen DocumentsTab.pageFromModel
                |> M.map (Page model.page.ugid << TemplatesTab)

        DocumentsTab _ ->
            model.mDocumentsTab
                |> M.andThen DocumentsTab.pageFromModel
                |> M.map (Page model.page.ugid << DocumentsTab)

update : (Msg -> msg) -> Globals msg -> Msg -> Model -> ( Model, Cmd msg )
update embed globals msg model =
    case msg of
        TabMsg state ->
            ( { model | tabState = state }
            , if state == Tab.customInitialState "goback" then
                globals.gotoUserGroupAdminTab

              else
                Cmd.none
            )

        DetailsTabMsg tabMsg ->
            let updateDetailsTab = DetailsTab.update (embed << DetailsTabMsg) globals tabMsg
                (newDetailsTab, cmd) = maybeUpdate updateDetailsTab model.mDetailsTab
            in ({ model | mDetailsTab = newDetailsTab}, cmd)

        UsersTabMsg tabMsg ->
            let updateUsersTab = UsersTab.update (embed << UsersTabMsg) globals tabMsg
                (newUsersTab, cmd) = maybeUpdate updateUsersTab model.mUsersTab
            in ({ model | mUsersTab = newUsersTab}, cmd)

        StructureTabMsg tabMsg ->
            let (newStructureTab, cmd) = maybeUpdate (StructureTab.update tabMsg) model.mStructureTab
            in ({ model | mStructureTab = newStructureTab}, cmd)

        BrandingTabMsg tabMsg ->
            let updateBrandingTab = UserGroupBrandingTab.update (embed << BrandingTabMsg) globals tabMsg
                (newUserGroupBranding, cmd) = maybeUpdate updateBrandingTab model.mBrandingTab
            in ({ model | mBrandingTab = newUserGroupBranding}, cmd)

        PaymentsTabMsg tabMsg ->
            let updatePaymentsTab = PaymentsTab.update (embed << PaymentsTabMsg) globals tabMsg
                (newPaymentsTab, cmd) = maybeUpdate updatePaymentsTab model.mPaymentsTab
            in ({ model | mPaymentsTab = newPaymentsTab}, cmd)

        StatisticsTabMsg tabMsg ->
            let updateStatisticsTab = StatisticsTab.update (embed << StatisticsTabMsg) globals tabMsg
                (newStatisticsTab, cmd) = maybeUpdate updateStatisticsTab model.mStatisticsTab
            in ({ model | mStatisticsTab = newStatisticsTab}, cmd)

        TemplatesTabMsg tabMsg ->
            let updateTemplatesTab = DocumentsTab.update (embed << TemplatesTabMsg) globals tabMsg
                (newTemplatesTab, cmd) = maybeUpdate updateTemplatesTab model.mTemplatesTab
            in ({ model | mTemplatesTab = newTemplatesTab}, cmd)

        DocumentsTabMsg tabMsg ->
            let updateDocumentsTab = DocumentsTab.update (embed << DocumentsTabMsg) globals tabMsg
                (newDocumentsTab, cmd) = maybeUpdate updateDocumentsTab model.mDocumentsTab
            in ({ model | mDocumentsTab = newDocumentsTab}, cmd)


updatePage : (Msg -> msg) -> Page -> Model -> ( Model, Cmd msg )
updatePage embed page model =
    case page.tab of
        DetailsTab ->
            let
                ( tab, tabCmd ) =
                    model.mDetailsTab
                        |> M.map (\t -> ( t, DetailsTab.setUserGroupID (embed << DetailsTabMsg) page.ugid t ))
                        |> M.withDefault
                            (DetailsTab.init (embed << DetailsTabMsg) page.ugid)
            in
            ( { model
                | tabState = Tab.customInitialState DetailsTab.tabName
                , page = page
                , mDetailsTab = Just tab
              }
            , tabCmd
            )

        UsersTab tabPage ->
            let
                ( tab, tabCmd ) =
                    model.mUsersTab
                        |> M.map (UsersTab.updatePage (embed << UsersTabMsg) page.ugid tabPage)
                        |> M.withDefault
                            (UsersTab.init (embed << UsersTabMsg) page.ugid
                                tabPage
                            )
            in
            ( { model
                | mUsersTab = Just tab
                , page = page
                , tabState = Tab.customInitialState UsersTab.tabName
              }
            , tabCmd
            )

        StructureTab ->
            let
                ( tab, tabCmd ) =
                    model.mStructureTab
                        |> M.map (StructureTab.setUserGroupID (embed << StructureTabMsg) page.ugid)
                        |> M.withDefault
                            (StructureTab.init (embed << StructureTabMsg) page.ugid)
            in
            ( { model
                | tabState = Tab.customInitialState StructureTab.tabName
                , page = page
                , mStructureTab = Just tab
              }
            , tabCmd
            )

        BrandingTab tabPage ->
            let
                ( tab, tabCmd ) =
                    model.mBrandingTab
                        |> M.map (UserGroupBrandingTab.updatePage (embed << BrandingTabMsg) { ugid = page.ugid, page = tabPage })
                        |> M.withDefault
                            (UserGroupBrandingTab.init (embed << BrandingTabMsg)
                              { page = tabPage
                              , ugid = page.ugid
                              } )
            in
            ( { model
                | tabState = Tab.customInitialState UserGroupBrandingTab.tabName
                , page = page
                , mBrandingTab = Just tab
              }
            , tabCmd
            )

        PaymentsTab ->
            let
                ( tab, tabCmd ) =
                    model.mPaymentsTab
                        |> M.map (PaymentsTab.setUserGroupID (embed << PaymentsTabMsg) page.ugid)
                        |> M.withDefault
                            (PaymentsTab.init (embed << PaymentsTabMsg) page.ugid)
            in
            ( { model
                | tabState = Tab.customInitialState PaymentsTab.tabName
                , page = page
                , mPaymentsTab = Just tab
              }
            , tabCmd
            )

        StatisticsTab tabPage ->
            let
                ( tab, tabCmd ) =
                    model.mStatisticsTab
                        |> M.map (StatisticsTab.updatePage (embed << StatisticsTabMsg) tabPage <| ConfigForUserGroup page.ugid)
                        |> M.withDefault
                            (StatisticsTab.init (embed << StatisticsTabMsg) tabPage (ConfigForUserGroup page.ugid))
            in
            ( { model
                | tabState = Tab.customInitialState StatisticsTab.tabName
                , page = page
                , mStatisticsTab = Just tab
              }
            , tabCmd
            )

        TemplatesTab tabPage ->
            let
                ( tab, tabCmd ) =
                    model.mTemplatesTab
                        |> M.map (DocumentsTab.updatePage (embed << TemplatesTabMsg) (ConfigForUserGroupTmpl page.ugid) tabPage)
                        |> M.withDefault
                            (DocumentsTab.init (embed << TemplatesTabMsg) (ConfigForUserGroupTmpl page.ugid))
            in
            ( { model
                | mTemplatesTab = Just tab
                , page = page
                , tabState = Tab.customInitialState DocumentsTab.tabTemplates
              }
            , tabCmd
            )

        DocumentsTab tabPage ->
            let
                ( tab, tabCmd ) =
                    model.mDocumentsTab
                        |> M.map (DocumentsTab.updatePage (embed << DocumentsTabMsg) (ConfigForUserGroupDocs page.ugid) tabPage)
                        |> M.withDefault
                            (DocumentsTab.init (embed << DocumentsTabMsg) (ConfigForUserGroupDocs page.ugid))
            in
            ( { model
                | mDocumentsTab = Just tab
                , page = page
                , tabState = Tab.customInitialState DocumentsTab.tabName
              }
            , tabCmd
            )


view : (Msg -> msg) -> Model -> Html msg
view embed model =
    Tab.config (embed << TabMsg)
        |> Tab.useHash True
        |> Tab.items
            [ Tab.item
                { id = "goback"
                , link = Tab.link [] [ text "<" ]
                , pane = Tab.pane [ Spacing.mt3 ] []
                }
            , Tab.item
                { id = DetailsTab.tabName
                , link = Tab.link [] [ text "Company details" ]
                , pane =
                    Tab.pane [ Spacing.mt3 ] <|
                        [ model.mDetailsTab
                            |> M.map (DetailsTab.view <| embed << DetailsTabMsg)
                            |> M.withDefault viewError
                        ]
                }
            , Tab.item
                { id = UsersTab.tabName
                , link = Tab.link [] [ text "Company users" ]
                , pane =
                    Tab.pane [ Spacing.mt3 ] <|
                        [ model.mUsersTab
                            |> M.map (UsersTab.view <| embed << UsersTabMsg)
                            |> M.withDefault viewError
                        ]
                }
            , Tab.item
                { id = StructureTab.tabName
                , link = Tab.link [] [ text "Company structure" ]
                , pane =
                    Tab.pane [ Spacing.mt3 ] <|
                        [ model.mStructureTab
                            |> M.map (StructureTab.view <| embed << StructureTabMsg)
                            |> M.withDefault viewError
                        ]
                }
            , Tab.item
                { id = "branding"
                , link = Tab.link [] [ text "Branding" ]
                , pane =
                    Tab.pane [ Spacing.mt3 ] <|
                        [ model.mBrandingTab
                            |> M.map (UserGroupBrandingTab.view <| embed << BrandingTabMsg)
                            |> M.withDefault viewError
                        ]
                }
            , Tab.item
                { id = StatisticsTab.tabName
                , link = Tab.link [] [ text "Statistics" ]
                , pane =
                    Tab.pane [ Spacing.mt3 ] <|
                        [ model.mStatisticsTab
                            |> M.map (StatisticsTab.view <| embed << StatisticsTabMsg)
                            |> M.withDefault viewError
                        ]
                }
            , Tab.item
                { id = PaymentsTab.tabName
                , link = Tab.link [] [ text "Payments" ]
                , pane =
                    Tab.pane [ Spacing.mt3 ] <|
                        [ model.mPaymentsTab
                            |> M.map (PaymentsTab.view <| embed << PaymentsTabMsg)
                            |> M.withDefault viewError
                        ]
                }
            , Tab.item
                { id = DocumentsTab.tabTemplates
                , link = Tab.link [] [ text "Templates" ]
                , pane =
                    Tab.pane [ Spacing.mt3 ] <|
                        [ model.mTemplatesTab
                            |> M.map (DocumentsTab.view <| embed << TemplatesTabMsg)
                            |> M.withDefault viewError
                        ]
                }
            , Tab.item
                { id = DocumentsTab.tabName
                , link = Tab.link [] [ text "Documents" ]
                , pane =
                    Tab.pane [ Spacing.mt3 ] <|
                        [ model.mDocumentsTab
                            |> M.map (DocumentsTab.view <| embed << DocumentsTabMsg)
                            |> M.withDefault viewError
                        ]
                }
            ]
        |> Tab.view model.tabState
