module Doc.API.V2.Calls.DocumentPostCallsTest (apiV2DocumentPostCallsTests) where

import Data.Default
import Happstack.Server
import Test.Framework

import Company.Model
import Context
import DB.Query (dbUpdate)
import Doc.API.V2.AesonTestUtils
import Doc.API.V2.Calls.CallsTestUtils
import Doc.API.V2.Calls.DocumentGetCalls (docApiV2Get)
import Doc.API.V2.Calls.DocumentPostCalls
import Doc.API.V2.Calls.SignatoryCalls (docApiV2SigSign)
import Doc.API.V2.Mock.TestUtils
import Doc.Data.DocumentStatus (DocumentStatus(..))
import Doc.Data.SignatoryLink (AuthenticationToViewMethod(..), AuthenticationToSignMethod(..))
import Doc.DocumentMonad (withDocumentID)
import Doc.Model.Update (SetDocumentSharing(..), TimeoutDocument(..))
import KontraPrelude
import TestingUtil
import TestKontra
import Util.Actor (userActor)

apiV2DocumentPostCallsTests :: TestEnvSt -> Test
apiV2DocumentPostCallsTests env = testGroup "APIv2DocumentPostCalls" $
  [ testThat "API v2 New"                                   env testDocApiV2New
  , testThat "API v2 New from template"                     env testDocApiV2NewFromTemplate
  , testThat "API v2 New from template for company shared"  env testDocApiV2NewFromTemplateShared
  , testThat "API v2 Update"                                env testDocApiV2Update
  , testThat "API v2 Start"                                 env testDocApiV2Start
  , testThat "API v2 Prolong"                               env testDocApiV2Prolong
  , testThat "API v2 Cancel"                                env testDocApiV2Cancel
  , testThat "API v2 Trash"                                 env testDocApiV2Trash
  , testThat "API v2 Delete"                                env testDocApiV2Delete
  , testThat "API v2 Remind"                                env testDocApiV2Remind
  , testThat "API v2 Forward"                               env testDocApiV2Forward
  , testThat "API v2 Set file"                              env testDocApiV2SetFile
  , testThat "API v2 Set attachments"                       env testDocApiV2SetAttachments
  , testThat "API v2 Set auto-reminder"                     env testDocApiV2SetAutoReminder
  , testThat "API v2 Clone"                                 env testDocApiV2Clone
  , testThat "API v2 Restart"                               env testDocApiV2Restart
  , testThat "API v2 Callback"                              env testDocApiV2Callback
  , testThat "API v2 Set signatory authentication to-view"  env testDocApiV2SigSetAuthenticationToView
  , testThat "API v2 Set signatory authentication to-sign"  env testDocApiV2SigSetAuthenticationToSign
  ]

testDocApiV2New :: TestEnv ()
testDocApiV2New = do
  user <- addNewRandomUser
  ctx <- (\c -> c { ctxmaybeuser = Just user }) <$> mkContext def
  status <- getMockDocStatus <$> testDocApiV2New' ctx
  assertEqual "Document should be in preparation" Preparation status

testDocApiV2NewFromTemplate :: TestEnv ()
testDocApiV2NewFromTemplate = do
  user <- addNewRandomUser
  ctx <- (\c -> c { ctxmaybeuser = Just user }) <$> mkContext def
  did <- getMockDocId <$> testDocApiV2New' ctx

  do -- Just to ensure limited scope so we don't test against the wrong thing
    is_template <- getMockDocIsTemplate <$> mockDocTestRequestHelper ctx
      POST [("document", inText "{\"is_template\":true}")]
      (docApiV2Update did) 200
    assertEqual "Document should be template" True is_template

  do -- Just to ensure limited scope so we don't test against the wrong thing
    is_not_template <- getMockDocIsTemplate <$> mockDocTestRequestHelper ctx POST [] (docApiV2NewFromTemplate did) 201
    assertEqual "New document should NOT be template" False is_not_template

