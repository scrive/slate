module API.MailAPI (
      handleMailCommand
    , mailAPI
    , parseSimpleEmail
    , parseSignatory
    , allStrings
    , parseEmailMessageToParts
    ) where

import DB.Classes
import Doc.DocState
import Company.Model
import User.Model
import Kontra
import Misc
import qualified AppLogger as Log (debug)
import qualified Doc.DocControl as DocControl
import Control.Monad.Reader
import InputValidation
import Control.Monad.Error
import Data.Functor
import Data.List
import Data.Maybe
import Happstack.Server hiding (simpleHTTP, host)
import Happstack.StaticRouting(Route, Path)
import Happstack.State (update)
import Text.JSON
import Text.JSON.String
import Codec.MIME.Decode
import qualified Codec.MIME.Parse as MIME
import qualified Codec.MIME.Type as MIME
import qualified Data.ByteString as BS
import qualified Data.ByteString.Char8 as BSC
import qualified Data.ByteString.Lazy as BSL
import qualified Data.ByteString.UTF8 as BS
import Data.Either

import qualified Codec.Text.IConv as IConv
import InspectXMLInstances ()
import API.API
import API.APICommons
import Data.Char
import Mails.MailsData as MD
import Data.String.Utils
import Util.StringUtil
import Doc.DocViewMail

import Util.JSON
data MailAPIContext = MailAPIContext { ibody :: APIRequestBody
                                     , icontent :: BS.ByteString
                                     , ifrom :: BS.ByteString
                                     , ito :: BS.ByteString
                                     }
type MailAPIFunction m a = APIFunction m MailAPIContext a

instance APIContext MailAPIContext where
    apiContext = apiContextForMail

instance JSONContainer MailAPIContext where
    getJSON = ibody
    setJSON j mapictx = mapictx {ibody = j}


