{-# LANGUAGE OverloadedStrings #-}
-- Copyright © 2015 Bart Massey
-- [This program is licensed under the GPL version 3 or later.]
-- Please see the file COPYING in the source
-- distribution of this software for license terms.

-- TauNet echo server

import Control.Monad
import Data.CipherSaber2
import qualified Data.ByteString as BS
import qualified Data.ByteString.Char8 as BSC
import Data.List
import Network.Socket hiding (send, sendTo, recv, recvFrom)
import Network.Socket.ByteString
import System.Exit
import System.IO
import System.Posix.Process

(+++) :: BSC.ByteString -> BSC.ByteString -> BSC.ByteString
(+++) = BSC.append

debug :: Bool
debug = True

versionNumber :: String
versionNumber = "0.2"

taunetPort :: PortNumber
taunetPort = 6283

maxMessageSize :: Int
maxMessageSize = 1024 * 1024

scheduleReps :: Int
scheduleReps = 20

makeIV :: IO BS.ByteString
makeIV = 
  withBinaryFile "/dev/urandom" ReadMode $ \h ->
  do
    hSetBuffering h NoBuffering
    BS.hGet h 10

readKey :: IO BS.ByteString
readKey = do
  key <- readFile "key.txt"
  return $ BSC.pack $ head $ lines key

linesCRLF :: String -> [String]
linesCRLF [] = []
linesCRLF ('\r' : '\n' : cs) =
    [] : linesCRLF cs
linesCRLF (c : cs) =
    case linesCRLF cs of
      [] -> [[c]]   -- String did not end in CRLF
      (l : ls) -> (c : l) : ls

data Message = Message { messageTo, messageFrom :: String,
                         messageBody :: BS.ByteString }

data Failure = Failure { failureMessage :: String,
                         failureBody :: BS.ByteString }

failUnless :: Bool -> Failure -> Either Failure ()
failUnless True _ = Right ()
failUnless False f = Left f

receiveMessage :: Bool -> BS.ByteString -> Socket
               -> IO (Either Failure Message)
receiveMessage doCrypt key s = do
  messagetext <- recv s maxMessageSize
  close s
  let plaintext =
          case doCrypt of
            True -> decrypt scheduleReps key messagetext
            False -> messagetext
  let headers = take 4 $ linesCRLF $ BSC.unpack plaintext
  return $ do
    let failure msg = Failure msg plaintext
    let removeHeader header target
            | isPrefixOf paddedHeader target =
                Right $ drop (length paddedHeader) target
            | otherwise =
                Left $ Failure ("bad header " ++ header) plaintext
            where
              paddedHeader = header ++ ": "
    failUnless (length headers == 4) $
               failure "mangled headers"
    failUnless (headers !! 0 == ("version " ++ versionNumber)) $
               failure "bad version header"
    failUnless (headers !! 3 == "") $
               failure "bad end-of-headers"
    toHeader <- removeHeader "to" (headers !! 1)
    fromHeader <- removeHeader "from" (headers !! 2)
    return $ Message toHeader fromHeader plaintext

sendMessage :: Bool -> BS.ByteString -> SockAddr -> Message -> IO ()
sendMessage doCrypt key sendAddr message = do
  let plaintext =
        ("version 0.2\r\n" +++
        "to: " +++ toPerson +++ "\r\n" +++
        "from: " +++ fromPerson +++ "\r\n\r\n" +++
        messageBody message) :: BSC.ByteString
        where
          toPerson = BSC.pack $ messageFrom message
          fromPerson = BSC.pack $ messageTo message
  messagetext <-
      case doCrypt of
        True -> do
          iv <- makeIV
          return $ encrypt scheduleReps key iv plaintext
        False ->
          return plaintext
  sendSocket <- socket AF_INET Stream defaultProtocol
  connect sendSocket sendAddr
  _ <- send sendSocket messagetext
  close sendSocket
  return ()

fixAddr :: SockAddr -> SockAddr
fixAddr (SockAddrInet _ address) = SockAddrInet taunetPort address
fixAddr _ = error "address type not supported"

main :: IO ()
main = do
  key <- readKey
  taunetSocket <- socket AF_INET Stream defaultProtocol
  bind taunetSocket $ SockAddrInet taunetPort 0
  listen taunetSocket 1
  forever $ do
    (recvSocket, recvAddr) <- accept taunetSocket
    maybeFork debug $ do
      let sendAddr = fixAddr recvAddr
      received <- receiveMessage debug key recvSocket
      let sendIt = sendMessage debug key sendAddr
      case received of
        Right message -> sendIt message
        Left failure -> sendIt failMessage
                   where
                     failMessage = Message {
                       messageTo = "???",
                       messageFrom = "po8",
                       messageBody =
                           BSC.pack (failureMessage failure) +++
                           "\r\n" +++ failureBody failure }
      exitSuccess
    return ()
    where
      maybeFork True a = do _ <- forkProcess a; return ()
      maybeFork False a = a
