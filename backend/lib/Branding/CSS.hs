{-# LANGUAGE ExtendedDefaultRules #-}
module Branding.CSS (
     signviewBrandingCSS
   , serviceBrandingCSS
   , loginBrandingCSS
   , scriveBrandingCSS
   , domainBrandingCSS
  ) where

import Control.Monad.Trans
import Log as Log
import System.Exit
import System.Process.ByteString.Lazy (readProcessWithExitCode)
import qualified Data.ByteString.Lazy as BSL
import qualified Data.Text as T
import qualified Data.Text.Encoding as TE

import BrandedDomain.BrandedDomain
import Log.Utils
import Theme.Model
import Utils.Color
import Utils.Font

-- Signview branding CSS. Generated using less
signviewBrandingCSS :: (MonadLog m, MonadIO m) => Theme -> m BSL.ByteString
signviewBrandingCSS theme = do
  (code, stdout, stderr) <- liftIO $ do
    readProcessWithExitCode
      "lessc"
      [ "--include-path=frontend/app/less"
      , "-" {-use stdin-}
      ]
      (BSL.fromStrict $ TE.encodeUtf8 $ signviewBrandingLess theme)
  case code of
    ExitSuccess -> do
      return $ stdout
    ExitFailure _ -> do
      logAttention "Creating sign view branding failed"
        $ object ["stderr" `equalsExternalBSL` stderr]
      return BSL.empty

signviewBrandingLess :: Theme -> Text
signviewBrandingLess theme =
  T.unlines
    $  [ "@import 'branding/variables';"
       , -- This is imported so we can use color variables from there
         "@import 'branding/elements';"
       , -- This is imported so we can use some transform functions
         "@import 'runtime/signviewbranding/signviewbrandingdefaultvariables';" -- This will set default signview branding
      --Following settings will overwrite default values
       ]
    <> lessVariablesFromTheme theme
    <> [ -- Only last part will generate some css. Previews ones are just definitions
        "@import 'runtime/signviewbranding/signviewbranding';"]

-- Service branding CSS. Generated using less
serviceBrandingCSS :: (MonadLog m, MonadIO m) => Theme -> m BSL.ByteString
serviceBrandingCSS theme = do
  (code, stdout, stderr) <- liftIO $ do
    readProcessWithExitCode
      "lessc"
      [ "--include-path=frontend/app/less"
      , "-" {-use stdin-}
      ]
      (BSL.fromStrict $ TE.encodeUtf8 $ serviceBrandingLess theme)
  case code of
    ExitSuccess -> do
      return $ stdout
    ExitFailure _ -> do
      logAttention "Creating service branding failed"
        $ object ["stderr" `equalsExternalBSL` stderr]
      return BSL.empty

serviceBrandingLess :: Theme -> Text
serviceBrandingLess theme =
  T.unlines
    $  [ "@import 'branding/variables';"
       , -- This is imported so we can use color variables from there
         "@import 'branding/elements';"
       , -- This is imported so we can use some transform functions
         "@import 'runtime/servicebranding/servicebrandingdefaultvariables';" -- This will set default signview branding
      --Following settings will overwrite default values
       ]
    <> lessVariablesFromTheme theme
    <> [ -- Only last part will generate some css. Previews ones are just definitions
        "@import 'runtime/servicebranding/servicebranding';"]



-- Service branding CSS. Generated using less
loginBrandingCSS :: (MonadLog m, MonadIO m) => Theme -> m BSL.ByteString
loginBrandingCSS theme = do
  (code, stdout, stderr) <- liftIO $ do
    readProcessWithExitCode
      "lessc"
      [ "--include-path=frontend/app/less"
      , "-" {-use stdin-}
      ]
      (BSL.fromStrict $ TE.encodeUtf8 $ loginBrandingLess theme)
  case code of
    ExitSuccess -> do
      return $ stdout
    ExitFailure _ -> do
      logAttention "Creating login branding failed"
        $ object ["stderr" `equalsExternalBSL` stderr]
      return BSL.empty

loginBrandingLess :: Theme -> Text
loginBrandingLess theme =
  T.unlines
    $  [ "@import 'branding/variables';"
       , -- This is imported so we can use color variables from there
         "@import 'branding/elements';"
       , -- This is imported so we can use some transform functions
         "@import 'runtime/loginbranding/loginbrandingdefaultvariables';" -- This will set default signview branding
    --Following settings will overwrite default values
       ]
    <> lessVariablesFromTheme theme
    <> [ -- Only last part will generate some css. Previews ones are just definitions
        "@import 'runtime/loginbranding/loginbranding';"]

-- Scrive branding CSS. Generated using less. No DB involved, hence takes no `Theme`.
-- Should be used only for those pages that mimic the look of the company web ('Expression Engine').
scriveBrandingCSS :: (MonadLog m, MonadIO m) => m BSL.ByteString
scriveBrandingCSS = do
  (code, stdout, stderr) <- liftIO $ do
    readProcessWithExitCode
      "lessc"
      [ "--include-path=frontend/app/less"
      , "-" {-use stdin-}
      ]
      (BSL.fromStrict $ TE.encodeUtf8 scriveBrandingLess)
  case code of
    ExitSuccess -> do
      return $ stdout
    ExitFailure _ -> do
      logAttention "Creating Scrive branding failed"
        $ object ["stderr" `equalsExternalBSL` stderr]
      return BSL.empty

scriveBrandingLess :: Text
scriveBrandingLess =
  T.unlines
    $ [ "@import 'branding/variables';"
      , -- This is imported so we can use color variables from there
        "@import 'branding/elements';"
      , -- This is imported so we can use some transform functions
        "@import 'runtime/scrivebranding/scrivebrandingdefaultvariables';"
      , "@import 'runtime/scrivebranding/scrivebranding';"
      ]

lessVariablesFromTheme :: Theme -> [Text]
lessVariablesFromTheme theme =
  [ bcolor "brandcolor" $ themeBrandColor theme
  , bcolor "brandtextcolor" $ themeBrandTextColor theme
  , bcolor "actioncolor" $ themeActionColor theme
  , bcolor "actiontextcolor" $ themeActionTextColor theme
  , bcolor "actionsecondarycolor" $ themeActionSecondaryColor theme
  , bcolor "actionsecondarytextcolor" $ themeActionSecondaryTextColor theme
  , bcolor "positivecolor" $ themePositiveColor theme
  , bcolor "positivetextcolor" $ themePositiveTextColor theme
  , bcolor "negativecolor" $ themeNegativeColor theme
  , bcolor "negativetextcolor" $ themeNegativeTextColor theme
  , bfont "font" $ themeFont theme
  ]

domainBrandingCSS :: (MonadLog m, MonadIO m) => BrandedDomain -> m BSL.ByteString
domainBrandingCSS bd = do
  (code, stdout, stderr) <- liftIO $ do
    readProcessWithExitCode
      "lessc"
      [ "--include-path=frontend/app/less"
      , "-" {-use stdin-}
      ]
      (BSL.fromStrict $ TE.encodeUtf8 $ domainBrandingLess bd)
  case code of
    ExitSuccess -> do
      return $ stdout
    ExitFailure _ -> do
      logAttention "Creating domain branding failed"
        $ object ["stderr" `equalsExternalBSL` stderr]
      return BSL.empty

domainBrandingLess :: BrandedDomain -> Text
domainBrandingLess bd =
  T.unlines
    $  [ "@import 'branding/variables';"
       , -- This is imported so we can use color variables from there
         "@import 'branding/elements';"
       , -- This is imported so we can use some transform functions
         "@import 'runtime/domainbranding/domainbrandingdefaultvariables';" -- This will set default signview branding
    --Following settings will overwrite default values
       ]
    <> lessVariablesFromDomain bd
    <> [ -- Only last part will generate some css. Previews ones are just definitions
        "@import 'runtime/domainbranding/domainbranding';"]

lessVariablesFromDomain :: BrandedDomain -> [Text]
lessVariablesFromDomain bd =
  [ bcolor "participantcolor1" $ bd ^. #participantColor1
  , bcolor "participantcolor2" $ bd ^. #participantColor2
  , bcolor "participantcolor3" $ bd ^. #participantColor3
  , bcolor "participantcolor4" $ bd ^. #participantColor4
  , bcolor "participantcolor5" $ bd ^. #participantColor5
  , bcolor "participantcolor6" $ bd ^. #participantColor6
  , bcolor "draftcolor" $ bd ^. #draftColor
  , bcolor "cancelledcolor" $ bd ^. #cancelledColor
  , bcolor "initiatedcolor" $ bd ^. #initatedColor
  , bcolor "sentcolor" $ bd ^. #sentColor
  , bcolor "deliveredcolor" $ bd ^. #deliveredColor
  , bcolor "openedcolor" $ bd ^. #openedColor
  , bcolor "reviewedcolor" $ bd ^. #reviewedColor
  , bcolor "signedcolor" $ bd ^. #signedColor
  ]

-- Some sanity checks on data. Note that this are provided by users
bcolor :: Text -> Text -> Text
bcolor n c = if (isValidColor $ T.unpack c) then "@" <> n <> ": " <> c <> ";" else ""

bfont :: Text -> Text -> Text
bfont n c = if (isValidFont $ T.unpack c) then "@" <> n <> ": " <> c <> ";" else ""