apiContextForMail :: Kontrakcja m => m (Either (API_ERROR, String) MailAPIContext)
apiContextForMail = do
    ctx <- getContext
    Input contentspec (Just _filename) _contentType <- getDataFnM (lookInput "mail")
    content <- case contentspec of
        Left filepath -> liftIO $ BSL.readFile filepath
        Right content -> return content
    -- content at this point is basically full MIME email as it was received by SMTP server
    -- can be tested using curl -X POST -F mail=@mail.eml http://url.com/mailapi/
    eresult <- parseEmailMessage (concatChunks content)
    case eresult of
      Left (from,msg) -> do
        Log.debug $ "handleMailAPI: " ++ msg
        let from' = takeWhile (/= '>') $ dropWhile (== '<') $ dropWhile (/= '<') $ BS.toString from
        case (asValidEmail from') of 
             Good _ -> scheduleEmailSendout (ctxesenforcer ctx) $ mailMailApiError (MD.MailAddress {MD.fullname=BS.empty, MD.email = BS.fromString from'}) msg
             _ -> return ()
        return $ Left (API_ERROR_PARSING, "Cannot parse email API call: " ++ msg)
      Right (json, pdf, from, to) -> do
        Log.debug $ "json again: " ++ show json
        return $ Right $ MailAPIContext { ibody    = json
                                        , icontent = pdf
                                        , ifrom    = from
                                        , ito      = to
                                        }

mailAPI :: (Kontrakcja m, Path m (m Response) Response Response) => Route (m Response)
mailAPI = apiCall "mailapi" handleMailCommand

maybeFail :: (Monad m) => String -> Maybe a -> m a
maybeFail msg = maybe (fail msg) return

{-

{ "title": "Title of the document",
  "involved": [
           { "fstname": "Gracjan",
             "sndname": "Polak",
             "personalnumber": "1412341234",
             "email": "gracjan@skrivapa.se"
           }]
}

-}

parseEmailMessageToParts :: BS.ByteString -> (MIME.MIMEValue, [(MIME.Type, BS.ByteString)])
parseEmailMessageToParts content = (mime, parts mime)
  where
    mime = MIME.parseMIMEMessage (BSC.unpack content)
    parts mimevalue = case MIME.mime_val_content mimevalue of
        MIME.Single value -> [(MIME.mime_val_type mimevalue, BSC.pack value)]
        MIME.Multi more -> concatMap parts more

parseEmailMessage :: (Monad m, MonadIO m) => BS.ByteString -> m (Either (BS.ByteString,String) (JSValue,BS.ByteString,BS.ByteString,BS.ByteString))
parseEmailMessage content = 
  let 
  (mime, allParts) = parseEmailMessageToParts content
  isPDF (tp,_) = MIME.mimeType tp == MIME.Application "pdf"
  isPlain (tp,_) = MIME.mimeType tp == MIME.Text "plain"
  typesOfParts = map fst allParts
  pdfs = filter isPDF allParts
  plains = filter isPlain allParts
  from = maybe BS.empty BS.fromString $ lookup "from" (MIME.mime_val_headers mime)
  to   = maybe BS.empty BS.fromString $ lookup "to"   (MIME.mime_val_headers mime)
  isOutlook = maybe False ("Outlook" `isInfixOf`) $ lookup "x-mailer" (MIME.mime_val_headers mime) 
  subject = decodeWords $ BS.toString $ maybe BS.empty BS.fromString $ lookup "subject" (MIME.mime_val_headers mime)
  charset mimetype = maybe "us-ascii" id $ lookup "charset" (MIME.mimeParams mimetype)
  recode mimetype content' =
        case IConv.convertStrictly (charset mimetype) "UTF-8" (BSL.fromChunks [content']) of
          Left result' -> return $ BS.concat (BSL.toChunks (result'))
          Right errmsg -> throwError (show $ IConv.reportConversionError errmsg)
  extendWithFrom (Left l) = Left (from,l)
  extendWithFrom (Right r) = Right r
  in
 liftM extendWithFrom $ runErrorT $ do        
  Log.debug $ "Types of mime parts: " ++ show typesOfParts 
  pdf <- case pdfs of
    [pdf] -> return pdf
    _ -> throwError $ "Exactly one of attachments should be application/pdf, you have " ++ show typesOfParts
  plain <- case plains of
    [plain] -> return plain
    _ -> throwError $ "Exactly one of attachments should be text/plain, you have " ++ show typesOfParts
  let pdfBinary = snd pdf
  recodedPlain' <- recode (fst plain) (snd plain)
  let recodedPlain = (replace "\r\n\r\n" "\r\n" $ BS.toString recodedPlain') <| isOutlook |> BS.toString recodedPlain'
  Log.debug $ "recodedPlain body: " ++ recodedPlain
  json <- (ErrorT . return) $ if '{' == (head $ strip recodedPlain)
                              then runGetJSON readJSObject recodedPlain
                              else parseSimpleEmail subject recodedPlain
  Log.debug $ "Json returned from parsing: " ++ show json
  return (json,pdfBinary,from,to)

-- handleMailCommand :: JSValue -> BS.ByteString -> BS.ByteString -> BS.ByteString -> Kontra (Either String DocumentID)
-- handleMailCommand (JSObject json) content from to = runErrorT $ do
handleMailCommand :: Kontrakcja m => MailAPIFunction m (JSObject JSValue)
handleMailCommand = do
    Log.debug "top of handleMailCommand"
    MailAPIContext { ifrom = from, ito = to, icontent = content } <- ask
    let username = takeWhile (/= '>') $ dropWhile (== '<') $ dropWhile (/= '<') $ BS.toString from
    -- 'extension' is a piece of data that is after + sign in email
    -- addres. example: api+1234@api.skrivapa.se here '1234' is
    -- extension and can be used as for example password
    let extension = takeWhile (/= '@') $ dropWhile (== '+') $ dropWhile (/= '+') $ BS.toString to

    ctxx@Context { ctxtime, ctxipnumber } <- getContext
    user <- runDBQuery (GetUserByEmail Nothing (Email $ BS.fromString username))
      >>= maybeFail ("User '" ++ username ++ "' not found")

    mmailapi <- runDBQuery $ GetUserMailAPI $ userid user
    when (isNothing mmailapi) $
        fail $ "User '" ++ username ++ "' hasn't enabled mail api"
    let Just mailapi = mmailapi

    title <- fromMaybe (BS.fromString "Untitled document received by email") <$> (fromJSONField "title")

    apikey <- fromMaybe extension <$> (fromJSONField "apikey")

    case apikey of
        "" -> fail $ "Need to specify 'apikey' in JSON or after + sign in email address"
        k | (show $ umapiKey mailapi) == k -> return ()
        k -> fail $ "Apikey '" ++ k ++ "' invalid for account '" ++ username ++ "'"

    

    let toStr = BS.toString to
    mdoctype <- fromJSONField "doctype"
    doctype <- case mdoctype of
        Just "contract" -> return (Signable Contract)
        Just "offer" -> return (Signable Offer)
        Just "order" -> return (Signable Order)
        Just z -> fail $ "Unsupported document type '" ++ z ++ "', should be one of ['contract', 'offer', 'order']"
        -- magic below defaults to (Signable Contract), but looks up first True in a list of options
        _ -> return $ fromJust $ lookup True
             [ ("contract" `isInfixOf` toStr, Signable Contract)
             , ("offer" `isInfixOf` toStr,    Signable Offer)
             , ("order" `isInfixOf` toStr,    Signable Order)
             , (True,                         Signable Contract)
             ]

    when (umapiDailyLimit mailapi == umapiSentToday mailapi) $ do
        fail $ "Daily limit of documents for user '" ++ username ++ "' has been reached"
    _ <- runDBUpdate $ SetUserMailAPI (userid user) $ Just mailapi {
        umapiSentToday = umapiSentToday mailapi + 1
    }
    Log.debug "here"
    (involvedTMP) <- fmap (fromMaybe []) $ (fromJSONLocal "involved" $ fromJSONLocalMap $ getSignatoryTMP)
    let (involved :: [SignatoryDetails]) = map toSignatoryDetails involvedTMP

    Log.debug $ show involved
    let signatories = map (\p -> (p,[SignatoryPartner])) involved
    mcompany <- case usercompany user of
                  Just companyid -> runDBQuery $ GetCompany companyid
                  Nothing -> return Nothing
    let userDetails = signatoryDetailsFromUser user mcompany

    (eitherdoc :: Either String Document) <- liftIO $ update $ NewDocument user mcompany title doctype ctxtime
    (doc :: Document) <- case eitherdoc of
                           Left errmsg -> return (error errmsg)
                           Right document -> return document
    (_ :: ()) <- liftKontra $ DocControl.handleDocumentUploadNoLogin (documentid doc) content title
    _errs <- lefts <$> (liftIO $ sequence $ [update $ SetEmailIdentification (documentid doc) ctxtime,
                                            update $ SetDocumentTitle (documentid doc) title ctxtime,
                                            update $ SetDocumentFunctionality (documentid doc) AdvancedFunctionality ctxtime,
                                            update $ ResetSignatoryDetails (documentid doc) ((userDetails, [SignatoryPartner, SignatoryAuthor]):signatories) ctxtime])

    (eithernewdocument :: Either String Document) <- update $ PreparationToPending (documentid doc) ctxtime
    (newdocument :: Document) <- case eithernewdocument of
                                     Left errmsg -> return (error errmsg)
                                     Right document -> return document

    (_ :: ()) <- liftKontra $ DocControl.markDocumentAuthorReadAndSeen newdocument ctxtime ctxipnumber
    (_ :: ()) <- liftKontra $ DocControl.postDocumentChangeAction newdocument doc Nothing
    let docid = documentid doc

    _ <- DocControl.sendMailAPIConfirmEmail ctxx newdocument

    let (rjson :: JSObject JSValue) = toJSObject [ ("status", JSString (toJSString "success"))
                                                 , ("message", JSString (toJSString ("Document #" ++ show docid ++ " created")))
                                                 , ("documentid", JSString (toJSString (show docid)))
                                                 ]
    return rjson


-- Simple Mail API

-- | like lookup, but compares with maxLev 2 instead
--     of ==
levLookup :: String -> [(String, a)] -> Maybe a
levLookup _ []                                    = Nothing
levLookup k1 ((k2, v):_) | maxLev k1 k2 2         = Just v
levLookup k1 (_:ps)                               = levLookup k1 ps
  
data SimpleMailError = NoColon String
                     | UnknownKey String
                     | MissingField String
                     | NoSignatory
                       
instance Show SimpleMailError where
  show (NoColon l) = "Each line must be of the form key:value; this line had no colon " ++ l
  show (UnknownKey k) = "This key was not recognized: " ++ k
  show (MissingField k) = "This required key was missing: " ++ k
  show NoSignatory = "The body of the email was empty; we cannot send a contract with no signatories"

noColonCheck :: String -> Maybe SimpleMailError
noColonCheck l | isNothing $ find (== ':') l = Just $ NoColon l
noColonCheck _ = Nothing

allStrings :: [[String]]
allStrings = [firstNameStrings 
             ,lastNameStrings
             ,emailStrings
             ,companyStrings
             ,orgStrings
             ,persStrings]

firstNameStrings :: [String] 
firstNameStrings = ["first name"]

lastNameStrings :: [String]
lastNameStrings = ["last name"]

emailStrings :: [String]
emailStrings = ["email"]

companyStrings :: [String]
companyStrings = ["company"]

orgStrings :: [String]
orgStrings = [a ++ s ++ b | a <- ["org", "cmp"]
                          , s <- [" ", ""]
                          , b <- ["number", "num", "nr"]]
             ++ [a ++ " number" | a <- ["organization", "company"]]
                                    
             
persStrings :: [String]
persStrings = [a ++ s ++ b | a <- ["personal", "pers"]
                           , s <- [" ", ""]
                           , b <- ["number", "num", "nr"]]

unknownKeyCheck :: String -> Maybe SimpleMailError
unknownKeyCheck l | isJust $ find (== ':') l = 
  let (k, _) = break (== ':') l
  in if none (\a -> maxLev (map toLower k) a 2) (concat allStrings)
     then Just $ UnknownKey k
     else Nothing
unknownKeyCheck _ = Nothing

-- | Takes one line of a simple email and returns the errors                                                    
-- in that line
getParseErrorsLine :: String -> [SimpleMailError]
getParseErrorsLine l = catMaybes $ map ($ l) [unknownKeyCheck
                                             ,noColonCheck
                                             ]
                       
getParseErrorsSig :: [String] -> [SimpleMailError]
getParseErrorsSig ls = concatMap getParseErrorsLine ls ++
                       let pairs = [(strip $ toLower <$> k, strip $ (drop 1) v)| (k, v) <- map (break (== ':')) ls]
                           fstname = levLookup "first name"          pairs
                           sndname = levLookup "last name"           pairs
                           email   = levLookup "email"               pairs
                       in [MissingField s | (s, Nothing) <- [("First name", fstname), 
                                                             ("Last name",  sndname),
                                                             ("Email",      email)]]

splitSignatories :: String -> [[String]]
splitSignatories mailbody =
  let sigstrings' = map strip $ lines $ strip mailbody
      sigstrings  = takeWhile ((== "") ||^ (elem ':')) sigstrings'           
      lss = filter (/= []) $ split [""] sigstrings
  in lss

getParseErrorsEmail :: String -> [SimpleMailError]
getParseErrorsEmail mailbody = 
  if strip mailbody == ""
  then [NoSignatory]
  else concatMap getParseErrorsSig $ splitSignatories mailbody

parseSignatory :: [String] -> Maybe APIRequestBody
parseSignatory sig = 
  let ls = sig
      pairs = [(strip $ toLower <$> k, strip $ (drop 1) v)| (k, v) <- map (break (== ':')) ls]
      fstname = msum $ map (flip levLookup $ pairs) firstNameStrings
      sndname = msum $ map (flip levLookup $ pairs) lastNameStrings
      email   = msum $ map (flip levLookup $ pairs) emailStrings
      company = msum $ map (flip levLookup $ pairs) companyStrings
      cmpnr   = msum $ map (flip levLookup $ pairs) orgStrings
      prsnr   = msum $ map (flip levLookup $ pairs) persStrings
  in
   if all isJust [fstname, sndname, email]
   then let ss = ([("fstname", JSString $ toJSString $ fromJust fstname),
                   ("sndname", JSString $ toJSString $ fromJust sndname),
                   ("email"  , JSString $ toJSString $ fromJust email)] ++ 
                  [("company"   , JSString $ toJSString a) | Just a <- [company]] ++ 
                  [("companynumber" , JSString $ toJSString a) | Just a <- [cmpnr]] ++ 
                  [("personalnumber", JSString $ toJSString a) | Just a <- [prsnr]]) 
        in if length ss == length pairs 
           then Just $ JSObject $ toJSObject ss
           else Nothing
   else Nothing
       
parseSimpleEmail :: String -> String -> Either String APIRequestBody
parseSimpleEmail subject mailbody =  
  case getParseErrorsEmail mailbody of
    [] -> if strip subject == ""
          then Left "The subject of the email becomes the title. The subject you sent was blank. Please add a subject."
          else let sigs = map parseSignatory $ splitSignatories mailbody
               in Right $ JSObject $ toJSObject [("title", JSString $ toJSString $ strip subject),
                                                 ("involved", JSArray (catMaybes sigs))]
    es -> Left $ intercalate "<br />\n" (map show es)
                           
