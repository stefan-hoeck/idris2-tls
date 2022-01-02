module Tests.LTLS

import Control.Linear.LIO
import Crypto.Random
import Crypto.Random.C
import Data.Either
import Data.List1
import Data.String
import Data.String.Parser
import Debug.Trace
import Network.Socket
import Network.TLS
import Network.TLS.Certificate
import Network.TLS.Handle
import Network.TLS.Handshake
import Network.TLS.Parse.DER
import Network.TLS.Parse.PEM
import Network.TLS.Verify
import System
import System.File.ReadWrite
import Utils.Bytes
import Utils.Handle
import Utils.Handle.C
import Utils.IPAddr
import Utils.Misc

%hide Network.TLS.Handshake.Message.Certificate

test_http_body : String -> List Bits8
test_http_body hostname = string_to_ascii $ "GET / HTTP/1.1\nHost: " <+> hostname <+> "\n\n"

parse_report_error : List Certificate -> List PEMBlob -> Either String (List Certificate)
parse_report_error acc [] = Right acc
parse_report_error acc (x :: xs) =
  case parse_certificate x.content of
    Right cert => parse_report_error (cert :: acc) xs
    Left err => Left $ "error: " <+> err <+> ", content:\n" <+> encode_pem_blob x

-- Download it from https://wiki.mozilla.org/CA/Included_Certificates
tls_test : String -> String -> Int -> IO ()
tls_test trusted_cert_store target_hostname port = do
  putStrLn "reading cert store"
  Right certs_txt <- readFile trusted_cert_store
  | Left err => putStrLn $ "error while reading: " <+> show err

  let Right (certs_bin, _) = parse (many parse_pem_blob) certs_txt
  | Left err => putStrLn $ "error while parsing pem: " <+> err

  let Right certs = parse_report_error [] certs_bin
  | Left err => putStrLn $ "error while parsing crt: " <+> err
  putStrLn "done"

  Right sock <- socket AF_INET Stream 0
  | Left err => putStrLn $ "unable to create socket: " <+> show err
  0 <- connect sock (Hostname target_hostname) port
  | _ => putStrLn "unable to connect"
  run $ do
    let handle = socket_to_handle sock
    -- perform handshake
    (True # handle) <- tls_handshake target_hostname handle (certificate_check certs target_hostname)
    | (False # (error # ())) => putStrLn error

    -- write data
    (True # handle) <- write handle $ test_http_body target_hostname
    | (False # (error # ())) => putStrLn error

    -- read data
    (True # (output # handle)) <- read handle 100
    | (False # (error # ())) => putStrLn error

    putStrLn "response"
    putStrLn $ ascii_to_string output

    -- read data
    (True # (output # handle)) <- read handle 100
    | (False # (error # ())) => putStrLn error

    putStrLn "response"
    putStrLn $ ascii_to_string output

    -- close handle
    close handle
    putStrLn "ok"
