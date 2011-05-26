{-# OPTIONS_GHC -Wall -fno-warn-orphans #-}
-----------------------------------------------------------------------------
-- |
-- Module      :  Templates.TemplatesLoader
-- Maintainer  :  mariusz@skrivapa.se
-- Stability   :  development
-- Portability :  portable
--
-- This module also provides reading template files, some checking and template info
-- 'KontrakcjaTemplates' is alias for template group, but ma be changed in a future
-----------------------------------------------------------------------------
module Templates.TemplatesLoader
    ( KontrakcjaTemplates
    , KontrakcjaTemplate
    , renderTemplateMain
    , templateList
    , readTemplates
    , getTemplatesModTime
    , toKontrakcjaTemplates
    , templateFiles
    , templateFilePath
    , getTemplates
    ) where

import Text.StringTemplate 
import Text.StringTemplate.Base
import Text.StringTemplate.Classes
import System.IO
import Control.Monad
import Data.Maybe
import Data.List
import Data.Char
import AppLogger as Log
import Text.Html (stringToHtmlString)
import System.Directory
import System.Time
{-Names of template files -}

templatesFilesPath :: [String]
templatesFilesPath = map templateFilePath templateFiles

templateFilePath :: String -> String
templateFilePath fn =  "templates/" ++ fn

templateFiles :: [String]
templateFiles = ["landpages.st",
                 "modals.st",
                 "flash.st",
                 "mails.st",
                 "utils.st",
                 "listutils/listutils.st",
                 "pages.st",
                 "payments.st",
                 "administration.st",
                 "userpages/accountpage.st",
                 "userpages/subaccountslist.st",
                 "userpages/friendpage.st",
                 "userpages/securitypage.st",
                 "userpages/userotherpages.st",                     
                 "docpages/doclist.st",
                 "docpages/doctemplatelist.st",
                 "docpages/docofferslist.st",
                 "docpages/docattachmentlist.st",
                 "docpages/doclistutils.st",
                 "docpages/doctexts.st",
                 "docpages/docviewutils.st",
                 "docpages/docviewforauthor.st",
                 "docpages/docviewforsignatory.st",
                 "docpages/docviewforviewer.st",
                 "docpages/docdesign.st",
                 "docpages/docupload.st",
                 "docpages/doctemplates.st",
                 "docpages/docsignatories.st",
                 "docpages/docseal.st",
                 "docpages/attachmentpage.st",
                 "contacts/contacts.st",
                 "apppages.st",
                 "firstpage.st",
                 "staticpages/sitemap.st",
                 "staticpages/priceplanpage.st",
                 "staticpages/securitypage.st",
                 "staticpages/legalpage.st",
                 "staticpages/privacypolicypage.st",
                 "staticpages/termspage.st",
                 "staticpages/aboutpage.st",
                 "staticpages/partnerspage.st",
                 "staticpages/clientspage.st",
                 "eleg.st",
                 "api/embedded.st",
                 "api/services.st"]


type KontrakcjaTemplates = STGroup String
type KontrakcjaTemplate = StringTemplate String

--This is avaible only for special cases
renderTemplateMain :: (ToSElem a) => KontrakcjaTemplates -> String -> [(String, a)]
                   -> (KontrakcjaTemplate -> KontrakcjaTemplate) -> IO String
renderTemplateMain ts name params f = do 
    let ts' = setEncoderGroup stringToHtmlString ts
    let noescape = groupStringTemplates [("noescape", newSTMP "$it$" :: StringTemplate String)]
    let mt =  getStringTemplate name $ mergeSTGroups noescape ts'
    case mt of 
        Just t -> do
                let t'= f (setManyAttrib params  t)   
                let (e,p,st) = checkTemplateDeep t'
                when (not (null e) || not (null p) || not (null st)) $
                     Log.error $ "Template " ++ name ++ " problem with message " ++ (show (e,p,st)) 
                return $ render t'
        Nothing -> do
                Log.error $ "No template named " ++ name 
                return ""                                   

getTemplatesModTime :: IO ClockTime
getTemplatesModTime = do
    mtimes <- mapM getModificationTime templatesFilesPath
    return (maximum mtimes)

readTemplates :: IO KontrakcjaTemplates 
readTemplates = do
    ts <- mapM getTemplates templatesFilesPath
    return $ groupStringTemplates $ fmap (\(n,v) -> (n,newSTMP v)) (concat ts)

getTemplates :: String -> IO [(String, String)]            
getTemplates fp = 
    withFile fp ReadMode $ \handle -> do
        hSetEncoding handle utf8
        parseTemplates handle


parseTemplates :: Handle -> IO [(String,String)]
parseTemplates handle = do
    e <- hIsEOF handle
    if (e) 
        then return []
        else do
               t  <- parseTemplate handle
               ts <- parseTemplates handle
               return $ (maybeToList t) ++ ts 

parseTemplate :: Handle -> IO (Maybe (String, String))                              
parseTemplate handle = do
    ls <- parseLines handle
    let (name,t) = break (==  '=') $ head ls 
    if (null ls || null (name) || null t)
        then return Nothing   
        else do
            let template = intercalate "\r\n" ((tail t): (tail ls)) 
            return $ Just (filter isAlphaNum name,template)

parseLines :: Handle -> IO [String]                                    
parseLines handle = do
    l <- hGetLine handle
    e <- hIsEOF handle
    if (isPrefixOf ("#") l) 
        then return []
        else if e
            then return [l]
            else fmap ((:) l) (parseLines handle)

{- Template checker, printing info about params-}
templateList :: IO ()
templateList = do 
    ts <- fmap concat $ sequence (map getTemplates templatesFilesPath)         
    let tsnames = map fst ts
    let tsgroup =  groupStringTemplates $ fmap (\(n,v) -> (n,newSTMP v)) ts
    sequence_ $ map (printTemplateData tsgroup) tsnames
                
printTemplateData :: STGroup String -> String -> IO ()
printTemplateData tsgroup name = do 
    let Just t = getStringTemplate name tsgroup
    let (e,p,st) = checkTemplateDeep t
    putStrLn $ name ++ ": " 
    if (not $ null e) 
        then putStrLn $ "PARSE ERROR " ++ (show e)
        else if (not $ null st)  
             then putStrLn $ "MISSING SUBTEMPLATES " ++ (show st)
             else do
                 sequence_ $ map (putStrLn . ("    " ++ )) p
                 putStrLn ""    



{- For some reasons the SElem a is not of class ToSElem -}
instance (Stringable a) => ToSElem (SElem a) where
   toSElem (STR a) = (STR a)    
   toSElem (BS a) = (BS a)    
   toSElem (STSH a) = (STSH a)    
   toSElem (SM a) = (SM $ fmap (toSElem) a)       
   toSElem (LI a) = (LI $ fmap (toSElem) a)       
   toSElem (SBLE a ) = (SBLE $ convert a)       
   toSElem (SNAT a ) = (SNAT $ convert a)       
   toSElem SNull = SNull       


convert :: (Stringable a, Stringable b) => a -> b
convert = stFromString . stToString


toKontrakcjaTemplates::[(String,String)] ->  IO KontrakcjaTemplates
toKontrakcjaTemplates ts = return $ groupStringTemplates $ map (\(n,l) -> (n, newSTMP l)) ts