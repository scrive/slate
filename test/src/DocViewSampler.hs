module DocViewSampler(
    docViewSamples
) where

import Test.HUnit (assert, assertEqual, assertFailure, Assertion(..))
import Test.Framework (Test, testGroup)
import Test.Framework.Providers.HUnit (testCase)

import DocView
import SamplerHelper
import SampleData
import User
import DocState
import UserState
import Misc
import AppView
import KontraLink
import HSP
import System.IO.Unsafe
import qualified Data.ByteString.UTF8 as BS

docViewSamples :: [Test]
docViewSamples = [testGroup "sample document flash messages"
                           [testCase "document draft saved" sampleDocumentDraftSavedFlashMsg,
                            testCase "document restarted" sampleDocumentRestartedFlashMsg,
                            testCase "remind unsigned mail sent" sampleRemindUnsignedMailSentFlashMsg,
                            testCase "remind signed mail sent" sampleRemindSignedMailSentFlashMsg,
                            testCase "document canceled" sampleCanceledFlashMsg ],
                  testGroup "sample document views"
                           [testCase "landpage sign invite" sampleLandpageSignInviteView,
                            testCase "landpage rejected view" sampleLandpageRejectedView,
                            testCase "landpage signed (no account)" sampleLandpageSignedNoAccountView,
                            testCase "landpage signed (has account)" sampleLandpageSignedHasAccountView,
                            testCase "landpage login for save" sampleLandpageLoginForSaveView, 
                            testCase "landpage document saved" sampleDocumentSavedView,
                            testCase "document for sign" sampleDocumentViewForSign]]


sampleDocumentDraftSavedFlashMsg =
  sampleFlashMsg "document_details_saved" flashDocumentDraftSaved

sampleDocumentRestartedFlashMsg =
  sampleFlashMsg "document_restarted" flashDocumentRestarted

sampleRemindUnsignedMailSentFlashMsg = 
  sampleFlashMsg "remind_unsigned_mail_sent" (\t -> flashRemindMailSent t anUnsignedSigLink)

sampleRemindSignedMailSentFlashMsg = 
  sampleFlashMsg "remind_signed_mail_sent" (\t -> flashRemindMailSent t aSignedSigLink)

sampleCanceledFlashMsg =
  sampleFlashMsg "document_canceled" flashMessageCanceled

sampleLandpageSignInviteView =
  sampleView "landpage_sign_invite" (\t -> landpageSignInviteView t anUnsignedDocument)

sampleLandpageRejectedView =
  sampleView "landpage_rejected_view" (\t -> landpageRejectedView t anUnsignedDocument)

sampleLandpageSignedNoAccountView =
  sampleView "landpage_signed_no_account" (\t -> landpageSignedView t aSignedDocument aSignedSigLink False)

sampleLandpageSignedHasAccountView =
  sampleView "landpage_signed_has_account" (\t -> landpageSignedView t aSignedDocument aSignedSigLink True)

sampleLandpageLoginForSaveView =
  sampleView "landpage_login_for_save" landpageLoginForSaveView

sampleDocumentSavedView =
  sampleView "document_saved" landpageDocumentSavedView

sampleDocumentViewForSign =
    let ctx = aTestCtx
        document = anUnsignedDocument
        wassigned = False
        author = aTestUser
        invitedlink = head $ documentsignatorylinks document
    in
    sampleView2 "document_for_sign" (\templ -> pageFromBody' "../public" (ctx{ctxtemplates=templ}) TopNone "kontrakcja"
                                               (fmap cdata $ pageDocumentForSign (LinkSignDoc document invitedlink) 
                                                     document (ctx{ctxtemplates=templ}) invitedlink wassigned author))


sampleView2 name action = sample name "view" (\t -> renderHSPToString (action t)) writeFile
