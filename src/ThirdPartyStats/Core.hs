-- | Backend API for logging events to be sent off to a third party.
module ThirdPartyStats.Core (
    EventProperty (..),
    PropValue (..),
    ProcRes (..),
    NumEvents (..),
    EventName (..),
    AsyncEvent,
    someProp,
    numProp,
    stringProp,
    asyncLogEvent,
    asyncProcessEvents
  ) where
import qualified Data.ByteString.Lazy as BL
import qualified Data.ByteString as B
import Data.Binary
import Data.String
import Control.Monad.IO.Class
import Control.Applicative
import qualified DB (Binary (..))
import DB hiding (Binary)
import DB.SQL2
import ThirdPartyStats.Tables
import qualified Log
import MinutesTime
import User.UserID (UserID, unsafeUserID)
import Doc.DocumentID (DocumentID, unsafeDocumentID)
import IPAddress
import User.Model (Email (..))

import Test.QuickCheck (Arbitrary (..), frequency, oneof, suchThat)


-- | The various types of values a property can take.
data PropValue
  = PVNumber      Double
  | PVString      String
  | PVBool        Bool
  | PVMinutesTime MinutesTime
    deriving (Show, Eq)

instance Binary PropValue where
  put (PVNumber d)      = putWord8 0 >> put d
  put (PVString s)      = putWord8 1 >> put s
  put (PVBool b)        = putWord8 2 >> put b
  put (PVMinutesTime t) = putWord8 3 >> put t
  
  get = do
    tag <- getWord8
    case tag of
      0 -> PVNumber      <$> get
      1 -> PVString      <$> get
      2 -> PVBool        <$> get
      3 -> PVMinutesTime <$> get
      n -> fail $ "Couldn't parse PropValue constructor tag: " ++ show n


-- | Type class to keep the user from having to wrap stuff in annoying data
--   constructors.
class SomeProperty a where
  someProp :: PropName -> a -> EventProperty

instance SomeProperty String where
  someProp s = SomeProp s . PVString

instance SomeProperty Double where
  someProp s = SomeProp s . PVNumber

instance SomeProperty Bool where
  someProp s = SomeProp s . PVBool

instance SomeProperty MinutesTime where
  someProp s = SomeProp s . PVMinutesTime


-- | Create a named property with a Double value.
--   This function just fixes the property type of someProp to avoid
--   unnecessary type annotations due to numeric literals being overloaded.
numProp :: PropName -> Double -> EventProperty
numProp = someProp

-- | Create a named property with a String value.
--   This function just fixes the property type of someProp to avoid
--   unnecessary type annotations in the presence of overloaded strings.
stringProp :: PropName -> String -> EventProperty
stringProp = someProp


-- | Makes type signatures on functions involving event names look nicer.
data EventName = SetUserProps | NamedEvent String deriving (Show, Eq)
type PropName = String

instance IsString EventName where
  fromString = NamedEvent

instance Binary EventName where
  put (SetUserProps)    = putWord8 0
  put (NamedEvent name) = putWord8 255 >> put name
  
  get = do
    tag <- getWord8
    case tag of
      0   -> return SetUserProps
      255 -> NamedEvent <$> get
      t   -> fail $ "Unable to parse EventName constructor tag: " ++ show t


-- | Represents a property on an event.
data EventProperty
  = MailProp   Email
  | IPProp     IPAddress
  | NameProp   String
  | UserIDProp UserID
  | TimeProp   MinutesTime
  | DocIDProp  DocumentID
  | SomeProp   PropName PropValue
    deriving (Show, Eq)


-- | The scheme here is to have generic properties at ID 255 and give any
--   special properties IDs starting at 0. Obviously.
instance Binary EventProperty where
  put (MailProp mail)     = putWord8 0   >> put (unEmail mail)
  put (IPProp ip)         = putWord8 1   >> put ip
  put (NameProp name)     = putWord8 2   >> put name
  put (UserIDProp uid)    = putWord8 3   >> put uid
  put (TimeProp t)        = putWord8 4   >> put t
  put (DocIDProp did)     = putWord8 5   >> put did
  put (SomeProp name val) = putWord8 255 >> put name >> put val
  
  get = do
    tag <- getWord8
    case tag of
      0   -> MailProp . Email <$> get
      1   -> IPProp           <$> get
      2   -> NameProp         <$> get
      3   -> UserIDProp       <$> get
      4   -> TimeProp         <$> get
      5   -> DocIDProp        <$> get
      255 -> SomeProp         <$> get <*> get
      n   -> fail $ "Couldn't parse EventProperty constructor tag: " ++ show n