testDocApiV2NewFromTemplateShared :: TestEnv ()
testDocApiV2NewFromTemplateShared = do
  (Company {companyid}) <- addNewCompany
  author <- addNewRandomCompanyUser companyid False
  ctxauthor <- (\c -> c { ctxmaybeuser = Just author }) <$> mkContext def
  did <- getMockDocId <$> testDocApiV2New' ctxauthor

  do -- Just to ensure limited scope so we don't test against the wrong thing
    is_template <- getMockDocIsTemplate <$> mockDocTestRequestHelper ctxauthor
      POST [("document", inText "{\"is_template\":true}")]
      (docApiV2Update did) 200
    assertEqual "Document should be template" True is_template

  _ <- randomUpdate $ SetDocumentSharing [did] True
  user <- addNewRandomCompanyUser companyid False
  ctx <- (\c -> c { ctxmaybeuser = Just user }) <$> mkContext def

  do -- Just to ensure limited scope so we don't test against the wrong thing
    is_not_template <- getMockDocIsTemplate <$> mockDocTestRequestHelper ctx POST [] (docApiV2NewFromTemplate did) 201
    assertEqual "New document should NOT be template" False is_not_template

testDocApiV2Update :: TestEnv ()
testDocApiV2Update = do
  user <- addNewRandomUser
  ctx <- (\c -> c { ctxmaybeuser = Just user }) <$> mkContext def
  did <- getMockDocId <$> testDocApiV2New' ctx

  let new_title = "testTitle blah 42$#$%^"
  updated_title <- getMockDocTitle <$> mockDocTestRequestHelper ctx
    POST [("document", inText $ "{\"title\":\"" ++ new_title ++ "\"}")] (docApiV2Update did) 200
  assertEqual "Title should be updated" new_title updated_title

testDocApiV2Start :: TestEnv ()
testDocApiV2Start = do
  user <- addNewRandomUser
  ctx <- (\c -> c { ctxmaybeuser = Just user }) <$> mkContext def
  _ <- testDocApiV2Start' ctx
  return ()

testDocApiV2Prolong :: TestEnv ()
testDocApiV2Prolong = do
  user <- addNewRandomUser
  ctx <- (\c -> c { ctxmaybeuser = Just user }) <$> mkContext def
  mockDoc <- testDocApiV2Start' ctx
  assertEqual "Default number of days should match" 90 $ getMockDocDaysToSign mockDoc
  let did = getMockDocId mockDoc
  withDocumentID did $ do
    dbUpdate $ TimeoutDocument (userActor ctx user)
  -- Current limit is 365 days
  _ <- jsonTestRequestHelper ctx POST [("days", inText "366")] (docApiV2Prolong did) 400
  prolonged_status <- getMockDocStatus <$> mockDocTestRequestHelper ctx POST [("days", inText "365")] (docApiV2Prolong did) 200
  assertEqual "Document status should match" Pending prolonged_status

testDocApiV2Cancel :: TestEnv ()
testDocApiV2Cancel = do
  user <- addNewRandomUser
  ctx <- (\c -> c { ctxmaybeuser = Just user }) <$> mkContext def
  did <- getMockDocId <$> testDocApiV2Start' ctx

  cancel_status <- getMockDocStatus <$> mockDocTestRequestHelper ctx POST [] (docApiV2Cancel did) 200
  assertEqual "Document status should match" Canceled cancel_status

testDocApiV2Trash :: TestEnv ()
testDocApiV2Trash = do
  user <- addNewRandomUser
  ctx <- (\c -> c { ctxmaybeuser = Just user }) <$> mkContext def
  did <- getMockDocId <$> testDocApiV2New' ctx

  is_trashed <- getMockDocIsTrashed <$> mockDocTestRequestHelper ctx POST [] (docApiV2Trash did) 200
  assertEqual "Document should be trashed after call" True is_trashed

