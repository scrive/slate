module CompanyBrandingTest(
    companyBrandingTests
) where

import Control.Applicative
import Test.Framework

import BrandedDomain.BrandedDomain
import Context
import Theme.Model
import Utils.Default

import BrandedDomain.Model
import Company.Model
import DB
import TestingUtil
import TestKontra
import Happstack.Server hiding (simpleHTTP)
import Company.CompanyControl
import Text.JSON
import qualified Data.ByteString.UTF8 as BSU8
import Utils.String
import Data.Unjson
import Theme.View
import User.Model
import Company.CompanyUI

companyBrandingTests :: TestEnvSt -> Test
companyBrandingTests env = testGroup "CompanyBranding" [
    testThat "Test that user can fetch company branding" env testFetchCompanyBranding
  , testThat "Test that user can fetch domain themes (used by previews)" env testFetchDomainThemes
  , testThat "Test that admin can change company themes" env testUpdateCompanyTheme
  , testThat "Test that admin can delete company themes" env testDeleteCompanyTheme
  , testThat "Test that normal user cant delete or change company themes" env testNormalUserCantChangeOrDeleteTheme
  , testThat "Test that admin can change company branding additional details " env testChangeCompanyUI
  , testThat "Test that normal user can't deleted or change company UI" env testNormalUseCantChangeCompanyUI
  ]


testFetchCompanyBranding:: TestEnv ()
testFetchCompanyBranding = do
  company <- addNewCompany
  Just user <- addNewCompanyUser "Mariusz" "Rak" "mariusz+ut@scrive.com" (companyid company)
  ctx <- (\c -> c { ctxmaybeuser = Just user })
    <$> mkContext defaultValue
  req1 <- mkRequest GET []
  (rsp1, _) <- runTestKontra req1 ctx $ handleGetCompanyBranding Nothing
  case decode (BSU8.toString $ concatChunks $ rsBody rsp1) of
               Ok (_ :: JSValue) -> return ()
               _ -> assertFailure "Response from handleGetCompanyBranding is not a valid JSON"

  req2 <- mkRequest GET []
  (rsp2, _) <- runTestKontra req2 ctx $ handleGetThemes Nothing
  case decode (BSU8.toString $ concatChunks $ rsBody rsp2) of
               Ok (_ :: JSValue) -> return ()
               _ -> assertFailure "Response from handleGetThemes is not a valid JSON"

testFetchDomainThemes:: TestEnv ()
testFetchDomainThemes = do
  ctx <-  mkContext defaultValue
  req1 <- mkRequest GET []
  (rsp1, _) <- runTestKontra req1 ctx $ handleGetDomainThemes
  case decode (BSU8.toString $ concatChunks $ rsBody rsp1) of
               Ok (_ :: JSValue) -> return ()
               _ -> assertFailure "Response from handleGetDomainThemes is not a valid JSON"

testUpdateCompanyTheme:: TestEnv ()
testUpdateCompanyTheme = do
  company <- addNewCompany
  Just user <- addNewCompanyUser "Mariusz" "Rak" "mariusz+ut@scrive.com" (companyid company)
  ctx <- (\c -> c { ctxmaybeuser = Just user })
    <$> mkContext defaultValue

  mainbd <- dbQuery $ GetMainBrandedDomain
  mailTheme <- dbQuery $ GetTheme (bdMailTheme mainbd)
  newTheme <- dbUpdate $ InsertNewThemeForCompany (companyid company) mailTheme
  let newChangedTheme1 =  newTheme {themeBrandColor = "#12399a"}
  let newChangedThemeStr1 =  unjsonToByteStringLazy' (Options { pretty = True, indent = 2, nulls = True }) unjsonTheme newChangedTheme1
  req1 <- mkRequest POST [("theme", inTextBS $ newChangedThemeStr1)]
  ((), _) <- runTestKontra req1 ctx $ handleUpdateTheme Nothing (themeID newChangedTheme1)
  newThemeChangedFromDB <- dbQuery $ GetTheme (themeID newTheme)
  assertEqual "Theme color has been changed" "#12399a" (themeBrandColor newThemeChangedFromDB)


  --Check if invalid color wil raise an exception
  let newChangedTheme2 =  newTheme {themeBrandColor = "bla bla"}
  let newChangedThemeStr2 =  unjsonToByteStringLazy' (Options { pretty = True, indent = 2, nulls = True }) unjsonTheme newChangedTheme2
  req2 <- mkRequest POST [("theme", inTextBS $ newChangedThemeStr2)]
  assertRaisesDBException $ do
    ((), _) <- runTestKontra req2 ctx $ handleUpdateTheme Nothing (themeID newChangedTheme2)
    return ()

  --Check if invalid font wil raise an exception
  let newChangedTheme3 =  newTheme {themeFont = "bla bla"}
  let newChangedThemeStr3 =  unjsonToByteStringLazy' (Options { pretty = True, indent = 2, nulls = True }) unjsonTheme newChangedTheme3
  req3 <- mkRequest POST [("theme", inTextBS $ newChangedThemeStr3)]
  assertRaisesDBException $ do
    ((), _) <- runTestKontra req3 ctx $ handleUpdateTheme Nothing (themeID newChangedTheme3)
    return ()

testDeleteCompanyTheme :: TestEnv ()
testDeleteCompanyTheme = do
  company <- addNewCompany
  Just user <- addNewCompanyUser "Mariusz" "Rak" "mariusz+ut@scrive.com" (companyid company)
  ctx <- (\c -> c { ctxmaybeuser = Just user })
    <$> mkContext defaultValue
  mainbd <- dbQuery $ GetMainBrandedDomain
  mailTheme <- dbQuery $ GetTheme (bdMailTheme mainbd)
  newTheme <- dbUpdate $ InsertNewThemeForCompany (companyid company) mailTheme
  req1 <- mkRequest POST []
  ((), _) <- runTestKontra req1 ctx $ handleDeleteTheme Nothing (themeID newTheme)
  assertRaisesDBException $ do
    _ <- dbQuery $ GetTheme (themeID newTheme)
    return ()
  return ()


