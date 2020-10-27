module Sensei.App where

import Network.Wai.Application.Static
import Network.Wai.Handler.Warp
import Sensei.API
import Sensei.Server
import Servant
import System.Directory
import System.FilePath
import System.Posix.Daemonize

sensei :: FilePath -> IO ()
sensei output =
  run
    23456
    ( serve senseiAPI $
        traceS output
          :<|> ( flowS output
                   :<|> queryFlowDaySummaryS output
                   :<|> notesDayS output
                   :<|> queryFlowDayS output
                   :<|> queryFlowS output
               )
          :<|> Tagged staticResources
    )

-- | Serve static resources under `public/` directory
staticResources :: Application
staticResources = staticApp (defaultFileServerSettings "ui")

senseiLog :: IO FilePath
senseiLog = (</> ".sensei.log") <$> getHomeDirectory

daemonizeServer :: IO ()
daemonizeServer =
  daemonize $
  -- TODO fix this silly hardcoded path
  -- this is so because I want to ensure the server is started in a location
  -- where it can find the FE resources...
  withCurrentDirectory "/Users/arnaud/projects/pankzsoft/sensei/" $ startServer

startServer :: IO ()
startServer = senseiLog >>= sensei
