{-# OPTIONS_GHC -fno-warn-orphans #-}
module Templates ( getAllTemplates
                 , readGlobalTemplates
                 , localizedVersion
                 , KontrakcjaGlobalTemplates
                 , KontrakcjaTemplates
                 , getTemplatesModTime
                 , renderLocalTemplate
                 , runTemplatesT
                 , templateName
                 ) where

import Data.List (isSuffixOf)

import Control.Monad.Trans
import Control.Monad.Reader
import Data.Time.Clock

import User.Lang
import Crypto.RNG

import qualified Text.StringTemplates.Files as TF
import qualified Text.StringTemplates.TemplatesLoader as TL
import qualified Text.StringTemplates.Templates as T
import qualified Text.StringTemplates.Fields as F
import Text.StringTemplates.Utils (directoryFilesRecursive)

templateFilesDir :: FilePath
templateFilesDir = "templates"

textsDirectory :: FilePath
textsDirectory = "texts"

getAllTemplates :: IO [(String, String)]
getAllTemplates = do
  files <- directoryFilesRecursive templateFilesDir
  let templatesFiles = filter (".st" `isSuffixOf`) files
  concat `fmap` mapM TF.getTemplates templatesFiles

type KontrakcjaGlobalTemplates = TL.GlobalTemplates
type KontrakcjaTemplates = TL.Templates

readGlobalTemplates :: MonadIO m => m KontrakcjaGlobalTemplates
readGlobalTemplates = TL.readGlobalTemplates textsDirectory templateFilesDir (codeFromLang LANG_EN)


localizedVersion :: Lang -> KontrakcjaGlobalTemplates -> KontrakcjaTemplates
localizedVersion lang = TL.localizedVersion $ codeFromLang lang

getTemplatesModTime :: IO UTCTime
getTemplatesModTime = TL.getTemplatesModTime textsDirectory templateFilesDir

renderLocalTemplate :: (HasLang a, T.TemplatesMonad m) => a -> String -> F.Fields m () -> m String
renderLocalTemplate haslang name fields = do
  ts <- T.getTextTemplatesByLanguage $ codeFromLang $ getLang haslang
  T.renderHelper ts name fields

instance CryptoRNG m => CryptoRNG (T.TemplatesT m) where
    getCryptoRNGState = T.TemplatesT $ ReaderT $ \_r -> getCryptoRNGState

runTemplatesT :: (Functor m, Monad m) => (Lang, TL.GlobalTemplates) -> T.TemplatesT m a -> m a
runTemplatesT (lang, ts) action = runReaderT (T.unTT action) (codeFromLang lang, ts)

-- | use 'templateName' to flag that a string literal is a template name (for detect_old_templates)
templateName :: String -> String
templateName = id