testNormalUserCantChangeOrDeleteTheme:: TestEnv ()
testNormalUserCantChangeOrDeleteTheme = do
  company <- addNewCompany
  Just user1 <- addNewCompanyUser "Mariusz" "Rak" "mariusz+ut@scrive.com" (companyid company)
  True <-  dbUpdate $ SetUserCompanyAdmin (userid user1) False
  Just user2 <- dbQuery $ GetUserByID (userid user1)

  ctx <- (\c -> c { ctxmaybeuser = Just user2 })
    <$> mkContext defaultValue

  mainbd <- dbQuery $ GetMainBrandedDomain
  mailTheme <- dbQuery $ GetTheme (bdMailTheme mainbd)
  newTheme <- dbUpdate $ InsertNewThemeForCompany (companyid company) mailTheme
  let newChangedTheme1 =  newTheme {themeBrandColor = "#12399a"}
  let newChangedThemeStr1 =  unjsonToByteStringLazy' (Options { pretty = True, indent = 2, nulls = True }) unjsonTheme newChangedTheme1
  req1 <- mkRequest POST [("theme", inTextBS $ newChangedThemeStr1)]
  -- We should get exception when updating company theme, when not admin

  assertRaisesInternalError $ do
    ((), _) <- runTestKontra req1 ctx $ handleUpdateTheme Nothing (themeID newChangedTheme1)
    return ()

  -- Theme should also not be changed
  newThemeChangedFromDB <- dbQuery $ GetTheme (themeID newTheme)
  assertEqual  "Theme color is same" (themeBrandColor mailTheme) (themeBrandColor newThemeChangedFromDB)

  -- We should also get expection when trying to delete theme
  assertRaisesInternalError $ do
    ((), _) <- runTestKontra req1 ctx $ handleDeleteTheme Nothing (themeID newTheme)
    return ()


testChangeCompanyUI:: TestEnv ()
testChangeCompanyUI = do
  company <- addNewCompany
  Just user <- addNewCompanyUser "Mariusz" "Rak" "mariusz+ut@scrive.com" (companyid company)
  ctx <- (\c -> c { ctxmaybeuser = Just user })
    <$> mkContext defaultValue

  mainbd <- dbQuery $ GetMainBrandedDomain
  mailTheme <- dbQuery $ GetTheme (bdMailTheme mainbd)
  newTheme1 <- dbUpdate $ InsertNewThemeForCompany (companyid company) mailTheme
  newTheme2 <- dbUpdate $ InsertNewThemeForCompany (companyid company) mailTheme
  newTheme3 <- dbUpdate $ InsertNewThemeForCompany (companyid company) mailTheme

  companyui <- dbQuery $ GetCompanyUI (companyid company)
  let newCompanyUI =  companyui {
                          companyMailTheme = Just $ themeID newTheme1
                        , companySignviewTheme = Just $ themeID newTheme2
                        , companyServiceTheme = Just $ themeID newTheme3
                        , companyBrowserTitle = Just "Wow"
                      }
  let newCompanyUIStr1 =  unjsonToByteStringLazy' (Options { pretty = True, indent = 2, nulls = True }) unjsonCompanyUI newCompanyUI
  req1 <- mkRequest POST [("companyui", inTextBS $ newCompanyUIStr1)]
  ((), _) <- runTestKontra req1 ctx $ handleChangeCompanyBranding Nothing
  companyUIAfter <- dbQuery $ GetCompanyUI (companyid company)
  assertEqual "Company UI has been changed" companyUIAfter newCompanyUI


testNormalUseCantChangeCompanyUI:: TestEnv ()
testNormalUseCantChangeCompanyUI = do
  company <- addNewCompany
  Just user1 <- addNewCompanyUser "Mariusz" "Rak" "mariusz+ut@scrive.com" (companyid company)
  True <-  dbUpdate $ SetUserCompanyAdmin (userid user1) False
  Just user2 <- dbQuery $ GetUserByID (userid user1)
  ctx <- (\c -> c { ctxmaybeuser = Just user2 })
    <$> mkContext defaultValue

  mainbd <- dbQuery $ GetMainBrandedDomain
  mailTheme <- dbQuery $ GetTheme (bdMailTheme mainbd)
  newTheme1 <- dbUpdate $ InsertNewThemeForCompany (companyid company) mailTheme
  newTheme2 <- dbUpdate $ InsertNewThemeForCompany (companyid company) mailTheme
  newTheme3 <- dbUpdate $ InsertNewThemeForCompany (companyid company) mailTheme

  companyui <- dbQuery $ GetCompanyUI (companyid company)
  let newCompanyUI =  companyui {
                          companyMailTheme = Just $ themeID newTheme1
                        , companySignviewTheme = Just $ themeID newTheme2
                        , companyServiceTheme = Just $ themeID newTheme3
                        , companyBrowserTitle = Just "Wow"
                      }
  let newCompanyUIStr1 =  unjsonToByteStringLazy' (Options { pretty = True, indent = 2, nulls = True }) unjsonCompanyUI newCompanyUI
  req1 <- mkRequest POST [("companyui", inTextBS $ newCompanyUIStr1)]
  assertRaisesInternalError $ do
    ((), _) <- runTestKontra req1 ctx $ handleChangeCompanyBranding Nothing
    return ()
  companyUIAfter <- dbQuery $ GetCompanyUI (companyid company)
  assertEqual "Company UI has been not been changed" companyUIAfter companyui

