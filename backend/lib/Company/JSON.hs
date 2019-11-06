module Company.JSON
  ( unjsonUserGroupUI
  , unjsonUserGroupUIWithCompanyID
  ) where

import Data.Functor.Invariant
import Data.Unjson
import qualified Control.Applicative.Free as AltF
import qualified Data.ByteString as BS
import qualified Data.ByteString.Base64 as B64
import qualified Data.ByteString.Char8 as BSC8

import UserGroup.Types

unjsonUserGroupUI :: UnjsonDef UserGroupUI
unjsonUserGroupUI = objectOf $ unjsonUserGroupUIFields

-- Dedicated version of unjsonUserGroupUI that adds companyid field for
-- backward compatibility
unjsonUserGroupUIWithCompanyID :: UserGroupID -> UnjsonDef UserGroupUI
unjsonUserGroupUIWithCompanyID uid =
  objectOf
    $  unjsonUserGroupUIFields
    <* (fieldReadonly "companyid" (const uid) "Company id")

unjsonUserGroupUIFields :: AltF.Ap (FieldDef UserGroupUI) UserGroupUI
unjsonUserGroupUIFields =
  pure defaultUserGroupUI
    <**> (    fieldOpt "mailTheme" (^. #mailTheme) "Id of a mail theme"
         <**> (pure $ set #mailTheme)
         )
    <**> (    fieldOpt "signviewTheme" (^. #signviewTheme) "Id of a signview theme"
         <**> (pure $ set #signviewTheme)
         )
    <**> (    fieldOpt "serviceTheme" (^. #serviceTheme) "Id of a service theme"
         <**> (pure $ set #serviceTheme)
         )
    <**> (    fieldOpt "browserTitle" (^. #browserTitle) "Browser title"
         <**> (pure $ set #browserTitle)
         )
    <**> (    fieldOpt "smsOriginator" (^. #smsOriginator) "SMS Originator"
         <**> (pure $ set #smsOriginator)
         )
    <**> (    fieldOptBy
             "favicon"
             (^. #favicon)
             "Favicon"
             (invmap
               (\l -> B64.decodeLenient $ BSC8.pack $ drop 1 $ dropWhile ((/=) ',') $ l)
               (\l ->
                 BSC8.unpack $ BS.append (BSC8.pack "data:image/png;base64,") $ B64.encode
                   l
               )
               unjsonDef
             )
         <**> (pure $ set #favicon)
         )
