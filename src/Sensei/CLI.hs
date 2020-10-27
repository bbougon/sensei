{-# LANGUAGE ScopedTypeVariables #-}

module Sensei.CLI where

import qualified Control.Exception.Safe as Exc
import Data.Aeson hiding (Options)
import qualified Data.ByteString.Lazy as LBS
import Data.Text(Text)
import qualified Data.Text as Text
import Data.Text.Encoding (decodeUtf8)
import qualified Data.Text.IO as Text
import Data.Time
import Data.Time.Format.ISO8601
import Options.Applicative
import Sensei.API
import Sensei.Client
import System.Console.ANSI
import System.IO

data Options
  = QueryOptions {queryDay :: Maybe Day, summarize :: Bool}
  | RecordOptions {recordType :: FlowType}
  | NotesOptions {notesDay :: Day}

optionsParserInfo :: ParserInfo Options
optionsParserInfo =
  info
    (optionsParser <**> helper)
    (progDesc "Epoché - Record start time of some flow type for current user")

optionsParser :: Parser Options
optionsParser =
  QueryOptions <$> optional dayParser <*> summarizeParser
    <|> RecordOptions <$> flowTypeParser
    <|> NotesOptions <$> dayParser <* notesParser

dayParser :: Parser Day
dayParser =
  option
    (maybeReader iso8601ParseM)
    ( long "date"
        <> short 'd'
        <> metavar "DATE"
        <> help "date to filter on, in ISO8601 format (YYYY-mm-dd)"
    )

summarizeParser :: Parser Bool
summarizeParser =
  flag
    False
    True
    ( long "summary"
        <> short 's'
        <> help "summarize by flow type"
    )

notesParser :: Parser ()
notesParser =
  flag
    ()
    ()
    ( long "notes"
        <> short 'N'
        <> help "Display only notes for a given day"
    )

flowTypeParser :: Parser FlowType
flowTypeParser =
  flag' Experimenting (short 'e' <> help "Experimenting period")
    <|> flag' Learning (short 'l' <> help "Learning period")
    <|> flag' Troubleshooting (short 't' <> help "Troubleshooting period")
    <|> flag' Flowing (short 'f' <> help "Flowing period")
    <|> flag' Rework (short 'r' <> help "Rework period")
    <|> flag' Other (short 'o' <> help "Other period")
    <|> flag' End (short 'E' <> help "End previous period")
    <|> flag' Note (short 'n' <> help "Taking some note")

parseSenseiOptions :: IO Options
parseSenseiOptions = execParser optionsParserInfo

display :: ToJSON a => a -> IO ()
display = Text.putStrLn . decodeUtf8 . LBS.toStrict . encode

flowAction :: Options -> String -> UTCTime -> FilePath -> IO ()
flowAction (QueryOptions Nothing _) userName _ _ =
  send (queryFlowC userName) >>= display
flowAction (QueryOptions (Just day) False) userName _ _ =
  send (queryFlowDayC userName day) >>= display
flowAction (QueryOptions (Just day) True) userName _ _ =
  send (queryFlowDaySummaryC userName day) >>= display
flowAction (NotesOptions day) userName _ _ =
  send (notesDayC userName day) >>= mapM_ Text.putStrLn . formatNotes
flowAction (RecordOptions ftype) curUser startDate curDir =
  case ftype of
    Note -> do
      txt <- captureNote
      send $ flowC Note (FlowNote curUser startDate curDir txt)
    other ->
      send $ flowC other (FlowState curUser startDate curDir)

formatNotes  :: [(UTCTime, Text)] -> [Text]
formatNotes = concatMap timestamped

timestamped :: (UTCTime, Text) -> [Text]
timestamped (st, note) =
  Text.pack (formatTime defaultTimeLocale "%H:%M" st) : Text.lines note

captureNote :: IO Text.Text
captureNote = do
  setSGR
    [ SetConsoleIntensity NormalIntensity,
      SetColor Foreground Vivid White,
      SetColor Background Dull Blue
    ]
  putStr "Record a note, type Ctrl+D at beginning of line when done"
  setSGR [Reset]
  putStrLn ""
  capture []
  where
    capture :: [Text.Text] -> IO Text.Text
    capture acc = do
      eof <- isEOF
      if eof
        then pure $ Text.unlines (reverse acc)
        else do
          res <- Exc.try $ hGetLine stdin
          case res of
            Left (_ex :: Exc.IOException) -> pure $ Text.unlines (reverse acc)
            Right txt -> capture (Text.pack txt : acc)
