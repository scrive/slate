{-# LANGUAGE IncoherentInstances #-}
{-# OPTIONS_GHC -F -pgmFtrhsx #-}

module DocView where
import AppView
import Data.List
import DocState
import HSP
import qualified Data.ByteString.UTF8 as BS
import qualified Data.ByteString as BS
import qualified HSX.XMLGenerator as HSX (XML)
import qualified HSX.XMLGenerator
import User
import Control.Monad

jquery :: (XMLGenerator m) => [XMLGenT m (HSX.XML m)] 
jquery = [<script src="/js/jquery-1.4.2.min.js" zonk="öåä">öåä</script>,
          <script src="/js/jquery-ui-1.8.custom.min.js"/>]


mkSignDocLink :: String -> DocumentID -> SignatoryLinkID -> String
mkSignDocLink hostpart documentid signaturelinkid =
    hostpart ++ "/sign/" ++ show documentid ++ "/" ++ show signaturelinkid

-- * Convenience Functions

{-
dateStr :: ClockTime -> String
dateStr ct =
  formatCalendarTime
    defaultTimeLocale
    "%a, %B %d, %Y at %H:%M:%S (UTC)"
    (toUTCTime ct)
-}

-- dateStr1 _ = "Today"

-- * Main Implementation

instance (XMLGenerator m) => (EmbedAsChild m (Document, Bool)) where
    asChild (entry, alt) = 
          <%
           <tr class=(if alt then "alt" else "")>
            <td>
             <a href=("/issue/" ++ show (documentid entry))><% title entry %></a>
            </td>
            <td>
             <% show $ documentmtime entry %>
            </td>
            <td>
             <% show (status entry) %>
            </td>
           </tr>
          %>

instance (XMLGenerator m) => (EmbedAsChild m [Document]) where
    asChild (entries) = 
        <% 
         <table class="commentlist" width="100%">
           <% zip entries (cycle [False,True]) %>
         </table>
        %>
{-
seeOtherXML :: (XMLGenerator m) => String -> XMLGenT m (HSX.XML m)
seeOtherXML url = <a href=url alt="303 see other"><% url %></a>
-}

concatSignatories siglinks = 
    concat $ intersperse ", " $ map (BS.toString . signatoryname) siglinks 

oneDocumentRow document = 
    let link = "/issue/" ++ show (documentid document)
        mk x = <a href=link><% x %></a>
        statusimg = "/theme/images/" ++
                    case status document of
                      Preparation -> "status_draft.png"
                      ReadyToSign  -> "status_pending.png"
                      Closed -> "status_signed.png"
                      Canceled -> "status_rejected.png"
                      Timedout -> "status_timeout.png"
                      Rejected -> "status_rejected.png"
    in
    <tr>
     <td class="tdleft">
      <input type="checkbox"/>
     </td>
     <td><img width="17" height="17" src=statusimg/></td>
     <td><% mk $ concatSignatories (signatorylinks document) %></td>
     <td><% mk $ title document %></td>
     <td class="tdright"><% show $ documentmtime document %></td>
     {- <td>15</td> -}
     {- <td class="tdright">15</td> -}
    </tr>


listDocuments :: (XMLGenerator m) => [Document] -> XMLGenT m (HSX.XML m)
listDocuments documents = 
    <div>
     <br/>
     <table class="doctable" cellspacing="0">
      <col class="tdleft"/>
      <col/>
      <col/>
      <col/>
      <col class="tdright"/>
      <thead>
       <tr>
        <td>Alla</td>
        <td></td> {- status icon -}
        <td>Personer</td>
        <td>Avtal</td>
        <td>Senaste handelse</td>
        {- <td>Dagar kvar</td> -}
       </tr>
      </thead>
      <tfoot>
       <tr><td colspan="6">Foot</td></tr>
      </tfoot>
      <tbody>
       <% map oneDocumentRow documents %>
      </tbody>
     </table>
   </div>

showFile
  :: (EmbedAsChild m String) =>
     File -> XMLGenT m (HSX.XML m)
showFile file = <li><% show file %></li>

showSignatory
  :: (EmbedAsChild m String, Show a) => a -> XMLGenT m (HSX.XML m)
showSignatory sig = <li><% show sig %></li>


{-
showSignatoryEntry
  :: (HSX.XMLGenerator.EmbedAsAttr
        m (HSX.XMLGenerator.Attr [Char] [Char]),
      HSX.XMLGenerator.EmbedAsChild m [Char]) =>
     DocState.SignatoryLink -> HSX.XMLGenerator.GenChildList m
-}
showSignatoryEntryForEdit (SignatoryLink{signatoryname,signatorycompany,signatoryemail}) = 
    showSignatoryEntryForEdit2 "" (BS.toString signatoryname) (BS.toString signatorycompany) 
                                   (BS.toString signatoryemail)

showSignatoryEntryForEdit2 :: (XMLGenerator m) => String -> String -> String -> String -> XMLGenT m (HSX.XML m)
showSignatoryEntryForEdit2 idx signatoryname signatorycompany signatoryemail = 
    <li id=idx>
      <label>Namn på avtalspart</label><br/> 
      <input name="signatoryname" type="text" value=signatoryname/><br/>
      <label>Titel, företag</label><br/>
      <input name="signatorycompany" type="text" value=signatorycompany/><br/>
      <label>Personens e-mail</label><br/>
      <input name="signatoryemail" type="text" value=signatoryemail/><br/>
      <a onclick="return signatoryremove(this);" href="#">Ta bort</a>
      {- days to sign:
         Antal dagar att skriva på -}
    </li>

showSignatoryEntryStatus :: (XMLGenerator m) => SignatoryLink -> XMLGenT m (HSX.XML m)
showSignatoryEntryStatus (SignatoryLink{signatoryname,signatoryemail,maybeseentime,maybesigninfo}) = 
    <li> 
        <b><% signatoryname %></b><br/>
        <% case maybesigninfo of
             Just (SignInfo{signtime}) -> "Undertecknat " ++ show signtime 
             Nothing -> case maybeseentime of
                          Just time -> "Har öppnat dokumentet " ++ show time
                          Nothing -> "Har inte öppnat dokumentet"
        %>
    </li>

 -- FIXME: add info about date viewed, date signed, send reminder, change email
showFileImages file = 
   [ <img src=("/pages/" ++ show (fileid file) ++ "/" ++ show pageno) width="300"/> |
     pageno <- [1..(length (filejpgpages file))]]

showFilesImages2 files = <xml><% concatMap showFileImages files %></xml> 

showDocumentBox document = 
    <div id="documentBox">
        {- <% map showFileImages (files document) %> -}
        Förbereder avtal...
    </div>

{-

   Document is invalid
   Fel filformat
   Vi beklagar, fel filformat

   mp3 -- we cannot do anything with this document
-}


emptyLink = SignatoryLink 
          { signatorylinkid = SignatoryLinkID 0
          , signatoryname = BS.empty
          , signatorycompany = BS.empty
          , signatoryemail = BS.empty
          , maybesignatory = Nothing
          , maybesigninfo  = Nothing
          , maybeseentime  = Nothing
          }
{- showDocument
  :: (EmbedAsChild m [Char], EmbedAsAttr m (Attr [Char] [Char])) =>
     Document -> XMLGenT m (HSX.XML m)
-}
showDocument
  :: (XMLGenerator m,
      EmbedAsAttr m (Attr [Char] BS.ByteString)) =>
     User -> Document -> Bool -> XMLGenT m (HSX.XMLGenerator.XML m)
showDocument user document issuedone =
   let helper = jquery ++ 
                [ <span style="display: none">
                   <% showSignatoryEntryForEdit2 "signatory_template" "" "" "" %>
                  <div id="dialog-confirm-signinvite" title="Underteckna">
	        
            <p> När du bekräftar avtalet kommer en automatisk inbjudan att skickas till 
                <strong><span id="mrx">"Mr X"</span></strong>. 
             <strong>Avtalet blir juridiskt bindande när alla parter undertecknat.</strong>
            </p>
            
            <p>Det är först då vi tar betalt. 
            Vi fakturerar månadsvis. Era fakturauppgifter:</p>

            <div class="inlinebox">
            Referens: <% fullname user %> <br/>
            Företag: <% usercompanyname user %> <br/>
            Org nr: <% usercompanynumber user %> <br/>
            Adress: <% userinvoiceaddress user %> <br/>
            Pris: ”20 SEK exkl moms” <br/>
            </div>

           <p>Är du säker på att du vill underteckna avtalet?</p>

{- <span class="ui-icon ui-icon-alert" style="float:left; margin:0 7px 20px 0;"></span>
             These items will be permanently deleted and cannot be recovered. Are you sure?
-}
          </div>

                <div id="dialog-confirm-signinvite-done" title="Avtal undertecknat!">
	        <p> Du har undertecknat avtalet och en inbjudan har nu skickats till <span id="mrx">"Mr X"</span>.</p>

          </div>
        </span>
                , <script> var documentid = <% show $ documentid document %>; 
                           var issuedone = <% if issuedone then "true" else "false" %>;
                  </script>
                , <script type="text/javascript" src="/js/document-edit.js"/>
                ]
   in showDocumentPageHelper ("/issue/" ++ show (documentid document)) document helper (BS.fromString $ "Avtal: " ++ BS.toString (title document))  
      <div>
       <div>Personer:<br/>

        <% if status document == Preparation
           then <span>
              <ol id="signatorylist">
               <% map showSignatoryEntryForEdit (if null (signatorylinks document)
                                                 then [emptyLink] else signatorylinks document) %>
              </ol>
              <a onclick="signatoryadd(); return false;" href="#">Skapa inbjudan</a>
             </span>
           else
              <ol id="signatorylist">
               <% map showSignatoryEntryStatus (signatorylinks document) %>
              </ol>
                           
         %>
         <hr/>
         <% 
           if (status document==Preparation) 
              then <span>
                    <input class="bigbutton" type="submit" name="final" value="Underteckna" id="signinvite"/>
                    <input type="hidden" name="final2" value=""/>
                    <br/>
                    <input class="secbutton" type="submit" name="save" value="Spara till senare"/>
                   </span>
              else <span/>
          %>
       </div>
      </div>

showDocumentPageHelper action document helpers title content =
   <div> 
   <br/>
   <% helpers %>
   <form method="post" id="form" name="form" action=action> 
    <table class="docview">
     <tr>
      <td>
   
       <% showDocumentBox document %>
      </td>
      <td> 
       <p class="headline"><% title %><br/> 
           <small><a href=("/issue/" ++ show (documentid document) ++ "/" ++ BS.toString title ++ ".pdf") target="_blank">Open as PDF</a></small>
       </p>
       <% content %>
      </td>
     </tr>
    </table> 
   </form>
   <div id="dialog-confirm-sign" title="Underteckna">


        <p><strong>Avtalet blir juridiskt bindande när alla parter undertecknat.</strong>
        Då får du ett e-mail med det färdig avtalet.</p>
        
        <p>Är du säker på att du vill underteckna avtalet?</p>

   </div>

   </div>


showDocumentForSign :: (XMLGenerator m) =>
                       String -> Document -> BS.ByteString -> BS.ByteString -> Bool -> XMLGenT m (HSX.XML m)
showDocumentForSign action document authorname invitedname wassigned =
   let helper = jquery ++ [ <script type="text/javascript" src="/js/document-edit.js"/>
                , <script> var documentid = <% show $ documentid document %>; 
                  </script>
                          ]
   in showDocumentPageHelper action document helper (BS.fromString $ "Avtal: " ++ BS.toString(title document)) $
        if wassigned 
           then <span>Du har redan skrivit på!</span>
           else <span>
                
                <p>Välkommen <% invitedname %>,</p>

                <p>Genom skrivaPå kan du underteckna juridiskt bindande avtal online. På vänster sida har du avtalet <strong><% title document %></strong> som <strong><% authorname %></strong> har bjudit in dig att underteckna.</p>

                <p>Om du inte är <strong><% invitedname %></strong> klicka av "avvisa".</p>

{- Avvisa - gray FIXME -}
                <p>Jag vill veta mer <a href="/about" target="_blank">om skrivaPå</a>.</p>

                   <input type="hidden" name="sign2" value=""/>
                   <input class="bigbutton" type="submit" name="sign" value="Underteckna" id="sign"/>
                </span>

poweredBySkrivaPaPara :: (XMLGenerator m) => XMLGenT m (HSX.XML m)
poweredBySkrivaPaPara = 
    <p>
      {- Med vänliga hälsningar<br/> -}
     <small>Powered by <a href="http://skrivapa.se/">skrivaPå</a></small>
    </p>


invitationMailXml :: (XMLGenerator m) 
                     => Context
                  -> BS.ByteString
                  -> BS.ByteString
                  -> BS.ByteString
                  -> DocumentID
                  -> SignatoryLinkID
                  -> XMLGenT m (HSX.XML m)
invitationMailXml (Context (Just user) hostpart) 
                  emailaddress personname 
                  documenttitle documentid 
                  signaturelinkid = 
    let link = hostpart ++ "/sign/" ++ show documentid ++ "/" ++ show signaturelinkid
        creatorname = BS.toString $ fullname user
    in 
    <html>
     <head>
      <meta http-equiv="content-type" content="text/html; charset=utf-8"/>
     </head>
     <body>
      <p>Hej <% personname %>,</p>
      <p></p>
      <p><strong><% creatorname %></strong> har bjudit in dig att skriva på avtalet <strong><% documenttitle %></strong>. Klicka på länken för att läsa igenom och skriva på.</p>
      <p><a href=link><% link %></a></p>
      <% poweredBySkrivaPaPara %>
     </body>
    </html>

invitationMail :: Context
               -> BS.ByteString
               -> BS.ByteString
               -> BS.ByteString
               -> DocumentID
               -> SignatoryLinkID
               -> IO BS.ByteString
invitationMail ctx emailaddress personname 
               documenttitle documentid signaturelinkid = do
                 let xml = invitationMailXml ctx emailaddress personname 
                           documenttitle documentid signaturelinkid
                           -- FIXME: first part of tuple is Maybe Metadata
                           -- potentially important
                 (_,content) <- evalHSP Nothing xml
                 return (BS.fromString (renderAsHTML content))

closedMailXml :: (XMLGenerator m) 
                     => Context
                  -> BS.ByteString
                  -> BS.ByteString
                  -> BS.ByteString
                  -> DocumentID
                  -> SignatoryLinkID
                  -> XMLGenT m (HSX.XML m)
closedMailXml (Context (Just user) hostpart) 
                  emailaddress personname 
                  documenttitle documentid 
                  signaturelinkid = 
    let link = hostpart ++ "/sign/" ++ show documentid ++ "/" ++ show signaturelinkid
        creatorname = BS.toString $ fullname user
    in 
    <html>
     <head>
      <meta http-equiv="content-type" content="text/html; charset=utf-8"/>
     </head>
     <body>
      <p>Hej <% personname %>,</p>
      <p>Avtalet <strong><% documenttitle %></strong> har undertecknats av alla parter. Avtalet är nu lagligt bindande.</p>
      
      <p>Det färdig avtalet bifogas nedan. Om du har ett konto hos skrivaPå hittar du avtalet under "Avtal". Om du inte har ett konto kan du spara avtalet genom att klicka på länken:</p>

      <p><a href=link><% link %></a></p>
     
      <% poweredBySkrivaPaPara %>
     </body>
    </html>

closedMail :: Context
           -> BS.ByteString
           -> BS.ByteString
           -> BS.ByteString
           -> DocumentID
           -> SignatoryLinkID
           -> IO BS.ByteString
closedMail ctx emailaddress personname 
               documenttitle documentid signaturelinkid = do
                 let xml = closedMailXml ctx emailaddress personname 
                           documenttitle documentid signaturelinkid
                           -- FIXME: first part of tuple is Maybe Metadata
                           -- potentially important
                 (_,content) <- evalHSP Nothing xml
                 return (BS.fromString (renderAsHTML content))
