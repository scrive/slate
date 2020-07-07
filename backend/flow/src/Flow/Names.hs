module Flow.Names
  ( DocumentName
  , UserName
  , MessageName
  , FieldName
  , StageName
  , Name
  , fromName
  , unsafeName
  ) where

import Flow.Names.Internal

unsafeName :: Text -> Name a
unsafeName = Name

fromName :: Name a -> Text
fromName (Name n) = n