testDocApiV2Delete :: TestEnv ()
testDocApiV2Delete = do
  user <- addNewRandomUser
  ctx <- (\c -> c { ctxmaybeuser = Just user }) <$> mkContext def
  did <- getMockDocId <$> testDocApiV2New' ctx

  _ <- mockDocTestRequestHelper ctx POST [] (docApiV2Trash did) 200

  mockDoc <- mockDocTestRequestHelper ctx POST [] (docApiV2Delete did) 200
  assertEqual "Document should be trashed after call" True (getMockDocIsTrashed mockDoc)
  assertEqual "Document should be deleted after call" True (getMockDocIsDeleted mockDoc)

testDocApiV2Remind :: TestEnv ()
testDocApiV2Remind = do
  user <- addNewRandomUser
  ctx <- (\c -> c { ctxmaybeuser = Just user }) <$> mkContext def
  did <- getMockDocId <$> testDocApiV2Start' ctx
  _ <- testRequestHelper ctx POST [] (docApiV2Remind did) 202
  return ()

testDocApiV2Forward :: TestEnv ()
testDocApiV2Forward = do
  user <- addNewRandomUser
  ctx <- (\c -> c { ctxmaybeuser = Just user }) <$> mkContext def
  mockDoc <- testDocApiV2Start' ctx
  let did = getMockDocId mockDoc
  let slid = getMockDocSigLinkId 1 mockDoc

  _ <- mockDocTestRequestHelper ctx
    POST [("fields", inText "[]"),("accepted_author_attachments", inText "[]")]
    (docApiV2SigSign did slid) 200

  _ <- testRequestHelper ctx POST [("email", inText "2.a2@22.e.aa")]
    (docApiV2Forward did) 202
  return ()

testDocApiV2SetFile :: TestEnv ()
testDocApiV2SetFile = do
  user <- addNewRandomUser
  ctx <- (\c -> c { ctxmaybeuser = Just user }) <$> mkContext def
  did <- getMockDocId <$> testDocApiV2New' ctx

  do -- Just to ensure limited scope so we don't test against the wrong thing
    hasFile <- getMockDocHasFile <$> mockDocTestRequestHelper ctx POST [] (docApiV2SetFile did) 200
    assertBool "There should be no file set" (not hasFile)

  do -- Just to ensure limited scope so we don't test against the wrong thing
    hasFile <- getMockDocHasFile <$> mockDocTestRequestHelper ctx
      POST [("file", inFile "test/pdfs/simple-rotate-180.pdf")]
      (docApiV2SetFile did) 200
    assertBool "There should now be a file set" hasFile

testDocApiV2SetAttachments :: TestEnv ()
testDocApiV2SetAttachments = do
  user <- addNewRandomUser
  ctx <- (\c -> c { ctxmaybeuser = Just user }) <$> mkContext def
  did <- getMockDocId <$> testDocApiV2New' ctx

  do -- Just to ensure limited scope so we don't test against the wrong thing
    mda <- mockDocTestRequestHelper ctx
      POST [
        ("attachments", inText $ "[" <>
            "{\"name\" : \"A1\", \"required\" : false, \"file_param\" : \"attachment_0\"}," <>
            "{\"name\" : \"A2\", \"required\" : true, \"file_param\" : \"other_attachment\"}" <>
        "]")
      ,("attachment_0", inFile "test/pdfs/simple-rotate-90.pdf")
      ,("other_attachment", inFile "test/pdfs/simple-rotate-180.pdf")
      ]
      (docApiV2SetAttachments did) 200
    assertEqual "Number of 'author_attachments' should match those set" 2 (getMockDocAuthorAttachmentLength mda)

    assertEqual "Attachment 'A1' should be named as such" "A1" (getMockDocAuthorAttachmentName 1 mda)
    assertEqual "Attachment 'A1' should not be required" False (getMockDocAuthorAttachmentRequired 1 mda)
    assertBool "Attachment 'A1' should have a file set" (getMockDocAuthorAttachmentHasFile 1 mda)

    assertEqual "Attachment 'A2' should be named as such" "A2" (getMockDocAuthorAttachmentName 2 mda)
    assertEqual "Attachment 'A2' should be required" True (getMockDocAuthorAttachmentRequired 2 mda)
    assertBool "Attachment 'A2' should have a file set" (getMockDocAuthorAttachmentHasFile 2 mda)

  do -- Just to ensure limited scope so we don't test against the wrong thing
    mdnoa <- mockDocTestRequestHelper ctx
      POST [("attachments", inText "[]")] (docApiV2SetAttachments did) 200
    assertEqual "Number of 'author_attachments' should match those set" 0 (getMockDocAuthorAttachmentLength mdnoa)