-- | Data type representing an asynchronous event.
data AsyncEvent = AsyncEvent EventName [EventProperty] deriving (Show, Eq)

instance Binary AsyncEvent where
  put (AsyncEvent name props) = put name >> put props
  get = AsyncEvent <$> get <*> get


-- | Denotes how many events should be processed.
data NumEvents = All | NoMoreThan Integer


-- | Indicates how the processing of an event fared.
data ProcRes
  = OK            -- ^ Processing succeeded, we're done with this event.
  | PutBack       -- ^ Processing failed, but may succeed if retried later.
  | Failed String -- ^ Processing failed permanently, discard event and
                  --   log the failure.


-- | Remove a number of events from the queue and process them.
asyncProcessEvents :: (MonadIO m, MonadDB m)
                   => (EventName -> [EventProperty] -> m ProcRes)
                      -- ^ Event processing function.
                   -> NumEvents
                      -- ^ Max events to process.
                   -> m ()
asyncProcessEvents process numEvts = do
    (evts, lastEvt) <- fetchEvents
    mapM_ processEvent evts
    deleteEvents lastEvt
  where
    processEvent (AsyncEvent name props) = do
        result <- process name props
        case result of
          PutBack ->
            asyncLogEvent name props
          Failed msg ->
            Log.error $ "Event processing failure; event name = " ++ (show name) ++ " reason = " ++ msg
          _  | otherwise ->
            return ()

    decoder (evts, max_seq) seqnum evt =
        (decode (BL.fromChunks [DB.unBinary evt]) : evts, max seqnum max_seq)

    -- Delete all events with a sequence number less than or equal to lastEvt.
    deleteEvents lastEvt = do
        runDBEnv $ do
          _ <- kRun $ sqlDelete (tblName tableAsyncEventQueue) $ do
                      sqlWhere $ SQL "sequence_number <= ?" [toSql lastEvt]
          return ()

    -- Fetch events from database and turn them into a pair of
    -- (events, highest sequence number in fetched list).
    fetchEvents = do
        runDBEnv $ do
            _ <- kRun_ $ sqlSelect (tblName tableAsyncEventQueue) $ do
                sqlResult "sequence_number"
                sqlResult "event"
                sqlOrderBy "sequence_number ASC"
                case numEvts of
                  NoMoreThan n -> sqlLimit n
                  _            -> return ()
            foldDB decoder ([], 0 :: Integer)


-- | Send a message off to the async queue for later processing.
--   The event must have a name and zero or more named properties, some of
--   which, such as email address or signup time, may be "special", in the
--   sence that third party services may be able to do interesting things to
--   them since they have more contextual knowledge about them.
--   
--   "Special" properties should be identified using the proper `EventProperty`
--   constructor, whereas others may be arbitrarily named using `someProp`.
asyncLogEvent :: (MonadDB m) => EventName -> [EventProperty] -> m ()
asyncLogEvent name props = do
    _ <- runDBEnv $ kRun $ mkSQL INSERT tableAsyncEventQueue serializedEvent
    return ()
  where
    serializedEvent = [sql "event" . mkBinary $ AsyncEvent name props]
    mkBinary = DB.Binary . B.concat . BL.toChunks . encode




-- Arbitrary instances for testing

instance Arbitrary EventName where
  arbitrary = frequency [
      (1, return SetUserProps),
      (9, NamedEvent <$> arbitrary)]

instance Arbitrary PropValue where
  arbitrary = oneof [
      PVNumber <$> arbitrary,
      PVString <$> arbitrary,
      PVBool <$> arbitrary,
      PVMinutesTime . fromSeconds <$> arbitrary]

-- Note that IP addresses are completely arbitrary 32 bit words here!
instance Arbitrary EventProperty where
  arbitrary = frequency [
      (1, MailProp <$> email),
      (1, IPProp . unsafeIPAddress <$> arbitrary),
      (1, NameProp <$> arbitrary),
      (1, UserIDProp . unsafeUserID <$> arbitrary),
      (1, TimeProp . fromSeconds <$> arbitrary),
      (1, DocIDProp . unsafeDocumentID <$> arbitrary),
      (5, SomeProp <$> arbitrary <*> arbitrary)]
    where
      email = do
        acct <- arbitrary `suchThat` ((> 5) . length)
        domain <- arbitrary `suchThat` ((> 5) . length)
        toplevel <- oneof (map return ["com", "net", "org", "nu", "se"])
        return $! Email $! concat [acct, "@", domain, ".", toplevel]

instance Arbitrary AsyncEvent where
  arbitrary = AsyncEvent <$> arbitrary <*> arbitrary
