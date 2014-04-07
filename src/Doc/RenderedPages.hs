module Doc.RenderedPages
  ( RenderedPages(..)
  , RenderedPagesCache
  , pagesCount
  , legacyWidthInPixels
  ) where

import qualified MemCache
import qualified Data.ByteString as BS
import File.FileID

data RenderedPages
  = RenderedPages Bool  -- ^ Rendering is finished
                  [BS.ByteString] -- ^ Pages rendered so far. Format is PNG.
    deriving (Eq, Ord, Show)

pagesCount :: RenderedPages -> Int
pagesCount (RenderedPages _ ps) = length ps

-- | This is a memcache indexed by tripples: FileID of file that was rendered,
-- page width in pixels that was requested and indication if whole document
-- was requested to be rendered (True) or just the first page (False)
type RenderedPagesCache = MemCache.MemCache (FileID,Int,Bool) RenderedPages

legacyWidthInPixels :: Int
legacyWidthInPixels = 943