testDocApiV2SetAutoReminder :: TestEnv ()
testDocApiV2SetAutoReminder = do
  user <- addNewRandomUser
  ctx <- (\c -> c { ctxmaybeuser = Just user }) <$> mkContext def
  did <- getMockDocId <$> testDocApiV2Start' ctx

  _auto_remind_time <- getMockDocHasAutoRemindTime <$> mockDocTestRequestHelper ctx
    POST [("days", inText "89")] (docApiV2SetAutoReminder did) 200
  -- FIXME setting this doesn't update the auto remind time immediately, bug in core?
  -- assertJust auto_remind_time
  return ()

testDocApiV2Clone :: TestEnv ()
testDocApiV2Clone = do
  user <- addNewRandomUser
  ctx <- (\c -> c { ctxmaybeuser = Just user }) <$> mkContext def
  mockDoc <- testDocApiV2New' ctx
  let did = getMockDocId mockDoc

  mockDocClone <- mockDocTestRequestHelper ctx POST [] (docApiV2Clone did) 201
  assertEqual "Cloned document should have same structure as original" (cleanMockDocForComparison mockDoc) (cleanMockDocForComparison mockDocClone)

testDocApiV2Restart :: TestEnv ()
testDocApiV2Restart = do
  user <- addNewRandomUser
  ctx <- (\c -> c { ctxmaybeuser = Just user }) <$> mkContext def
  mockDoc <- testDocApiV2Start' ctx
  let did = getMockDocId mockDoc

  _ <- mockDocTestRequestHelper ctx POST [] (docApiV2Cancel did) 200

  mockDocRestart <- mockDocTestRequestHelper ctx POST [] (docApiV2Restart did) 201
  assertEqual "Restarted document should have same structure as original" (cleanMockDocForComparison mockDoc) (cleanMockDocForComparison mockDocRestart)

testDocApiV2Callback :: TestEnv ()
testDocApiV2Callback = do
  user <- addNewRandomUser
  ctx <- (\c -> c { ctxmaybeuser = Just user }) <$> mkContext def
  mockDoc <- testDocApiV2New' ctx
  let did = getMockDocId mockDoc

  -- Should fail for documents in preparation
  _ <- testRequestHelper ctx POST [] (docApiV2Callback did) 409

  mockDocStart <- mockDocTestRequestHelper ctx POST [] (docApiV2Start did) 200

  -- TODO
  -- Right now as API v2 is not "active", V2 callbacks will not run
  -- When it becomes active this test should expand to test that a callback URL
  -- is actually called, by setting up some mock server or something...
  _ <- testRequestHelper ctx POST [] (docApiV2Callback did) 202

  mockDocAfterCallback <- mockDocTestRequestHelper ctx GET [] (docApiV2Get did) 200
  assertEqual "Document after callback should have same structure as original" (cleanMockDocForComparison mockDocStart) (cleanMockDocForComparison mockDocAfterCallback)
  assertEqual "Document after callback should be exactly the same" mockDocStart mockDocAfterCallback

  _cancel <- mockDocTestRequestHelper ctx POST [] (docApiV2Cancel did) 200
  -- Should work after document is cancelled too
  _ <- testRequestHelper ctx POST [] (docApiV2Callback did) 202
  return ()

