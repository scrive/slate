{-# LANGUAGE CPP #-}
{-# OPTIONS_GHC -Wall #-}
-----------------------------------------------------------------------------
-- |
-- Module      :  Doc.DocSeal
-- Maintainer  :  all
-- Stability   :  development
-- Portability :  not portable
--
-- All that is needed to seal a document
-----------------------------------------------------------------------------
module Doc.DocSeal(sealDocument) where

import Control.Concurrent
import Control.Monad.Reader
import Data.Maybe
import Data.Bits
import Data.List
import Data.Word
import Data.Ord
import Debug.Trace
import Doc.DocProcess
import Doc.DocState
import Doc.DocStorage
import Doc.DocView
import Doc.DocUtils
import Happstack.State (update, query)
import Misc
import System.Directory
import System.Exit
import Kontra
import Templates.Templates
import qualified Amazon as AWS
import qualified Data.ByteString as BS
import qualified Data.ByteString.Lazy.UTF8 as BSL hiding (length)
import qualified Data.ByteString.UTF8 as BS hiding (length)
import qualified SealSpec as Seal
import qualified TrustWeaver as TW
import qualified AppLogger as Log
import System.IO.Temp
import System.IO                       
                         
personFromSignatoryDetails :: SignatoryDetails -> Seal.Person
personFromSignatoryDetails details =
    Seal.Person { Seal.fullname = (BS.toString $ signatoryname details) ++ 
                                  if not (BS.null $ signatorypersonalnumber details)
                                     then " (" ++ (BS.toString $ signatorypersonalnumber details) ++ ")"
                                     else ""
                , Seal.company = BS.toString $ signatorycompany details
                , Seal.email = BS.toString $ signatoryemail details
                -- | FIXME: this should be split to company/personal number
                , Seal.personalnumber = BS.toString $ signatorypersonalnumber details
                , Seal.companynumber = BS.toString $ signatorycompanynumber details
                , Seal.fullnameverified = False
                , Seal.companyverified = False
                , Seal.numberverified = False
                , Seal.emailverified = True
                }

personFields::(Seal.Person, SignInfo, SignInfo, Bool, Maybe SignatureProvider,String) -> Fields
personFields  (person, signinfo,seeninfo, _ , mprovider, _initials) = do 
   field "personname" $ Seal.fullname person
   field "signip" $  formatIP (signipnumber signinfo)
   field "seenip" $  formatIP (signipnumber signinfo)
   field "provider" $ isJust mprovider
   field "bankid" $ mprovider == Just BankIDProvider
   field "nordea" $ mprovider == Just NordeaProvider
   field "telia"  $ mprovider == Just TeliaProvider


personsFromDocument :: Document -> [(Seal.Person, SignInfo, SignInfo, Bool, Maybe SignatureProvider, String)]
personsFromDocument document = 
    let
        links = filter isSignatory $ documentsignatorylinks document
        x (sl@SignatoryLink { signatorydetails
                            , maybesigninfo = Just signinfo
                            , maybeseeninfo
                            , maybesignatory
                            , signatorysignatureinfo
                            })
             -- FIXME: this one should really have seentime always...
             = ((personFromSignatoryDetails signatorydetails)
                { Seal.emailverified = True
                , Seal.fullnameverified = fullnameverified
                , Seal.companyverified = False
                , Seal.numberverified = numberverified}
              , maybe signinfo id maybeseeninfo
              , signinfo
              , siglinkIsAuthor sl
              , maybe Nothing (Just . signatureinfoprovider) signatorysignatureinfo
              , map head $ words $ BS.toString $ signatoryname signatorydetails
              )
                  where fullnameverified = maybe False (\x -> signaturefstnameverified x
                                                        && signaturelstnameverified x)
                                                signatorysignatureinfo
                        numberverified = maybe False signaturepersnumverified signatorysignatureinfo

        x link = trace (show link) $ error "SignatoryLink does not have all the necessary data"
    in map x links

fieldsFromPlacement :: String -> FieldPlacement -> Seal.Field
fieldsFromPlacement value placement  =
    Seal.Field { Seal.value = value
               , Seal.x =  placementx placement
               , Seal.y =  placementy placement
               , Seal.page = placementpage placement
               , Seal.w = placementpagewidth placement
               , Seal.h = placementpageheight placement
               }
               
fieldsFromDefinition :: FieldDefinition -> [Seal.Field]
fieldsFromDefinition def =
    map (fieldsFromPlacement (BS.toString (fieldvalue def))) (fieldplacements def)

fieldsFromSignatory::SignatoryDetails -> [Seal.Field]
fieldsFromSignatory sig = 
    (map (fieldsFromPlacement (BS.toString (signatoryfstname sig))) (signatoryfstnameplacements sig))
    ++
    (map (fieldsFromPlacement (BS.toString (signatorysndname sig))) (signatorysndnameplacements sig))
    ++
    (map (fieldsFromPlacement (BS.toString (signatoryemail sig))) (signatoryemailplacements sig))
    ++
    (map (fieldsFromPlacement (BS.toString (signatorycompany sig))) (signatorycompanyplacements sig))
    ++
    (map (fieldsFromPlacement (BS.toString (signatorypersonalnumber sig))) (signatorypersonalnumberplacements sig))
    ++
    (map (fieldsFromPlacement (BS.toString (signatorycompanynumber sig))) (signatorycompanynumberplacements sig))
    ++
    (foldl (++) [] (map fieldsFromDefinition (signatoryotherfields sig)))    

-- oh boy, this is really network byte order!
formatIP :: Word32 -> String
formatIP 0 = ""
-- formatIP 0x7f000001 = ""
formatIP x = " (IP: " ++ show ((x `shiftR` 0) .&. 255) ++
                   "." ++ show ((x `shiftR` 8) .&. 255) ++
                   "." ++ show ((x `shiftR` 16) .&. 255) ++
                   "." ++ show ((x `shiftR` 24) .&. 255) ++ ")"
                   
formatProvider :: SignatureProvider -> String
formatProvider BankIDProvider = "BankID"
formatProvider NordeaProvider = "Nordea e-legitimation"
formatProvider TeliaProvider  = "Telia e-legitimation"
formatProvider _ = "e-legitimation"

sealSpecFromDocument :: KontrakcjaTemplates -> String -> Document -> String -> String -> IO Seal.SealSpec
sealSpecFromDocument templates hostpart document inputpath outputpath =
  let docid = unDocumentID (documentid document)
      Just authorsiglink = getAuthorSigLink document
      authorHasSigned = isSignatory authorsiglink && isJust (maybesigninfo authorsiglink)
      signatoriesdetails = [signatorydetails sl | sl <- documentsignatorylinks document
                                                , SignatoryPartner `elem` signatoryroles sl]
      authordetails = signatorydetails authorsiglink
      signatories = personsFromDocument document
      secretaries = if authorHasSigned then [] else [personFromSignatoryDetails authordetails]

      persons = map (\(a,_,_,_,_,_) -> a) signatories
      initialsx = map (\(_,_,_,_,_,a) -> a) signatories
      paddeddocid = pad0 20 (show docid)

      initials = concatComma initialsx
      initialsOfPerson (Seal.Person {Seal.fullname}) = map head (words fullname)
      makeHistoryEntryFromSignatory personInfo@(_ ,seen, signed, isAuthor, _, _)  = do
          seenDesc <- renderTemplateForProcess templates document processseenhistentry $ do
                        personFields personInfo
                        documentInfoFields document
          let seenEvent = Seal.HistEntry 
                            { Seal.histdate = show (signtime seen)
                            , Seal.histcomment = pureString seenDesc} 
          signDesc <- renderTemplateForProcess templates document processsignhistentry $ do
                        personFields personInfo
                        documentInfoFields document
          let signEvent = Seal.HistEntry
                            { Seal.histdate = show (signtime signed)
                            , Seal.histcomment = pureString signDesc}      
          return $ if (isAuthor) 
                    then [signEvent]
                    else [seenEvent,signEvent]
      invitationSentEntry = case documentinvitetime document of
                                Nothing -> return []
                                Just (SignInfo time ipnumber) -> do
                                   desc <-  renderTemplateForProcess templates document processinvitationsententry $ do
                                       documentInfoFields document
                                       documentAuthorInfo document
                                       field "oneSignatory"  (length signatories>1)
                                       field "personname" $  listToMaybe $ map  (BS.toString . signatoryname)  signatoriesdetails
                                       field "ip" $ formatIP ipnumber
                                   return  [ Seal.HistEntry
                                      { Seal.histdate = show time
                                      , Seal.histcomment = pureString desc 
                                      }]

      maxsigntime = maximum (map (signtime . (\(_,_,c,_,_,_) -> c)) signatories)
      concatComma = concat . intersperse ", "
      
      lastHistEntry = do
                       desc <- renderTemplateForProcess templates document processlasthisentry (documentInfoFields document)
                       return $ if (Just True == getValueForProcess document processsealincludesmaxtime)
                                then [Seal.HistEntry
                                { Seal.histdate = show maxsigntime
                                , Seal.histcomment = pureString desc}]
                                else []

      -- document fields
      fields = if authorHasSigned
               then concatMap fieldsFromSignatory signatoriesdetails
               else concatMap fieldsFromSignatory $ authordetails : signatoriesdetails
                    
    
  in do    
      events <- fmap concat $ sequence $ 
                    (map makeHistoryEntryFromSignatory signatories) ++
                    [invitationSentEntry] ++
                    [lastHistEntry]
      -- here we use Data.List.sort that is *stable*, so it puts
      -- signatories actions before what happened with a document
      let history = sortBy (comparing Seal.histdate) events
      staticTexts <- renderTemplateForProcess templates document processsealingtext $ do
                        documentInfoFields document
                        field "hostpart" hostpart
      return $ Seal.SealSpec 
            { Seal.input          = inputpath
            , Seal.output         = outputpath
            , Seal.documentNumber = paddeddocid
            , Seal.persons        = persons
            , Seal.secretaries    = secretaries
            , Seal.history        = history
            , Seal.initials       = initials
            , Seal.hostpart       = hostpart
            , Seal.fields         = fields
            , Seal.staticTexts    = read staticTexts -- this should never fail since we control templates
            }

sealDocument :: Context 
             -> Document
             -> IO (Either String Document)
sealDocument ctx@Context{ctxdocstore, ctxs3action, ctxtwconf, ctxhostpart}
             document = do
  let files = documentfiles document
  Log.debug $ "Sealing document"
  mapM_ (sealDocumentFile ctx document) files
  Log.debug $ "Sealing should be done now"
  Just newdocument <- query $ GetDocumentByDocumentID (documentid document)
  Log.debug $ "Reselecting document after update - time for upload to amazon"
  _ <- liftIO $ forkIO $ mapM_ (AWS.uploadFile ctxdocstore ctxs3action) (documentsealedfiles newdocument)
  Log.debug $ "Upload to amazon is done"
  Log.debug $ show newdocument
  return $ Right newdocument

                 

{- Someday:

 We have lost the ability to upload document to TrustWeaver. Resurrect
 it someday, when somebody asks.

   case signeddocstorage (usersettings author) of
       Nothing -> return ()
       Just twsettings -> 
           do
               _ <- forkIO $ uploadDocumentFilesToTrustWeaver ctxtwconf (BS.toString $ storagetwname twsettings) documentid
               return ()
 -}


sealDocumentFile :: Context 
                 -> Document
                 -> File
                 -> IO (Either String Document)
sealDocumentFile ctx@Context{ctxdocstore, ctxs3action, ctxtwconf, ctxhostpart, ctxtemplates}
                 document@Document{documentid,documenttitle}
                 file@File {fileid,filename} =
  withSystemTempDirectory ("seal-" ++ show documentid ++ "-" ++ show fileid ++ "-") $ \tmppath -> do
  let tmpin = tmppath ++ "/input.pdf"
  let tmpout = tmppath ++ "/output.pdf"
  content <- getFileContents ctx file
  BS.writeFile tmpin content
  config <- sealSpecFromDocument ctxtemplates ctxhostpart document tmpin tmpout
  Log.debug $ show config
  (code,stdout,stderr) <- readProcessWithExitCode' "dist/build/pdfseal/pdfseal" [] (BSL.fromString (show config))
  Log.debug $ "Sealing completed with " ++ show code
  case code of
      ExitSuccess -> 
          do
              newfilepdf1 <- BS.readFile tmpout
              newfilepdf <- 
                  case TW.signConf ctxtwconf of
                      Nothing -> do
                          Log.debug $ "TrustWeaver configuration empty, not doing TrustWeaver signing"
                          return newfilepdf1
                      Just x -> do
                          Log.debug $ "About to TrustWeaver sign doc #" ++ show documentid ++ " file #" ++ show fileid
                          x <- TW.signDocument ctxtwconf newfilepdf1
                          case x of
                              Left errmsg -> 
                                  do
                                      let msg = "Cannot TrustWeaver sign doc #" ++ show documentid ++ " file #" ++ show fileid ++ ": " ++ errmsg
                                      Log.error $ msg 
                                      Log.trustWeaver $ msg 
                                      return newfilepdf1
                              Right result -> 
                                  do
                                      let msg = "TrustWeaver signed doc #" ++ show documentid ++ " file #" ++ show fileid ++ ": " ++ BS.toString documenttitle
                                      Log.trustWeaver msg
                                      return result
              res <- update $ AttachSealedFile documentid filename newfilepdf
              return res
      ExitFailure _ -> 
          do
              -- error handling
              systmp <- getTemporaryDirectory
              (path,handle) <- openTempFile systmp ("seal-failed-" ++ show documentid ++ "-" ++ show fileid ++ "-.pdf")
              let msg = "Cannot seal document #" ++ show documentid ++ " because of file #" ++ show fileid
              Log.error $ msg ++ ": " ++ path
              Log.error $ BSL.toString stderr
              Log.error $ "Sealing configuration: " ++ show config
              BS.hPutStr handle content
              hClose handle
              _ <- update $ ErrorDocument documentid $ "Could not seal document because of file #" ++ show fileid
              return $ Left msg
