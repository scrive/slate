{-# LANGUAGE IncoherentInstances, TemplateHaskell, NamedFieldPuns, FlexibleContexts, FlexibleInstances, MultiParamTypeClasses #-}
{-# OPTIONS_GHC -F -pgmFtrhsx -Wall #-}

module DocView( emptyDetails
              , showFilesImages2
              , pageDocumentForAuthor
              , pageDocumentForViewer
              , pageDocumentList
              , landpageSignInviteView
              , landpageSendInviteView
              , landpageSignedView
              , landpageLoginForSaveView
              , landpageDocumentSavedView
              , pageDocumentForSign
              , flashRemindMailSent
              , flashMessageCanceled 
              , flashDocumentRestarted
              , flashDocumentDraftSaved
              , landpageRejectedView
              , defaultInviteMessage 
              , mailDocumentRemind
              , mailDocumentRejectedForAuthor
              , mailDocumentAwaitingForAuthor
              , mailCancelDocumentByAuthorContent
              , mailCancelDocumentByAuthor
              , mailInvitationToSign
              , mailInvitationToSend
              , mailDocumentClosedForSignatories
              , mailDocumentClosedForAuthor
              , isNotLinkForUserID
              , signatoryDetailsFromUser
              ) where
import Data.List
import DocState
import HSP
import qualified Data.ByteString.UTF8 as BS
import qualified Data.ByteString as BS
import qualified HSX.XMLGenerator as HSX
import User
import KontraLink
import Misc
import MinutesTime
import Data.Maybe
import DocViewMail
import DocViewUtil
import Templates.Templates
import Templates.TemplatesUtils
import Mails.MailsUtil
import UserView (prettyName,UserSmallView(..))
import Data.Typeable
import Data.Data

landpageSignInviteView ::KontrakcjaTemplates -> Document ->  IO String
landpageSignInviteView templates  document =
     do 
      partylist <-renderListTemplate templates (map (BS.toString . personname') $ partyListButAuthor document)
      renderTemplate templates  "landpageSignInviteView" [("partyListButAuthor", partylist),
                                                          ("documenttitle",BS.toString $ documenttitle document )]

landpageSendInviteView ::KontrakcjaTemplates -> Document ->  IO String
landpageSendInviteView templates  document =
     do 
      partylist <-renderListTemplate templates (map (BS.toString . personname') $ partyListButAuthor document)
      renderTemplate templates  "landpageSendInviteView" [("partyListButAuthor", partylist),
                                                          ("documenttitle",BS.toString $ documenttitle document )]

willCreateAccountForYou::KontrakcjaTemplates -> Document->SignatoryLink->Bool->  IO String
willCreateAccountForYou templates  _ _ False =  renderTemplate templates "willCreateAccountForYouNoAccount" ([]::[(String,String)])
willCreateAccountForYou templates  document siglink True = 
                                     renderTemplate templates  "willCreateAccountForYouHasAccount" 
                                                                     [("documentid",show $ unDocumentID $ documentid document),
                                                                     ("signatorylinkid",show $ unSignatoryLinkID $ signatorylinkid siglink)]

landpageRejectedView ::KontrakcjaTemplates -> Document -> IO String
landpageRejectedView templates document =
   do 
      partylist <-renderListTemplate templates  (map (BS.toString . personname') $ partyList document)
      renderTemplate templates  "landpageRejectedView" [("partyList", partylist),
                                              ("documenttitle",BS.toString $ documenttitle document )]

landpageSignedView ::KontrakcjaTemplates -> Document -> SignatoryLink -> Bool -> IO String
landpageSignedView templates document@Document{documenttitle,documentstatus} signatorylink hasaccount =
    do
       willCreateAccountForYouProposal <- willCreateAccountForYou templates document signatorylink (not hasaccount) 
       if (documentstatus == Closed) 
        then do
              partylist <- renderListTemplate templates $ map (BS.toString . personname') $ partyList document
              renderTemplate templates "landpageSignedViewClosed" [("partyListString", partylist),
                                                         ("documenttitle",BS.toString $ documenttitle),
                                                         ("willCreateAccountForYou", willCreateAccountForYouProposal)]
        else do
              partyunsignedlist <- renderListTemplate templates  $ map (BS.toString . personname') $ partyUnsignedList document
              renderTemplate templates  "landpageSignedViewNotClosed"  [("partyUnsignedListString", partyunsignedlist),
                                                             ("documenttitle",BS.toString $ documenttitle),
                                                             ("willCreateAccountForYou", willCreateAccountForYouProposal)]   

landpageLoginForSaveView::KontrakcjaTemplates ->IO String
landpageLoginForSaveView  templates  = renderTemplate templates  "landpageLoginForSaveView" []

landpageDocumentSavedView ::KontrakcjaTemplates -> IO String
landpageDocumentSavedView templates  = renderTemplate templates  "landpageDocumentSavedView" []

flashDocumentDraftSaved :: KontrakcjaTemplates ->IO String
flashDocumentDraftSaved  templates  = renderTemplate templates  "flashDocumentDraftSaved" []

flashDocumentRestarted :: KontrakcjaTemplates ->IO String
flashDocumentRestarted  templates  = renderTemplate templates "flashDocumentRestarted" []

flashRemindMailSent :: KontrakcjaTemplates -> SignatoryLink -> IO String                                
flashRemindMailSent templates  signlink@SignatoryLink{maybesigninfo = Nothing}  = 
                            renderTemplate templates  "flashRemindMailSentNotSigned" [("personname",BS.toString $ personname signlink)] 
flashRemindMailSent templates  signlink = 
                            renderTemplate templates  "flashRemindMailSentSigned" [("personname",BS.toString $ personname signlink)] 


flashMessageCanceled :: KontrakcjaTemplates -> IO String
flashMessageCanceled templates = renderTemplate templates  "flashMessageCanceled" []


--All doc view
singLinkUserSmallView sl = UserSmallView {     usvId =  show $ signatorylinkid sl
                                             , usvFullname = BS.toString $ personname sl
                                             , usvEmail = ""
                                             , usvDocsCount = "" }

data DocumentSmallView = DocumentSmallView {
                          dsvId::String,
                          dsvTitle::String,
                          dsvSignatories::[UserSmallView],
                          dsvAnyinvitationundelivered::Bool,
                          dsvStatusimage::String,
                          dsvDoclink::String,
                          dsvDavelink::Maybe String,
                          dsvTimeoutdate::Maybe String,
                          dsvTimeoutdaysleft::Maybe String,  
                          dsvMtime::String
                         } deriving (Data, Typeable)
                         
documentSmallView::MinutesTime ->  User -> Document ->DocumentSmallView
documentSmallView crtime user doc = DocumentSmallView {
                          dsvId = show $ documentid doc,
                          dsvTitle = BS.toString $ documenttitle doc,
                          dsvSignatories = map singLinkUserSmallView $ documentsignatorylinks doc,
                          dsvAnyinvitationundelivered = anyInvitationUndelivered doc,
                          dsvStatusimage = "/theme/images/" ++
                                               case (documentstatus doc) of
                                                  Preparation -> "status_draft.png"
                                                  Pending  -> if  any (isJust . maybeseeninfo) $ documentsignatorylinks doc
                                                               then "status_viewed.png"
                                                               else "status_pending.png"
                                                  AwaitingAuthor -> "status_pending.png"
                                                  Closed -> "status_signed.png"
                                                  Canceled -> "status_rejected.png"
                                                  Timedout -> "status_timeout.png"
                                                  Rejected -> "status_rejected.png"
                                                  Withdrawn -> "status_rejected.png",
                          dsvDoclink =     if (unAuthor $ documentauthor doc) ==(userid user) || (null $ signatorylinklist)
                                            then show $ LinkIssueDoc $ documentid doc
                                            else show $ LinkSignDoc doc (head $ signatorylinklist),
                          dsvDavelink = if isSuperUser (Just user) 
                                         then Just $ "/dave/document/" ++ (show documentid) 
                                         else Nothing  ,               
                          dsvTimeoutdate =  fromTimeout show,
                          dsvTimeoutdaysleft =  fromTimeout $ show . (dateDiffInDays crtime),    
                          dsvMtime = showDateAbbrev crtime (documentmtime doc)
                         }
  where   signatorylinklist = filter (isMatchingSignatoryLink user) $ documentsignatorylinks doc  
          fromTimeout f =  case (documenttimeouttime doc,documentstatus doc) of
                                (Just (TimeoutTime x),Pending) -> Just $ f x
                                _ -> Nothing
                                                                            

pageDocumentList:: KontrakcjaTemplates -> MinutesTime -> User -> [Document] -> IO String
pageDocumentList templates ctime user documents = renderTemplateComplex templates "pageDocumentList" $
                                                        (setAttribute "documents" $ map (documentSmallView ctime user) $ filter (not . documentdeleted) documents)



----Single document view
showSignatoryEntryForEdit :: ( XMLGenerator m, EmbedAsAttr m (Attr [Char] KontraLink),
                               EmbedAsAttr m (Attr [Char] DocumentID)) 
                          => DocState.SignatoryDetails -> XMLGenT m (HSX.XML m)
showSignatoryEntryForEdit (SignatoryDetails{signatoryname,signatorycompany,signatorynumber, signatoryemail}) = 
    showSignatoryEntryForEdit2 "" (BS.toString signatoryname) 
                                   (BS.toString signatorycompany) 
                                   (BS.toString signatorynumber) 
                                   (BS.toString signatoryemail)

showSignatoryEntryForEdit2 :: (XMLGenerator m,EmbedAsAttr m (Attr [Char] KontraLink),
                               EmbedAsAttr m (Attr [Char] DocumentID)) 
                           => String -> String -> String -> String
                           -> String -> XMLGenT m (HSX.XML m)
showSignatoryEntryForEdit2 idx signatoryname signatorycompany signatorynumber signatoryemail = 
    <div id=idx class="signatorybox" alt="Namn på avtalspart">
      <input name="signatoryname" type="text" value=signatoryname autocomplete="off"
             infotext="Namn på motpart"/><br/>
      <input name="signatorycompany" type="text" value=signatorycompany autocomplete="off"
             infotext="Titel, företag"/><br/>
      <input name="signatorynumber" type="text" value=signatorynumber autocomplete="off"
             infotext="Orgnr/Persnr"/><br/>
      <input name="signatoryemail"  type="email" value=signatoryemail autocomplete="off"
             infotext="Personens e-mail"/><br/>
      <small><a onclick="return signatoryremove(this.parentNode);" href="#">Ta bort</a></small>
    </div>

    
showFileImages ::(EmbedAsAttr m (Attr [Char] [Char])) => File -> JpegPages -> [XMLGenT m (HSX.XML m)]    
showFileImages File{fileid} (JpegPages jpgpages) =
   [ <div id=("page" ++ show pageno) class="pagediv"><img class="pagejpg" src=("/pages/" ++ show fileid ++ "/" ++ show pageno) width="300" /></div> |
     pageno <- [1..(length jpgpages)]]
     
showFileImages _ JpegPagesPending = 
   [ <div class="pagejpga4 pagejpg">
      <img class="waiting" src="/theme/images/wait30trans.gif"/>
     </div> ]
     
showFileImages _ (JpegPagesError normalizelog) = 
   [ <div class="pagejpga4 pagejpg">
      <% normalizelog %>
     </div> ]
     
showFilesImages2 :: (EmbedAsAttr m (Attr [Char] [Char])) => [(File, JpegPages)] -> XMLGenT m (HSX.XML m)
showFilesImages2 files = <span><% concatMap (uncurry showFileImages) files %></span> 

showDocumentBox :: (EmbedAsAttr m (Attr [Char] [Char])) => XMLGenT m (HSX.XML m)
showDocumentBox = 
    <div id="documentBox">
     <div class="pagejpga4 pagejpg">
      <img class="waiting" src="/theme/images/wait30trans.gif"/>
     </div>
    </div> 

{-

   Document is invalid
   Fel filformat
   Vi beklagar, fel filformat

   mp3 -- we cannot do anything with this document
-}

emptyDetails :: SignatoryDetails
emptyDetails = SignatoryDetails 
          { signatoryname = BS.empty
          , signatorycompany = BS.empty
          , signatorynumber = BS.empty
          , signatoryemail = BS.empty
          , signatorynameplacements = []
          , signatorycompanyplacements = []
          , signatorynumberplacements = []
          , signatoryemailplacements = []
          , signatoryotherfields = []
          }

{- |
   link does not belong to user with uid
 -}
isNotLinkForUserID :: UserID
                   -> SignatoryLink
                   -> Bool
isNotLinkForUserID uid link =
    hasNoUserID || notSameUserID
        where hasNoUserID = isNothing $ maybesignatory link
              notSameUserID = uid /= linkuid
              linkuid = unSignatory $ fromJust $ maybesignatory link

{- |
   Show the document to the author with controls he needs.
 -}
pageDocumentForAuthor :: Context 
             -> Document 
             -> User
             -> (HSPT IO XML) 
pageDocumentForAuthor ctx
             document@Document{ documentsignatorylinks
                              , documenttitle
                              , documentid
                              , documentstatus
                              , documentdaystosign
                              , documentinvitetext
                              } 
             author =
   let helper = [ showSignatoryEntryForEdit2 "signatory_template" "" "" "" ""
                , <script> var documentid = "<% show $ documentid %>"; 
                  </script>
                ]
       authorid = userid author
       -- the author gets his own space when he's editing
       allinvited = filter (isNotLinkForUserID authorid) documentsignatorylinks
       authorhaslink = not $ null $ filter (not . isNotLinkForUserID authorid) documentsignatorylinks
       documentdaystosignboxvalue = maybe 7 id documentdaystosign
       timetosignset = isJust documentdaystosign --swedish low constrain
       documentauthordetails = signatoryDetailsFromUser author
   in showDocumentPageHelper document helper 
           (documenttitle)  
      <div>
       <div id="loading-message" style="display:none">
            Loading pages . . .
       </div>
       <div id="edit-bar">
        -- someone please refactor this. the then statement is so long I can't see the else!
        <%if documentstatus == Preparation
           then 
             <span>
               <script type="text/javascript">
                 <% "var docstate = " ++ (buildJS documentauthordetails $ map signatorydetails documentsignatorylinks) ++ ";" %>
               </script>
              <form method="post" name="form" action=(LinkIssueDoc documentid) id="main-document-form"> 
              Avsändare<br/>
              <div style="margin-bottom: 10px;" id="authordetails">
              <strong><span id="sauthorname"><% addbr $ signatoryname documentauthordetails %></span></strong>
              <span id="sauthorcompany"><% addbr $ signatorycompany documentauthordetails %></span>
              <span id="sauthornumber"><% addbr $ signatorynumber documentauthordetails %></span>
              <span id="sauthoremail"><% addbr $ signatoryemail documentauthordetails %></span>
              </div>

              Användarroll 
              <% if authorhaslink 
                  then
                      <select name="authorrole" id="authorroledropdown">
                                  <option value="signatory">Undertecknare</option>
                                  <option value="secretary">Sekreterare</option>
                      </select>
                  else
                      <select name="authorrole" id="authorroledropdown">
                                  <option value="secretary">Sekreterare</option>
                                  <option value="signatory">Undertecknare</option>
                      </select> %>

              <br /><br />

              Motpart<br/>
              <div id="signatorylist">
               <% map showSignatoryEntryForEdit (if null allinvited
                                                 then [emptyDetails] 
                                                 else map signatorydetails allinvited) %>
              </div>
              <small><a id="addsiglink" onclick="signatoryadd(); return false;" href="#">Lägg till fler</a></small>
              <div style="margin-top: 20px">
              <small><a rel="#edit-invite-text-dialog" id="editinvitetextlink" href="#" style="padding-top:3px">Hälsningsmeddelande</a></small>
              <input type="hidden" id="invitetext" name="invitetext" value=documentinvitetext />
              </div>
              <div style="margin-top: 20px">
              <span>
              <input type="checkbox" class="addremovecheckbox flashOnClick" rel="#daystosignbox" location="#datetosigncontainer" oldlocation="#hiddenttimestuffbox" autocomplete="off" value=(if timetosignset then "on" else "off") ></input> Välj förfallodatum
                <div id="datetosigncontainer">  </div>
                <% if timetosignset
                   then <span/>
                   else <span class="hidden flashMessage" > Varning: Om du väljer ett förfallodatum kan du inte återkalla inbjudan innan datumet förfallit. Detta regleras av avtalslagen.</span>
                   
                %>   
              </span>
              <div style="height: 2px;"/>
              <input class="bigbutton cross-button" type="submit" name="final" value="Underteckna" id="signinvite" rel="#dialog-confirm-signinvite"/> <br />
              <input class="button" type="submit" name="save" value="Spara som utkast"/>
              </div>
              </form>
              <span class="localdialogs">
                <form method="post" name="form" action=(LinkIssueDoc documentid) class="overlay redirectsubmitform" id="dialog-confirm-signinvite" rel="#main-document-form">  
                   <a class="close"> </a>
                   <h2 id="dialog-title-sign">Underteckna</h2>
                   <h2 id="dialog-title-send">Skicka inbjudan</h2>
                   <div id="dialog-confirm-text-sign">
                    <p>Är du säker att du vill underteckna dokumentet <strong><% documenttitle %></strong>?</p>
                    
                    <p>När du undertecknat kommer en automatisk inbjudan att skickas till 
                                    
                    <span class="Xinvited">Invited</span> med e-post.</p>
                   </div>

                   <div id="dialog-confirm-text-send">
                     <p>Du har valt en sekreterarroll och kommer själv inte att underteckna. Är du säker på att du vill skicka en inbjudan att underteckna dokumentet <strong><% documenttitle %></strong> till <span class="Xinvited">Invited</span>?</p>
                   </div>
                   
                   <div class="buttonbox" >
                       <input type="hidden" name="final" value="automatic"/>
                       <button class="close button" type="button"> Avbryt </button>
                       <button class="submiter button" type="button"> Underteckna </button>
                       </div>
                 </form>  
                 <form method="post" name="form" action="" class="overlay" id="edit-invite-text-dialog" >  
                   <a class="close"> </a>
                   <h2>Hälsningsmeddelande</h2>
                   <div style="border:1px solid #DDDDDD;padding:3px;margin:5px"> 
                   <% fmap cdata $ mailInvitationToSignContent (ctxtemplates ctx) False ctx document author Nothing%>
                   </div>
                   <div class="buttonbox" >
                       <button class="close button" type="button"> Avbryt </button>
                       <button class="editer button" type=""> Skriv eget meddelande </button>
                       <button class="close button" type="button" id="editing-invite-text-finished"> Ok </button>
                   </div>
                 </form>  
                 <div class="hidden" id="hiddenttimestuffbox">
                       <div id="daystosignbox">Undertecknas inom (dagar)
                        <BR/>
                        <input type="text" id="daystosign" name="daystosign" value=documentdaystosignboxvalue maxlength="2" size="2" autocomplete="off"/>
                        <small> <a  class="datetodaystip" rel="#daystosign"> </a> </small>
                       </div>
                 </div>
               </span>
             </span>
           else
               <span>
               <% if documentstatus == Pending || documentstatus == AwaitingAuthor 
                   then
                      <script type="text/javascript" language="Javascript" src="/js/showfields.js">  </script>
                   else <span /> %>
               <% if ((documentstatus == Pending || documentstatus == AwaitingAuthor) &&  anyInvitationUndelivered document)
                          then <p> Adressen 
                                   <strong>
                                    <% BS.intercalate (BS.fromString ", ") $ map (signatoryemail . signatorydetails) $ undeliveredSignatoryLinks document %> 
                                   </strong> existerar inte. Kontrollera adressen och försök igen.
                               </p>
                          else <span/>
               %>       
               <script type="text/javascript">
                 <% "var docstate = " ++ (buildJS documentauthordetails $ map signatorydetails documentsignatorylinks) ++ ";" %>
               </script>
               
              <div id="signatorylist">
                 <% map (showSignatoryLinkForSign ctx document author) documentsignatorylinks
                 %>
              </div>
              <% if documentstatus == AwaitingAuthor
                  then <form method="post" action=""><input class="bigbutton cross-button" type="submit" name="final" value="Underteckna" id="signinvite" /></form>
                  else <span />%>
              </span>
              %>
            <% if (documentstatus == Pending || documentstatus == AwaitingAuthor) 
                then 
                   if not timetosignset
                    then <span>
                     <input class="button cancel" type="button" name="cancel" value="Återkalla inbjudan"  rel="#cancel-by-author-dialog" />    
                     <span class="localdialogs">
                     <form method="post" action=(LinkCancel document) class="overlay" id="cancel-by-author-dialog">
                                <a class="close"> </a>
                                <h2> Återkalla inbjudan </h2>
                                <p>Är du säker att du vill återkalla din inbjudan att underteckna dokumentet?
                                <BR/>När du återkallat inbjudan kommer nedanstaende meddelande att skickas till dina motparter.
                                </p>
                                <div style="border:1px solid #DDDDDD;padding:3px;margin:5px"> 
                                 <% fmap cdata $ mailCancelDocumentByAuthorContent  (ctxtemplates ctx) False Nothing ctx document author%>
                                </div>
                                <div class="buttonbox" >
                                   <button class="close button" type="button"> Avbryt </button>
                                   <button class="editer button" type=""> Skriv eget meddelande </button>
                                   <button class="submiter button" type="button"> Återkalla inbjudan</button>
                                </div>
                          </form>
                       </span>
                       </span>
                    else <span>Du kan inte återkalla inbjudan före förfallodatum.</span>
                else <span/>
             %>         
            <% fmap cdata $
               if (documentstatus == Canceled || documentstatus == Timedout || documentstatus == Rejected || documentstatus == Withdrawn)
               then renderActionButton  (ctxtemplates ctx) (LinkRestart documentid) "restartButtonName"
               else return ""
             %>  
       </div>
      </div>

{- |
   Show the document for Viewers (friends of author or signatory).
   Show no buttons or other controls
 -}
pageDocumentForViewer :: Context -> Document -> User -> (HSPT IO XML) 
pageDocumentForViewer ctx
             document@Document{ documentsignatorylinks
                              , documenttitle
                              , documentid
                              , documentstatus
                              } 
             author
             =
   let helper = [ showSignatoryEntryForEdit2 "signatory_template" "" "" "" ""
                , <script> var documentid = "<% show $ documentid %>"; 
                  </script>
                ]
       allinvited = documentsignatorylinks
       documentauthordetails = signatoryDetailsFromUser author
   in showDocumentPageHelper document helper 
           (documenttitle)  
      <div>
       <div id="loading-message" style="display:none">
            Loading pages . . .
       </div>
       <div id="edit-bar">
                <script type="text/javascript" language="Javascript" src="/js/showfields.js"> 
                </script>
                <script type="text/javascript">
                  <% "var docstate = " ++ (buildJS documentauthordetails $ map signatorydetails documentsignatorylinks) ++ ";" %>
                </script>
               
              <div id="signatorylist">
                 <% map (showSignatoryLinkForSign ctx document author) allinvited %>
              </div>
       </div>
      </div>


showDocumentPageHelper
    :: (XMLGenerator m, 
        HSX.EmbedAsChild m c,
        EmbedAsAttr m (Attr [Char] KontraLink),
        HSX.EmbedAsChild m d,
        EmbedAsAttr m (Attr [Char] BS.ByteString)) =>
        DocState.Document
     -> c
     -> BS.ByteString
     -> d
     -> XMLGenT m (HSX.XML m)
showDocumentPageHelper document helpers title content =
    <div class="docview">
     <div style="display: none">
      <% helpers %>
     </div>
      <div class="docviewleft">
       <% showDocumentBox%>
      </div>
      <div class="docviewright"> 
       <p><strong><% title %></strong><br/>
          <small><a href=(LinkIssueDocPDF document) target="_blank">Ladda ned PDF</a></small></p>
       <% content %>
      </div>
     <div class="clearboth"/>
    </div> 

showSignatoryLinkForSign :: Context -> Document -> User -> SignatoryLink -> GenChildList (HSPT' IO)
showSignatoryLinkForSign ctx@(Context {ctxmaybeuser = muser})  document author siglnk@(SignatoryLink{  signatorylinkid 
                                       , maybesigninfo
                                       , maybeseeninfo
                                       , invitationdeliverystatus
                                       , signatorydetails = SignatoryDetails
                                                            { signatoryname
                                                            , signatorynumber
                                                            , signatorycompany
                                                            , signatoryemail
                                                            , signatoryotherfields
                                                            }
                                         }) =
   let
      wasSigned =  isJust maybesigninfo
      wasSeen = isJust maybeseeninfo
      isTimedout = documentstatus document == Timedout
      isCanceled = documentstatus document == Canceled
      isRejected = documentstatus document == Rejected
      isWithDrawn = documentstatus document == Withdrawn
      dontShowAnyReminder = isTimedout || isCanceled || isRejected || isWithDrawn
      status =  caseOf
                [
                ( invitationdeliverystatus == Undelivered, <span>
                                                                                   <img src="/theme/images/status_rejected.png"/>
                                                                                   <span style="color:#000000;position:relative;top:-3px">!</span>
                                                                              </span>), 
                ( isWithDrawn, <img src="/theme/images/status_rejected.png"/>), 
                ( isCanceled, <img src="/theme/images/status_rejected.png"/>), 
                ( isRejected, <img src="/theme/images/status_rejected.png"/>), 
                ( isTimedout, <img src="/theme/images/status_timeout.png"/>), 
                (wasSigned, <img src="/theme/images/status_signed.png"/>),
                (wasSeen, <img src="/theme/images/status_viewed.png"/> )
               ]
                <img src="/theme/images/status_pending.png"/>
      message = caseOf
                [
                (wasSigned, "Undertecknat " ++ showDateOnly (signtime $ fromJust maybesigninfo) ),
                (isTimedout, "Förfallodatum har passerat"),
                (isCanceled || isRejected || isWithDrawn, "" ),
                (wasSeen,  "Granskat " ++ showDateOnly (signtime $ fromJust maybeseeninfo))]
                 "Har ej undertecknat"       
      isCurrentUserAuthor = maybe False (isAuthor document) muser
      isCurrentSignatorAuthor = (fmap (unEmail . useremail . userinfo) muser) ==  (Just signatoryemail)    
      reminderText = if (wasSigned)
                      then "Skicka dokumentet igen"
                      else "Skicka påminnelse"
      reminderSenderText = 
                     if (wasSigned)
                      then "Skicka"
                      else "Skicka påminnelse"               
      reminderEditorText = "Skriv eget meddelande"                          
      reminderDialogTitle = reminderText
      reminderMessage =  fmap cdata $  mailDocumentRemindContent  (ctxtemplates ctx) Nothing ctx document siglnk author
      dialogHeight =   if (wasSigned) then "400" else "600"
      reminderForm = <span>
                      <a style="cursor:pointer" class="prepareToSendReminderMail" rel=("#siglnk" ++ (show signatorylinkid ))>  <% reminderText %>  </a>
                      <form class="overlay" action=(LinkRemind document siglnk) method="POST" title=reminderDialogTitle width="600" height=dialogHeight id=("siglnk" ++ (show signatorylinkid))>
                       <a class="close"> </a>
                       <h2> <% reminderDialogTitle %> </h2>
                       <div style="border:1px solid #DDDDDD;padding:3px;margin:5px"> 
                         <% reminderMessage %>
                       </div>
                       <div class="buttonbox">
                       <button class="close button" type="button"> Avbryt </button>
                       <button class="editer button" type="button"> <%reminderEditorText%> </button>
                       <button class="submiter button" type="button"> <%reminderSenderText%> </button>
                       </div>
                      </form>     
                    </span>  
      changeEmailAddress = 
                   <span>
                      <a style="cursor:pointer" class="replacebynextonclick"> Skicka inbjudan till ny adress  </a>
                      <form action=(LinkChangeSignatoryEmail (documentid document) signatorylinkid) method="POST" style="display:none">
                        <input type="text" style="width:170px" name="email" value=(BS.toString signatoryemail)/>
                        <input type="submit" style="width:100px" value="Skicka"/>
                      </form>     
                   </span>                
   in asChild <div class=(if isCurrentSignatorAuthor then "author" else "signatory")><% 
                [asChild status,asChild " "] ++
                (if BS.null signatoryname then [] else [ asChild <strong><% signatoryname %></strong>, asChild <br/> ]) ++
                (if BS.null signatorycompany then [] else [ asChild signatorycompany, asChild <br/> ]) ++
                (if BS.null signatorynumber then [] else [ asChild signatorynumber, asChild <br/> ]) ++
                (if BS.null signatoryemail then [] else [ asChild signatoryemail, asChild <br/> ]) ++
                [asChild <div class="signatoryfields"><% map displayField signatoryotherfields %></div>] ++
                ([asChild message]) ++
                (if (isCurrentUserAuthor && (not isCurrentSignatorAuthor) && (not dontShowAnyReminder) && (invitationdeliverystatus /= Undelivered)) then [asChild <br/> ,asChild reminderForm] else []) ++
                (if (isCurrentUserAuthor && (invitationdeliverystatus == Undelivered) && (not dontShowAnyReminder)) then [asChild <br/> ,asChild changeEmailAddress] else [])
                %>
              </div>

displayField::(Monad m) => FieldDefinition -> (HSPT m XML) 
displayField FieldDefinition {fieldlabel, fieldvalue} 
    | fieldvalue == BS.fromString "" = <span />
    | otherwise        = <div><span class="fieldlabel"><% fieldlabel %>: </span><span class="fieldvalue"><% fieldvalue %></span></div>

pageDocumentForSign :: KontraLink 
                    -> Document 
                    -> Context
                    -> SignatoryLink
                    -> Bool 
                    -> User
                    -> (HSPT IO XML) 
pageDocumentForSign action document ctx  invitedlink wassigned author =
   let helpers = [ <script> var documentid = "<% show $ documentid document %>"; 
                  </script>
                , <script type="text/javascript">
                   <% "var docstate = " ++ (buildJS documentauthordetails $ map signatorydetails (documentsignatorylinks document)) ++ "; docstate['useremail'] = '" ++ (BS.toString $ signatoryemail $ signatorydetails invitedlink) ++ "';" %>
                  </script>
                , <script src="/js/signatory.js" /> ]
       magichash = signatorymagichash invitedlink
       authorname = signatoryname documentauthordetails
       allbutinvited = {- filter (/= invitedlink) -} (documentsignatorylinks document)
       documentauthordetails = signatoryDetailsFromUser author
       rejectMessage =  fmap cdata $ mailRejectMailContent (ctxtemplates ctx) Nothing ctx (prettyName author) document (personname invitedlink)
   in showDocumentPageHelper document helpers
              (documenttitle document) $
              <span>
                 <p>Vänligen var noga med att granska dokumentet och kontrollera 
                    uppgifterna nedan innan du undertecknar.</p>   

                 <% map (showSignatoryLinkForSign ctx document author) (allbutinvited) %>
                 <% caseOf 
                    [(wassigned ,
                              <div>Du har redan undertecknat!</div>),
                    (documentstatus document == Timedout, 
                              <div>Förfallodatum har passerat!</div>),
                    (documentstatus document == Pending, 
                              <div>
                                 <input class="bigbutton" type="submit" name="sign" value="Underteckna" id="sign" rel="#dialog-confirm-sign"/>
                                 <input class="bigbutton" type="submit" name="cancel" value="Avvisa" rel="#dialog-confirm-cancel" id="cancel"/>
                              </div>) ]
                     <span/>                 
                 %>
                 {- <small>Jag vill veta mer <a href="/about" target="_blank">om SkrivaPå</a>.</small> -}
                 <span class="localdialogs ">
                  <form method="post" name="form" action=action id="dialog-confirm-sign" class="overlay">     
                     <a class="close"> </a>                  
                     <h2>Underteckna</h2>  
                     <p>Är du säker att du vill underteckna dokumentet <strong><% documenttitle document %></strong>?</p>
                     <p>När <% partyUnsignedMeAndListString magichash document %> undertecknat blir 
                      avtalet <strong>juridiskt bindande</strong> och
                      det färdigställda avtalet skickas till din e-post.</p>
                      <div class="buttonbox">
                      <input type="hidden" name="sign" value="automatic"/>
                      <button class="close button" type="button"> Avbryt </button>
                      <button class="submiter button" type="button"> Underteckna </button>
                      </div>
                  </form>
                 <form method="post" name="form" action=action id="dialog-confirm-cancel" class="overlay">   
                    <a class="close"> </a>     
                       <h2>Avvisa</h2>                 
                    <p>Är du säker på att du vill avvisa dokumentet <strong><% documenttitle document %></strong>?</p>
                    <p>När du avvisat kommer vi att skicka ett e-postmeddelande för att meddela <strong><% authorname %></strong>.</p>
                    <div style="border:1px solid #DDDDDD;padding:3px;margin:5px"> 
                     <% rejectMessage %>
                    </div>
                    <div class="buttonbox">
                     <input type="hidden" name="cancel" value="automatic"/>
                     <button class="close button" type="button"> Avbryt </button>
                     <button class="editer button" type="button"> Skriv eget meddelande </button>
                     <button class="submiter button" type="button"> Avvisa </button>
                    </div> 
                 </form> 
                 </span>
                 
              </span>
     



--We keep this javascript code generation for now
jsArray :: [[Char]] -> [Char]
jsArray xs = "[" ++ (joinWith ", " xs) ++ "]"

buildDefJS :: FieldDefinition -> [Char]
buildDefJS (FieldDefinition { fieldlabel, fieldvalue, fieldplacements }) = 
    "{ label: " ++ show fieldlabel -- show because we need quotes
                    ++ ", value: " ++ show fieldvalue
                    ++ ", placements: " ++ (jsArray (map buildPlacementJS fieldplacements))
                    ++ " }"
                    
buildPlacementJS :: FieldPlacement -> [Char]
buildPlacementJS (FieldPlacement { placementx, placementy, placementpage, placementpagewidth, placementpageheight }) = 
    "{ x: " ++ show placementx 
                ++ ", y: " ++ show placementy
                ++ ", page: " ++ show placementpage
                ++ ", h: " ++ show placementpageheight
                ++ ", w: " ++ show placementpagewidth
                ++ " }"
                
buildSigJS :: SignatoryDetails -> [Char]
buildSigJS (SignatoryDetails { signatoryname, signatorycompany, signatorynumber, signatoryemail, signatorynameplacements, signatorycompanyplacements, signatoryemailplacements, signatorynumberplacements, signatoryotherfields }) = 
    "{ name: " ++ show signatoryname
                   ++ ", company: " ++ show signatorycompany
                   ++ ", email: " ++ show signatoryemail
                   ++ ", number: " ++ show signatorynumber
                   ++ ", nameplacements: " ++ (jsArray (map buildPlacementJS signatorynameplacements))
                   ++ ", companyplacements: " ++ (jsArray (map buildPlacementJS signatorycompanyplacements))
                   ++ ", emailplacements: " ++ (jsArray (map buildPlacementJS signatoryemailplacements))
                   ++ ", numberplacements: " ++ (jsArray (map buildPlacementJS signatorynumberplacements))
                   ++ ", otherfields: " ++ (jsArray (map buildDefJS signatoryotherfields))
                   ++ " }"
                   
buildJS :: SignatoryDetails -> [SignatoryDetails] -> [Char]
buildJS authordetails signatorydetails = 
    "{ signatories: " ++ sigs
                          ++ ", author: " ++ buildSigJS authordetails
                          ++ " }" where 
                              sigs = if (length signatorydetails) > 0
                                     then (jsArray (map buildSigJS signatorydetails))
                                     else (jsArray [(buildSigJS emptyDetails)])
                                    
defaultInviteMessage :: BS.ByteString
defaultInviteMessage = BS.empty     
