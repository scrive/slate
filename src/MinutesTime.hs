
module MinutesTime where

import System.Time hiding (toClockTime,toUTCTime)
import qualified System.Time as System.Time (toClockTime,toUTCTime)
import Happstack.Data
import Data.Data
import System.Locale
import System.IO.Unsafe
import System.Locale
import Data.Time

$(deriveAll [''Eq, ''Ord, ''Default, ''Read]
  [d|

   -- | Time in minutes from 1970-01-01 00:00 in UTC coordinates
   newtype MinutesTime = MinutesTime Int

 |])

instance Show MinutesTime where
    showsPrec prec (MinutesTime mins) = 
        let clocktime = TOD (fromIntegral mins*60) 0
            -- FIXME: use TimeZone of user
            calendartime = unsafePerformIO $ toCalendarTime clocktime
        in (++) $ formatCalendarTime defaultTimeLocale 
               "%Y-%m-%d, %H:%M" calendartime
               
showDateOnly (MinutesTime 0) = ""
showDateOnly (MinutesTime mins) = 
        let clocktime = TOD (fromIntegral mins*60) 0
            -- FIXME: use TimeZone of user
            calendartime = unsafePerformIO $ toCalendarTime clocktime
        in formatCalendarTime defaultTimeLocale 
               "%Y-%m-%d" calendartime

swedishTimeLocale = defaultTimeLocale { months = 
                                            [ ("jan","jan")
                                            , ("feb", "feb")
                                            , ("mar", "mar")
                                            , ("apr", "apr")
                                            , ("mai", "mai")
                                            , ("jun", "jun")
                                            , ("jul", "jul")
                                            , ("aug", "aug")
                                            , ("sep", "sep")
                                            , ("okt", "okt")
                                            , ("nov", "nov")
                                            , ("dec", "dec")
                                            ] }

showDateAbbrev (MinutesTime current) (MinutesTime mins) 
               | ctYear ct1 == ctYear ct && ctMonth ct1 == ctMonth ct && ctDay ct1 == ctDay ct =
                   formatCalendarTime swedishTimeLocale "%H:%M" ct
               | ctYear ct1 == ctYear ct =
                   formatCalendarTime swedishTimeLocale "%d %b" ct
               | otherwise =
                   formatCalendarTime swedishTimeLocale "%Y-%m-%d" ct
               where
                 ct1 = unsafePerformIO $ toCalendarTime $ TOD (fromIntegral current*60) 0
                 ct = unsafePerformIO $ toCalendarTime $ TOD (fromIntegral mins*60) 0

instance Version MinutesTime
$(deriveSerialize ''MinutesTime)

getMinutesTime = (return . fromClockTime) =<< getClockTime

fromClockTime (TOD secs picos) =  MinutesTime (fromIntegral $ (secs `div` 60))
toClockTime (MinutesTime time) = (TOD (fromIntegral time * 60) 0)   

toUTCTime = System.Time.toUTCTime . toClockTime

parseMinutesTimeMDY::String -> Maybe MinutesTime
parseMinutesTimeMDY s = do
                      t <- parseTime defaultTimeLocale "%d-%m-%Y" s
                      startOfTime <- parseTime defaultTimeLocale "%d-%m-%Y" "01-01-1970" 
                      let val = diffDays t startOfTime  
                      return (MinutesTime (fromIntegral $ (val *24*60)))

showDateMDY (MinutesTime mins) =  let clocktime = TOD (fromIntegral mins*60) 0
                                      calendartime = unsafePerformIO $ toCalendarTime clocktime
                                  in formatCalendarTime defaultTimeLocale "%d-%m-%y" calendartime  
                
minutesAfter::Int -> MinutesTime -> MinutesTime 
minutesAfter i (MinutesTime i') = MinutesTime $ i + i'

startOfMonth::MinutesTime->MinutesTime
startOfMonth t = let 
                   CalendarTime {ctDay,ctHour,ctMin,ctSec,ctPicosec} = toUTCTime t
                   diff = (noTimeDiff {tdDay= (-1)*ctDay+1,tdHour=(-1)*ctHour,tdMin=(-1)*ctMin,tdSec=(-1)*ctSec,tdPicosec=(-1)*ctPicosec})
                 in fromClockTime $ addToClockTime diff  (toClockTime t)
                   
addMonths::Int ->MinutesTime -> MinutesTime
addMonths i t = fromClockTime $ addToClockTime (noTimeDiff {tdMonth = i})  (toClockTime t)

dateDiffInDays::MinutesTime->MinutesTime -> Int
dateDiffInDays (MinutesTime ctime) (MinutesTime mtime)
                       | ctime>mtime = 0
                       | otherwise = (mtime - ctime) `div` (60*24)