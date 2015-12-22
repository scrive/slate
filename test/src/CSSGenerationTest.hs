module CSSGenerationTest(
    cssGenerationTests
) where

import Test.Framework
import qualified Data.ByteString.Lazy as BSL

import BrandedDomain.BrandedDomain
import Branding.CSS
import Context
import DB
import KontraPrelude
import TestingUtil
import TestKontra as T
import Theme.Model

cssGenerationTests :: TestEnvSt -> Test
cssGenerationTests env = testGroup "CSSGeneration" [
    testThat "Signview branding generation" env testSignviewBrandingGeneration
  , testThat "Service  branding generation" env testServiceBrandingGeneration
  , testThat "Login  branding generation"   env testLoginBrandingGeneration
  , testThat "Domain  branding generation"  env testDomainBrandingGeneration

  ]

testSignviewBrandingGeneration:: TestEnv ()
testSignviewBrandingGeneration = do
  bd <- ctxbrandeddomain <$> mkContext def
  theme <- dbQuery $ GetTheme $ (bdSignviewTheme $ bd)
  emptyBrandingCSS <- signviewBrandingCSS "" theme
  assertBool "CSS generated for signview branding is not empty" (not $ BSL.null $ emptyBrandingCSS)

testServiceBrandingGeneration:: TestEnv ()
testServiceBrandingGeneration = do
  bd <- ctxbrandeddomain <$> mkContext def
  theme <- dbQuery $ GetTheme $ (bdServiceTheme $ bd)
  emptyBrandingCSS <- serviceBrandingCSS "" theme
  assertBool "CSS generated for service branding is not empty" (not $ BSL.null $ emptyBrandingCSS)

testLoginBrandingGeneration:: TestEnv ()
testLoginBrandingGeneration = do
  bd <- ctxbrandeddomain <$> mkContext def
  theme <- dbQuery $ GetTheme $ (bdLoginTheme $ bd)
  emptyBrandingCSS <- loginBrandingCSS "" theme
  assertBool "CSS generated for login branding is not empty" (not $ BSL.null $ emptyBrandingCSS)

testDomainBrandingGeneration:: TestEnv ()
testDomainBrandingGeneration = do
  bd <- ctxbrandeddomain <$> mkContext def
  emptyBrandingCSS <- domainBrandingCSS bd
  assertBool "CSS generated for domain branding is not empty" (not $ BSL.null $ emptyBrandingCSS)

