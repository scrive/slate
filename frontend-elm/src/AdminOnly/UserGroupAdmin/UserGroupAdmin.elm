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
import Html exposing (text)
import Maybe as M
import Monocle.Optional exposing (Optional)
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


detailsModelLens : Optional Model DetailsTab.Model
detailsModelLens =
    Optional .mDetailsTab
        (\b a -> { a | mDetailsTab = Just b })


usersTabModelLens : Optional Model UsersTab.Model
usersTabModelLens =
    Optional .mUsersTab
        (\b a -> { a | mUsersTab = Just b })


structureTabModelLens : Optional Model StructureTab.Model
structureTabModelLens =
    Optional .mStructureTab
        (\b a -> { a | mStructureTab = Just b })


paymentsTabModelLens : Optional Model PaymentsTab.Model
paymentsTabModelLens =
    Optional .mPaymentsTab
        (\b a -> { a | mPaymentsTab = Just b })


statisticsTabModelLens : Optional Model StatisticsTab.Model
statisticsTabModelLens =
    Optional .mStatisticsTab
        (\b a -> { a | mStatisticsTab = Just b })


templatesTabModelLens : Optional Model DocumentsTab.Model
templatesTabModelLens =
    Optional .mTemplatesTab
        (\b a -> { a | mTemplatesTab = Just b })


documentsTabModelLens : Optional Model DocumentsTab.Model
documentsTabModelLens =
    Optional .mDocumentsTab
        (\b a -> { a | mDocumentsTab = Just b })


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


init : Globals msg -> Page -> ( Model, Cmd Msg )
init globals page =
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

    in updatePage page model


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

update : Globals msg -> Msg -> Model -> ( Model, Action msg Msg )
update globals =
    let
        updateDetails =
            liftOptionalUpdateHandler
                detailsModelLens
                DetailsTabMsg
            <|
                DetailsTab.update globals

        updateUsers =
            liftOptionalUpdateHandler
                usersTabModelLens
                UsersTabMsg
            <|
                UsersTab.update globals

        updateStructure =
            liftOptionalUpdateHandler
                structureTabModelLens
                StructureTabMsg
                StructureTab.update

        updateUserGroupBranding : UserGroupBrandingTab.Msg -> Model -> ( Model, Cmd (Either msg Msg) )
        updateUserGroupBranding msg model =
            case model.mBrandingTab of
              Nothing -> (model, Cmd.none)  -- this really should be an internal error
              Just brandingTab ->
                let (newBrandingTab, cmd) =
                      UserGroupBrandingTab.update
                        { embed = Right << BrandingTabMsg
                        , presentFlashMessage = Cmd.map Left << globals.flashMessage
                        , formBody = formBody globals
                        } msg brandingTab
                in ({ model | mBrandingTab = Just newBrandingTab }, cmd)

        updatePayments =
            liftOptionalUpdateHandler
                paymentsTabModelLens
                PaymentsTabMsg
            <|
                PaymentsTab.update globals

        updateStatistics =
            liftOptionalUpdateHandler
                statisticsTabModelLens
                StatisticsTabMsg
            <|
                StatisticsTab.update globals

        updateTemplates =
            liftOptionalUpdateHandler
                templatesTabModelLens
                TemplatesTabMsg
            <|
                DocumentsTab.update globals

        updateDocuments =
            liftOptionalUpdateHandler
                documentsTabModelLens
                DocumentsTabMsg
            <|
                DocumentsTab.update globals
    in
    \msg model ->
        case msg of
            TabMsg state ->
                ( { model | tabState = state }
                , if state == Tab.customInitialState "goback" then
                    outerCmd <| globals.gotoUserGroupAdminTab

                  else
                    Cmd.none
                )

            DetailsTabMsg tabMsg ->
                updateDetails tabMsg model

            UsersTabMsg tabMsg ->
                updateUsers tabMsg model

            StructureTabMsg tabMsg ->
                updateStructure tabMsg model

            BrandingTabMsg tabMsg ->
                updateUserGroupBranding tabMsg model

            PaymentsTabMsg tabMsg ->
                updatePayments tabMsg model

            StatisticsTabMsg tabMsg ->
                updateStatistics tabMsg model

            TemplatesTabMsg tabMsg ->
                updateTemplates tabMsg model

            DocumentsTabMsg tabMsg ->
                updateDocuments tabMsg model


