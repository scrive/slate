module BrandedDomainTest (brandedDomainTests) where

import Test.Framework

import BrandedDomain.Model
import DB
import TestingUtil
import TestKontra
import Theme.Model
import User.Model
import UserGroup.Types

brandedDomainTests :: TestEnvSt -> Test
brandedDomainTests env = testGroup
  "BrandedDomainsTest"
  [ testThat "test_brandedDomainCreateUpdate"     env test_brandedDomainCreateUpdate
  , testThat "test_brandedDomainAssociatedDomain" env test_brandedDomainAssociatedDomain
  , testThat "test_brandedDomainAmbiguous"        env test_brandedDomainAmbiguous
  , testThat "test_brandedDomainCanChangeThemeOrSettingsOfMainDomain"
             env
             test_brandedDomainCanChangeThemeOrSettingsOfMainDomain
  ]

test_brandedDomainCreateUpdate :: TestEnv ()
test_brandedDomainCreateUpdate = do
  bdID <- dbUpdate $ NewBrandedDomain

  bd   <- dbQuery $ GetBrandedDomainByID bdID
  let nbd = set #bdUrl "http://localhost:8000" bd
  dbUpdate $ UpdateBrandedDomain nbd

  xbd <- dbQuery $ GetBrandedDomainByID bdID

  assertEqual "Branded domain round trips to database" nbd xbd

  wbd <- dbQuery $ GetBrandedDomainByURL (nbd ^. #bdUrl)

  assertEqual "GetBrandedDomainByURL works" nbd wbd

test_brandedDomainAssociatedDomain :: TestEnv ()
test_brandedDomainAssociatedDomain = do
  ugid <- ugID <$> addNewUserGroup
  bdID <- dbUpdate $ NewBrandedDomain
  bd   <- dbQuery $ GetBrandedDomainByID bdID
  let nbd = set #bdUrl "http://localhost:8000" bd
  dbUpdate $ UpdateBrandedDomain nbd

  pwd       <- createPassword "password_8866"

  Just user <- createNewUser ("Andrzej", "Rybczak")
                             "andrzej@scrive.com"
                             (Just pwd)
                             (ugid, True)
                             defaultLang
                             bdID
                             AccountRequest

  wbd <- dbQuery $ GetBrandedDomainByUserID (userid user)

  assertEqual "GetBrandedDomainByUserID works" nbd wbd

test_brandedDomainAmbiguous :: TestEnv ()
test_brandedDomainAmbiguous = do
  mainbd <- dbQuery $ GetMainBrandedDomain
  _bdid0 <- dbUpdate $ NewBrandedDomain
  wbd0   <- dbQuery $ GetBrandedDomainByURL ("http://url")

  assertEqual "GetBrandedDomainByURL with no url does not match" mainbd wbd0

  bdid1 <- dbUpdate $ NewBrandedDomain
  bd1   <- dbQuery $ GetBrandedDomainByID bdid1
  let nbd1 = set #bdUrl "http://localhost:8000" bd1
  dbUpdate $ UpdateBrandedDomain nbd1

  bdid2 <- dbUpdate $ NewBrandedDomain
  bd2   <- dbQuery $ GetBrandedDomainByID bdid2
  let nbd2 = set #bdUrl "http://localhost" bd2
  dbUpdate $ UpdateBrandedDomain nbd2


  wbd1 <- dbQuery $ GetBrandedDomainByURL (nbd1 ^. #bdUrl)
  wbd2 <- dbQuery $ GetBrandedDomainByURL (nbd2 ^. #bdUrl)
  wbd3 <- dbQuery $ GetBrandedDomainByURL ("")

  assertEqual "GetBrandedDomainByURL works" nbd1   wbd1
  assertEqual "GetBrandedDomainByURL works" nbd2   wbd2
  assertEqual "GetBrandedDomainByURL works" mainbd wbd3


test_brandedDomainCanChangeThemeOrSettingsOfMainDomain :: TestEnv ()
test_brandedDomainCanChangeThemeOrSettingsOfMainDomain = do
  mainbd1 <- dbQuery $ GetMainBrandedDomain
  void $ dbUpdate $ UpdateBrandedDomain (set #bdMailTheme (mainbd1 ^. #bdLoginTheme) mainbd1)
  mainbd2 <- dbQuery $ GetMainBrandedDomain
  assertEqual "Can change main domain " mainbd1 mainbd2

  mailTheme1 <- dbQuery $ GetTheme (mainbd1 ^. #bdMailTheme)
  False      <- dbUpdate $ UpdateThemeForDomain (mainbd1 ^. #bdid) $ mailTheme1
    { themeBrandTextColor = "#222345"
    }
  mailTheme2 <- dbQuery $ GetTheme (mainbd1 ^. #bdMailTheme)
  assertEqual "Can change mail theme of main domain " mailTheme1 mailTheme2

  loginTheme1 <- dbQuery $ GetTheme (mainbd1 ^. #bdLoginTheme)
  False       <- dbUpdate $ UpdateThemeForDomain (mainbd1 ^. #bdid) $ loginTheme1
    { themeBrandColor = "#123456"
    }
  loginTheme2 <- dbQuery $ GetTheme (mainbd1 ^. #bdLoginTheme)
  assertEqual "Can change login theme of main domain " loginTheme1 loginTheme2

  serviceTheme1 <- dbQuery $ GetTheme (mainbd1 ^. #bdServiceTheme)
  False         <- dbUpdate $ UpdateThemeForDomain (mainbd1 ^. #bdid) $ serviceTheme1
    { themeName = "New name"
    }
  serviceTheme2 <- dbQuery $ GetTheme (mainbd1 ^. #bdServiceTheme)
  assertEqual "Can change service theme of main domain " serviceTheme1 serviceTheme2

  signviewTheme1 <- dbQuery $ GetTheme (mainbd1 ^. #bdSignviewTheme)
  False          <- dbUpdate $ UpdateThemeForDomain (mainbd1 ^. #bdid) signviewTheme1
  signviewTheme2 <- dbQuery $ GetTheme (mainbd1 ^. #bdSignviewTheme)
  assertEqual "Can change signview theme of main domain " signviewTheme1 signviewTheme2

  void $dbUpdate $ DeleteThemeOwnedByDomain (mainbd1 ^. #bdid) (mainbd1 ^. #bdSignviewTheme)
  signviewTheme3 <- dbQuery $ GetTheme (mainbd1 ^. #bdSignviewTheme)
  assertEqual "Can delete theme of main domain  " signviewTheme1 signviewTheme3