testDocApiV2SigSetAuthenticationToView :: TestEnv ()
testDocApiV2SigSetAuthenticationToView = do
  user <- addNewRandomUser
  ctx <- (\c -> c { ctxmaybeuser = Just user }) <$> mkContext def
  mockDoc <- testDocApiV2Start' ctx
  let did = getMockDocId mockDoc
  let slid = getMockDocSigLinkId 1 mockDoc

  let param_auth x = ("authentication_type", inText x)
      standard_auth = "standard"
      se_bankid = "se_bankid"
      no_bankid = "no_bankid"
      param_ssn x = ("personal_number", inText x)
      se_ssn_10 = "1234567890"
      se_ssn_12 = "123456789012"
      no_ssn = "12345678901"
      param_mobile x = ("mobile_number", inText x)
      no_mobile = "+4712345678"

  -- Some invalid requests
  _ <- jsonTestRequestHelper ctx POST [param_ssn se_ssn_10]
    (docApiV2SigSetAuthenticationToView did slid) 400
  _ <- jsonTestRequestHelper ctx POST [param_auth "god_is_witness"]
    (docApiV2SigSetAuthenticationToView did slid) 400
  -- FIXME as this is random the SL could have a correct SSN already!
  _ <- jsonTestRequestHelper ctx POST [param_auth no_bankid]
    (docApiV2SigSetAuthenticationToView did slid) 409
  _ <- jsonTestRequestHelper ctx POST [param_auth no_bankid, param_ssn se_ssn_10]
    (docApiV2SigSetAuthenticationToView did slid) 409
  _ <- jsonTestRequestHelper ctx POST [param_auth se_bankid]
    (docApiV2SigSetAuthenticationToView did slid) 409
  _ <- jsonTestRequestHelper ctx POST [param_auth se_bankid, param_ssn no_ssn]
    (docApiV2SigSetAuthenticationToView did slid) 409

  let getAuthToView = getMockDocSigLinkAuthToViewMethod 1
      getPersonalNumber = getMockDocSigLinkPersonalNumber 1
      getMobileNumber = getMockDocSigLinkMobileNumber 1

  -- Valid SE BankID
  do -- Just to ensure limited scope so we don't test against the wrong thing
    mockDocSE10 <- mockDocTestRequestHelper ctx POST [param_auth se_bankid, param_ssn se_ssn_10]
      (docApiV2SigSetAuthenticationToView did slid) 200
    assertEqual "Authentication to view should be set" SEBankIDAuthenticationToView (getAuthToView mockDocSE10)
    assertEqual "SE-10 Personal number should be set" se_ssn_10 (getPersonalNumber mockDocSE10)

  do -- Just to ensure limited scope so we don't test against the wrong thing
    mockDocStandard1 <- mockDocTestRequestHelper ctx POST [param_auth standard_auth]
      (docApiV2SigSetAuthenticationToView did slid) 200
    assertEqual "Authentication to view should be set" StandardAuthenticationToView (getAuthToView mockDocStandard1)
    assertEqual "SE-10 Personal number should STILL be set" se_ssn_10 (getPersonalNumber mockDocStandard1)

  do -- Just to ensure limited scope so we don't test against the wrong thing
    mockDocSE12 <- mockDocTestRequestHelper ctx POST [param_auth se_bankid, param_ssn se_ssn_12]
      (docApiV2SigSetAuthenticationToView did slid) 200
    assertEqual "Authentication to view should be set" SEBankIDAuthenticationToView (getAuthToView mockDocSE12)
    assertEqual "SE-12 Personal number should be set" se_ssn_12 (getPersonalNumber mockDocSE12)

  -- Invalid NO SSN
  _ <- jsonTestRequestHelper ctx POST [param_auth no_bankid]
    (docApiV2SigSetAuthenticationToView did slid) 409

  -- Valid NO BankID
  do -- Just to ensure limited scope so we don't test against the wrong thing
    mockDocNO <- mockDocTestRequestHelper ctx POST [param_auth no_bankid, param_ssn no_ssn]
      (docApiV2SigSetAuthenticationToView did slid) 200
    assertEqual "Authentication to view should be set" NOBankIDAuthenticationToView (getAuthToView mockDocNO)
    assertEqual "NO Personal number should be set" no_ssn (getPersonalNumber mockDocNO)

  -- Invalid NO Mobile
  _ <- jsonTestRequestHelper ctx POST [param_auth no_bankid, param_mobile "-1"]
    (docApiV2SigSetAuthenticationToView did slid) 409
  _ <- jsonTestRequestHelper ctx POST [param_auth no_bankid, param_mobile (init no_mobile)]
    (docApiV2SigSetAuthenticationToView did slid) 409
  _ <- jsonTestRequestHelper ctx POST [param_auth no_bankid, param_mobile (no_mobile ++ "5")]
    (docApiV2SigSetAuthenticationToView did slid) 409

  do -- Just to ensure limited scope so we don't test against the wrong thing
    mockDocNOMobile <- mockDocTestRequestHelper ctx POST [param_auth no_bankid, param_mobile no_mobile]
      (docApiV2SigSetAuthenticationToView did slid) 200
    assertEqual "Authentication to view should be set" NOBankIDAuthenticationToView (getAuthToView mockDocNOMobile)
    assertEqual "NO Mobile number should be set" no_mobile (getMobileNumber mockDocNOMobile)
    assertEqual "NO Personal number should STILL be set" no_ssn (getPersonalNumber mockDocNOMobile)

  do -- Just to ensure limited scope so we don't test against the wrong thing
    mockDocNOEmptyMobile <- mockDocTestRequestHelper ctx POST [param_auth no_bankid, param_mobile ""]
      (docApiV2SigSetAuthenticationToView did slid) 200
    assertEqual "Authentication to view should be set" NOBankIDAuthenticationToView (getAuthToView mockDocNOEmptyMobile)
    assertEqual "NO Mobile number should be empty" "" (getMobileNumber mockDocNOEmptyMobile)
    assertEqual "NO Personal number should STILL be set" no_ssn (getPersonalNumber mockDocNOEmptyMobile)

  do -- Just to ensure limited scope so we don't test against the wrong thing
    mockDocStandard2 <- mockDocTestRequestHelper ctx POST [param_auth standard_auth]
      (docApiV2SigSetAuthenticationToView did slid) 200
    assertEqual "Authentication to view should be set" StandardAuthenticationToView (getAuthToView mockDocStandard2)
    assertEqual "NO Personal number should STILL be set" no_ssn (getPersonalNumber mockDocStandard2)

