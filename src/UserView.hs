{-# LANGUAGE FlexibleContexts, FlexibleInstances, MultiParamTypeClasses, NamedFieldPuns #-}
{-# OPTIONS_GHC -F -pgmFtrhsx -Wall #-}
module UserView(viewSubaccounts,passwordChangeMail,showUser,userDetailsSavedFlashMessage,newUserMail,inviteSubaccountMail,pageAcceptTOS,prettyName,mailNewAccountCreatedByAdmin) where

import HSP hiding (Request)
import Happstack.Server.SimpleHTTP
import qualified Data.ByteString as BS
import qualified Data.ByteString.UTF8 as BS
import UserState
import AppView
import User
import KontraLink
import SendMail(Mail,emptyMail,title,content)
import qualified HSX.XMLGenerator


showUser :: User -> HSP.HSP HSP.XML
showUser user = 
    <div class="accounttable">
     <h1><% userfullname user %></h1>
      <div>
       <form action=LinkAccount method="post">
        <table>
         <tr><td>Namn:</td>
             <td><input type="text" name="fullname" value=(userfullname user)/></td>
         </tr>
         <tr><td>E-post:</td>
             <td><% unEmail $ useremail user %></td>
         </tr>
         <tr><td>Företagsnamn:</td>
             <td><input type="text" name="companyname" value=(usercompanyname user)/></td>
         </tr>
         <tr><td>Organisationsnummer:</td>
             <td><input type="text" name="companynumber" value=(usercompanynumber user)/></td>
         </tr>
         <tr><td>Faktureringsadress:</td>
             <td><input type="text" name="invoiceaddress" value=(userinvoiceaddress user)/></td>
         </tr>
       </table>
       <input class="button" type="submit" value="Spara ändringar"/>
      </form>
      <div>
           <form action=LinkAccountPassword method="post">
            <table>
             <tr><td>Nuvarande lösenord:</td>
              <td><input type="password" name="oldpassword" autocomplete="off" /></td>
             </tr>
             <tr><td>Nytt lösenord:</td>
              <td><input type="password" name="password" autocomplete="off" /></td>
             </tr>
             <tr><td>Upprepa nytt lösenord:</td>
              <td><input type="password" name="password2" autocomplete="off" /></td>
             </tr>
            </table>
            <input class="button" type="submit" value="Ändra lösenord"/>
           </form>
          </div>
          <div>
           <a href=LinkSubaccount>Underkonton</a>
          </div>

     </div>
    </div>

pageAcceptTOS :: Context -> BS.ByteString -> Kontra Response
pageAcceptTOS ctx tostext = 
    let toptab = TopEmpty
    in
    renderFromBody ctx toptab kontrakcja $
     <form method="post" action="/accepttos" id="toscontainer" class="overlay">
      <a class="close"> </a>                  
      <h2>Vänligen acceptera användarvillkoren</h2>
      <% cdata $ BS.toString tostext %>
     <br/>
     <input type="checkbox" name="tos" id="tos"/>Jag har läst och accepterar SkrivaPå Allmänna Villkor<br/>
     <div class="buttonbox">
      <input class="submiter button" type="submit" value="Skicka"/>
     </div> 
    </form>
  
oneRow :: (EmbedAsAttr m (Attr [Char] [Char]), EmbedAsAttr m (Attr [Char] UserID)) =>  User -> XMLGenT m (HSX.XMLGenerator.XML m)
oneRow (User{ userfullname, useremail, userid })  = 
    <tr class="ui-state-default">
     <td class="tdleft">
      <input type="checkbox" name="doccheck" value=userid class="check" />
     </td>
     <td><img width="17" height="17" src=""/></td>
     <td><% userfullname %></td>
     <td><% useremail %></td>
     <td> - </td>
     <td class="tdright"></td>
    </tr>


viewSubaccounts :: Context -> [User] -> Kontra Response
viewSubaccounts ctx subusers = 
    renderFromBody ctx TopAccount kontrakcja $ 
    <form method="post" action= LinkSubaccount>
     <h1>Underkonton</h1>
     <table class="doctable" cellspacing="0">
      <col/>
      <col/>
      <col/>
      <col/>
      <col/>
      <thead>
       <tr>
        <td><a href="#" id="all">Alla</a></td>
        <td></td> {- status icon -}
        <td>Namn</td>
        <td>E-post</td>
        <td>Övrigt</td>
        <td></td>
       </tr>
      </thead>
      <tfoot>
       <tr>
        <td colspan="6" style="text-align: right; overflow: hidden;">
          <div class="floatleft">
           <input type="submit" class="button" name="remove" value="Radera"/>
          </div>
          {-
          <div class="floatright">
           <img src="/theme/images/status_draft.png"/> Utkast
           <img src="/theme/images/status_rejected.png"/> Avbrutet
           <img src="/theme/images/status_timeout.png"/> Förfallet
           <img src="/theme/images/status_pending.png"/> Väntar
           <img src="/theme/images/status_viewed.png"/> Granskat
           <img src="/theme/images/status_signed.png"/> Undertecknat
          </div>
          -}
          <div class="clearboth"/>
         </td>
       </tr>
      </tfoot>
     
      <tbody id="selectable">
       <% map oneRow subusers %>
      </tbody>
     </table><br/>
      <table>
	<tr> 
          <td>Namn:</td> 
          <td><input type="text" name="fullname"/></td> 
        </tr>
	<tr>
          <td>E-post:</td> 
          <td><input type="email" name="email"/></td> 
        </tr>
	<tr> 
          <td><input class="button" id="create" type="submit" name="create" value="Skapa ny"/></td>
          <td></td>
	</tr>
      </table>
    </form>

newUserMail :: String -> BS.ByteString -> BS.ByteString -> BS.ByteString -> IO Mail
newUserMail hostpart emailaddress personname newpassword =
    do 
    let title = BS.fromString "Nytt konto"
    content <- htmlHeadBodyWrapIO ""
     <span>
      <p>Hej <strong><% personname %></strong>,</p>

      <p>Jag heter Lukas Duczko och är VD på SkrivaPå. Tack för att du har skapat ett konto hos oss. 
         Vi hoppas att du kommer att bli nöjd med våra tjänster. Tveka inte att höra av dig med 
         feedback eller bara en enkel hälsning. Din åsikt är värdefull.</p>

      <p>Användarnamn: <b><% emailaddress %></b><br/>
         Lösenord: <b><% newpassword %></b><br/>
      </p>
      <p>
      <a href=(hostpart ++ "/login")><% hostpart ++ "/login" %></a>
      </p>

      <p>Med vänliga hälsningar<br/>/Lukas Duczko och team <a href=(hostpart ++ "/")>SkrivaPå</a>.
      </p>
     </span>
    return $ emptyMail {title=title, content = content} 
    
passwordChangeMail :: String
                   -> BS.ByteString
                   -> BS.ByteString
                   -> BS.ByteString
                   -> IO Mail
passwordChangeMail hostpart emailaddress personname newpassword = 
    do 
    let title = BS.fromString "Nytt lösenord"
    content <- htmlHeadBodyWrapIO ""
     <span>
      <p>Hej <strong><% personname %></strong>,</p>

      <p>Här kommer ditt nya lösenord. Vänligen ändra lösenordet så snart som möjligt.</p>

      <p>Användarnamn: <span style="color: orange; text-weight: bold"><% emailaddress %></span><br/>
         Lösenord: <span style="color: orange; text-weight: bold"><% newpassword %></span><br/>
      </p>
      <p>
      <a href=(hostpart ++ "/login")><% hostpart ++ "/login" %></a>
      </p>

      <% poweredBySkrivaPaPara hostpart %>
     </span>
    return $ emptyMail {title=title, content = content} 


inviteSubaccountMail :: String
                     -> BS.ByteString
                     -> BS.ByteString
                     -> BS.ByteString
                     -> BS.ByteString
                     -> BS.ByteString
                     -> IO Mail
inviteSubaccountMail hostpart supervisorname companyname emailaddress personname newpassword = 
    do 
     let title = BS.concat [(BS.fromString "Inbjudan från "),(supervisorname),(BS.fromString " till underkonto" )]
     content <- htmlHeadBodyWrapIO ""
       <span>
       <p>Hej <strong><% personname %></strong>,</p>
 
       <p><strong><% supervisorname %></strong> har bjudit in dig att öppna ett konto på SkrivaPå genom vilket du kan
          skriva avtal för <strong><% companyname %></strong>. Observera att detta konto inte är
          avsett för privat bruk.</p>     
       <p>Användarnamn: <span style="color: orange; text-weight: bold"><% emailaddress %></span><br/>
          Lösenord: <span style="color: orange; text-weight: bold"><% newpassword %></span><br/>
       </p>
 
       <p>
       <a href=(hostpart)><% hostpart %></a>
       </p>
 
       <% poweredBySkrivaPaPara hostpart %> 
       </span>
     return $ emptyMail{title=title, content = content} 

mailNewAccountCreatedByAdmin:: Context-> BS.ByteString -> BS.ByteString -> BS.ByteString ->  IO Mail
mailNewAccountCreatedByAdmin ctx fullname email password =    do 
    let title = BS.fromString "Nytt konto"
    let creatorname = maybe BS.empty prettyName (ctxmaybeuser  ctx)
    content <- htmlHeadBodyWrapIO ""
     <span>
      <p>Hej <strong><% fullname %></strong>,</p>

      <p><%creatorname%> har bjudit in dig till ett konto på tjänsten SkrivaPå. </p>

      <p>SkrivaPå är ett webbaserat tredjepartsnotariat som gör det möjligt att underteckna, 
         hantera och arkivera avtal elektroniskt. SkrivaPå är som Gmail för dina avtal.</p>

      <p>Användarnamn: <b><% email %></b><br/>
         Lösenord: <b><% password %></b><br/>
      </p>
      <p>
      <a href=(ctxhostpart ctx)><% ctxhostpart ctx %></a>
      </p>

          <% poweredBySkrivaPaPara $ ctxhostpart ctx%> 
     </span>
    return $ emptyMail {title=title, content = content} 
    

userDetailsSavedFlashMessage :: HSP.HSP HSP.XML
userDetailsSavedFlashMessage = 
    <div>Dina kontoändringar har sparats.</div>

{- Same as personname (username or email) from DocView but works on User not singlinks-}
prettyName::User -> BS.ByteString
prettyName u = if (BS.null $ userfullname u)
               then unEmail $ useremail u 
               else userfullname u
          