updatePage : Page -> Model -> ( Model, Cmd Msg )
updatePage page model =
    case page.tab of
        DetailsTab ->
            let
                ( tab, tabCmd ) =
                    model.mDetailsTab
                        |> M.map (\t -> ( t, DetailsTab.setUserGroupID page.ugid t ))
                        |> M.withDefault
                            (DetailsTab.init page.ugid)
            in
            ( { model
                | tabState = Tab.customInitialState DetailsTab.tabName
                , page = page
                , mDetailsTab = Just tab
              }
            , liftCmd DetailsTabMsg tabCmd
            )

        UsersTab tabPage ->
            let
                ( tab, tabCmd ) =
                    model.mUsersTab
                        |> M.map (UsersTab.updatePage page.ugid tabPage)
                        |> M.withDefault
                            (UsersTab.init page.ugid
                                tabPage
                            )
            in
            ( { model
                | mUsersTab = Just tab
                , page = page
                , tabState = Tab.customInitialState UsersTab.tabName
              }
            , liftCmd UsersTabMsg tabCmd
            )

        StructureTab ->
            let
                ( tab, tabCmd ) =
                    model.mStructureTab
                        |> M.map (\t -> StructureTab.setUserGroupID page.ugid t)
                        |> M.withDefault
                            (StructureTab.init page.ugid)
            in
            ( { model
                | tabState = Tab.customInitialState StructureTab.tabName
                , page = page
                , mStructureTab = Just tab
              }
            , liftCmd StructureTabMsg tabCmd
            )

        BrandingTab tabPage ->
            let
                ( tab, tabCmd ) =
                    model.mBrandingTab
                        |> M.map (UserGroupBrandingTab.updatePage { ugid = page.ugid, page = tabPage, embed = BrandingTabMsg })
                        |> M.withDefault
                            (UserGroupBrandingTab.init
                              { page = tabPage
                              , ugid = page.ugid
                              , embed = BrandingTabMsg
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
                        |> M.map (\t -> PaymentsTab.setUserGroupID page.ugid t)
                        |> M.withDefault
                            (PaymentsTab.init page.ugid)
            in
            ( { model
                | tabState = Tab.customInitialState PaymentsTab.tabName
                , page = page
                , mPaymentsTab = Just tab
              }
            , liftCmd PaymentsTabMsg tabCmd
            )

        StatisticsTab tabPage ->
            let
                ( tab, tabCmd ) =
                    model.mStatisticsTab
                        |> M.map (StatisticsTab.updatePage tabPage <| ConfigForUserGroup page.ugid)
                        |> M.withDefault
                            (StatisticsTab.init tabPage (ConfigForUserGroup page.ugid))
            in
            ( { model
                | tabState = Tab.customInitialState StatisticsTab.tabName
                , page = page
                , mStatisticsTab = Just tab
              }
            , liftCmd StatisticsTabMsg tabCmd
            )

        TemplatesTab tabPage ->
            let
                ( tab, tabCmd ) =
                    model.mTemplatesTab
                        |> M.map (DocumentsTab.updatePage (ConfigForUserGroupTmpl page.ugid) tabPage)
                        |> M.withDefault
                            (DocumentsTab.init (ConfigForUserGroupTmpl page.ugid))
            in
            ( { model
                | mTemplatesTab = Just tab
                , page = page
                , tabState = Tab.customInitialState DocumentsTab.tabTemplates
              }
            , liftCmd TemplatesTabMsg tabCmd
            )

        DocumentsTab tabPage ->
            let
                ( tab, tabCmd ) =
                    model.mDocumentsTab
                        |> M.map (DocumentsTab.updatePage (ConfigForUserGroupDocs page.ugid) tabPage)
                        |> M.withDefault
                            (DocumentsTab.init (ConfigForUserGroupDocs page.ugid))
            in
            ( { model
                | mDocumentsTab = Just tab
                , page = page
                , tabState = Tab.customInitialState DocumentsTab.tabName
              }
            , liftCmd DocumentsTabMsg tabCmd
            )


view : Model -> Render msg Msg
view model =
    Tab.config (Either.Right << TabMsg)
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
                            |> M.map (innerHtml << liftHtml DetailsTabMsg << DetailsTab.view)
                            |> M.withDefault viewError
                        ]
                }
            , Tab.item
                { id = UsersTab.tabName
                , link = Tab.link [] [ text "Company users" ]
                , pane =
                    Tab.pane [ Spacing.mt3 ] <|
                        [ model.mUsersTab
                            |> M.map (innerHtml << liftHtml UsersTabMsg << UsersTab.view)
                            |> M.withDefault viewError
                        ]
                }
            , Tab.item
                { id = StructureTab.tabName
                , link = Tab.link [] [ text "Company structure" ]
                , pane =
                    Tab.pane [ Spacing.mt3 ] <|
                        [ model.mStructureTab
                            |> M.map (innerHtml << liftHtml StructureTabMsg << StructureTab.view)
                            |> M.withDefault viewError
                        ]
                }
            , Tab.item
                { id = "branding"
                , link = Tab.link [] [ text "Branding" ]
                , pane =
                    Tab.pane [ Spacing.mt3 ] <|
                        [ model.mBrandingTab
                            |> M.map (innerHtml << liftHtml BrandingTabMsg << UserGroupBrandingTab.view)
                            |> M.withDefault viewError
                        ]
                }
            , Tab.item
                { id = StatisticsTab.tabName
                , link = Tab.link [] [ text "Statistics" ]
                , pane =
                    Tab.pane [ Spacing.mt3 ] <|
                        [ model.mStatisticsTab
                            |> M.map (innerHtml << liftHtml StatisticsTabMsg << StatisticsTab.view)
                            |> M.withDefault viewError
                        ]
                }
            , Tab.item
                { id = PaymentsTab.tabName
                , link = Tab.link [] [ text "Payments" ]
                , pane =
                    Tab.pane [ Spacing.mt3 ] <|
                        [ model.mPaymentsTab
                            |> M.map (innerHtml << liftHtml PaymentsTabMsg << PaymentsTab.view)
                            |> M.withDefault viewError
                        ]
                }
            , Tab.item
                { id = DocumentsTab.tabTemplates
                , link = Tab.link [] [ text "Templates" ]
                , pane =
                    Tab.pane [ Spacing.mt3 ] <|
                        [ model.mTemplatesTab
                            |> M.map (innerHtml << liftHtml TemplatesTabMsg << DocumentsTab.view)
                            |> M.withDefault viewError
                        ]
                }
            , Tab.item
                { id = DocumentsTab.tabName
                , link = Tab.link [] [ text "Documents" ]
                , pane =
                    Tab.pane [ Spacing.mt3 ] <|
                        [ model.mDocumentsTab
                            |> M.map (innerHtml << liftHtml DocumentsTabMsg << DocumentsTab.view)
                            |> M.withDefault viewError
                        ]
                }
            ]
        |> Tab.view model.tabState