testDocApiV2SigSetAuthenticationToSign :: TestEnv ()
testDocApiV2SigSetAuthenticationToSign = do
  user <- addNewRandomUser
  ctx <- (\c -> c { ctxmaybeuser = Just user }) <$> mkContext def
  mockDoc <- testDocApiV2Start' ctx
  let did = getMockDocId mockDoc
  let slid = getMockDocSigLinkId 1 mockDoc

  let param_auth x = ("authentication_type", inText x)
      standard_auth = "standard"
      se_bankid = "se_bankid"
      sms_pin = "sms_pin"
      param_ssn x = ("personal_number", inText x)
      se_ssn_10 = "1234567890"
      se_ssn_12 = "123456789012"
      se_ssn_invalid = "1234"
      param_mobile x = ("mobile_number", inText x)
      valid_mobile = "+4612345678"
      _invalid_mobile = "45678"

  -- Some invalid requests
  _ <- jsonTestRequestHelper ctx POST [param_auth "god_is_witness"]
    (docApiV2SigSetAuthenticationToSign did slid) 400
  _ <- jsonTestRequestHelper ctx POST [param_auth se_bankid, param_ssn se_ssn_invalid]
    (docApiV2SigSetAuthenticationToSign did slid) 409
  -- FIXME this works, but is it supposed to?
  --_ <- jsonTestRequestHelper ctx POST [param_auth sms_pin, param_mobile invalid_mobile]
  --  (docApiV2SigSetAuthenticationToSign did slid) 409

  let getAuthToSign = getMockDocSigLinkAuthToSignMethod 1
      getPersonalNumber = getMockDocSigLinkPersonalNumber 1
      getMobileNumber = getMockDocSigLinkMobileNumber 1

  -- Valid SE BankID
  do -- Just to ensure limited scope so we don't test against the wrong thing
    mockDocSEEmpty <- mockDocTestRequestHelper ctx POST [param_auth se_bankid]
      (docApiV2SigSetAuthenticationToSign did slid) 200
    assertEqual "Authentication to sign should be set" SEBankIDAuthenticationToSign (getAuthToSign mockDocSEEmpty)
    assertEqual "Personal number should not be set" "" (getPersonalNumber mockDocSEEmpty)

  do -- Just to ensure limited scope so we don't test against the wrong thing
    mockDocSE10 <- mockDocTestRequestHelper ctx POST [param_auth se_bankid, param_ssn se_ssn_10]
      (docApiV2SigSetAuthenticationToSign did slid) 200
    assertEqual "Authentication to sign should be set" SEBankIDAuthenticationToSign (getAuthToSign mockDocSE10)
    assertEqual "Personal number should be set (10 digit SE)" se_ssn_10 (getPersonalNumber mockDocSE10)

  do -- Just to ensure limited scope so we don't test against the wrong thing
    mockDocSE12 <- mockDocTestRequestHelper ctx POST [param_auth se_bankid, param_ssn se_ssn_12]
      (docApiV2SigSetAuthenticationToSign did slid) 200
    assertEqual "Authentication to sign should be set" SEBankIDAuthenticationToSign (getAuthToSign mockDocSE12)
    assertEqual "Personal number should be set (12 digit SE)" se_ssn_12 (getPersonalNumber mockDocSE12)

  do -- Just to ensure limited scope so we don't test against the wrong thing
    mockDocStandard1 <- mockDocTestRequestHelper ctx POST [param_auth standard_auth]
      (docApiV2SigSetAuthenticationToSign did slid) 200
    assertEqual "Authentication to sign should be set" StandardAuthenticationToSign  (getAuthToSign mockDocStandard1)
    assertEqual "Personal number should STILL be set (12 digit SE)" se_ssn_12 (getPersonalNumber mockDocStandard1)

  -- Valid SMS PIN
  do -- Just to ensure limited scope so we don't test against the wrong thing
    mockDocSMSEmpty <- mockDocTestRequestHelper ctx POST [param_auth sms_pin]
      (docApiV2SigSetAuthenticationToSign did slid) 200
    assertEqual "Authentication to sign should be set" SMSPinAuthenticationToSign (getAuthToSign mockDocSMSEmpty)
    assertEqual "Mobile number should not be set" "" (getMobileNumber mockDocSMSEmpty)
    assertEqual "Personal number should STILL be set (12 digit SE)" se_ssn_12 (getPersonalNumber mockDocSMSEmpty)

  do -- Just to ensure limited scope so we don't test against the wrong thing
    mockDocSMS <- mockDocTestRequestHelper ctx POST [param_auth sms_pin, param_mobile valid_mobile]
      (docApiV2SigSetAuthenticationToSign did slid) 200
    assertEqual "Authentication to sign should be set" SMSPinAuthenticationToSign (getAuthToSign mockDocSMS)
    assertEqual "Mobile number should be set" valid_mobile (getMobileNumber mockDocSMS)
    assertEqual "Personal number should STILL be set (12 digit SE)" se_ssn_12 (getPersonalNumber mockDocSMS)

  do -- Just to ensure limited scope so we don't test against the wrong thing
    mockDocStandard2 <- mockDocTestRequestHelper ctx POST [param_auth standard_auth]
      (docApiV2SigSetAuthenticationToSign did slid) 200
    assertEqual "Authentication to sign should be set" StandardAuthenticationToSign (getAuthToSign mockDocStandard2)
    assertEqual "Mobile number should STILL be set" valid_mobile (getMobileNumber mockDocStandard2)
    assertEqual "Personal number should STILL be set (12 digit SE)" se_ssn_12 (getPersonalNumber mockDocStandard2)
