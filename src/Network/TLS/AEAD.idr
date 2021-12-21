module Network.TLS.AEAD

import Data.Stream
import Data.Bits
import Data.Vect
import Data.List
import Utils.Misc
import Utils.Bytes
import Crypto.AES
import Crypto.GF128
import Crypto.ChaCha

public export
interface AEAD (0 a : Type) where
  ||| IV generated during key exchange
  iv_bytes : Nat
  key_bytes : Nat
  mac_bytes : Nat
  mac_key_bytes : Nat
  ||| Part of IV that is sent along with the ciphertext, should always be 0 in TLS 1.3
  explicit_iv_bytes : Nat

  encrypt : Vect key_bytes Bits8 -> Vect iv_bytes Bits8 -> Vect mac_key_bytes Bits8 -> Nat ->
            (plaintext : List Bits8) -> (aad : List Bits8) -> (Vect explicit_iv_bytes Bits8, List Bits8, Vect mac_bytes Bits8)
  decrypt : Vect key_bytes Bits8 -> Vect iv_bytes Bits8 -> Vect explicit_iv_bytes Bits8 -> Vect mac_key_bytes Bits8 -> Nat ->
            (ciphertext : List Bits8) -> (plaintext_to_aad : List Bits8 -> List Bits8) -> (mac_tag : List Bits8) -> (List Bits8, Bool)

aes_pad_iv_block : {iv : Nat} -> Vect iv Bits8 -> Stream (Vect (iv+4) Bits8)
aes_pad_iv_block iv = map ((iv ++) . to_be . (cast {to=Bits32})) $ drop 2 nats

pad : Nat -> List Bits8 -> List Bits8
pad Z a = a
pad (S n) a =
  let l = length a
      l = minus ((S n) * (divCeilNZ l (S n) SIsNonZero)) l
  in a <+> replicate l 0

toF128 : List Bits8 -> F128
toF128 elem =
  case exactLength 16 $ fromList $ take 16 elem of
    Just v => MkF128 v
    Nothing => toF128 (pad 16 elem)

aes_keystream : (mode : AES.Mode) -> Vect ((get_n_k mode) * 4) Bits8 -> Vect 12 Bits8 -> Stream Bits8
aes_keystream mode key iv =
  let key' = group _ _ key
  in stream_concat $ map (toList . Vect.concat . encrypt_block mode key' . group _ _) (aes_pad_iv_block iv)

aes_gcm_create_aad : (mode : AES.Mode) -> Vect ((get_n_k mode) * 4) Bits8 -> Vect 12 Bits8 -> List Bits8 -> List Bits8 -> Vect 16 Bits8
aes_gcm_create_aad mode key iv aad ciphertext =
  let key' = group _ _ key
      a = toList $ to_be {n=8} $ cast {to=Bits64} $ 8 * (length aad)
      c = toList $ to_be {n=8} $ cast {to=Bits64} $ 8 * (length ciphertext)
      input = chunk 16 (pad 16 aad <+> pad 16 ciphertext <+> a <+> c)
      h = mk_h_values
        $ MkF128
        $ concat
        $ encrypt_block mode key'
        $ group 4 4 
        $ map (const 0)
        $ Fin.range
      MkF128 output = foldl (\e,a => gcm_mult h $ xor a e) zero $ map toF128 input
      j0 = concat $ encrypt_block mode key' $ group 4 4 (iv ++ (to_be $ the Bits32 1))
  in zipWith xor j0 output

public export
data TLS13_AES_128_GCM : Type where

public export
AEAD TLS13_AES_128_GCM where
  iv_bytes = 12
  key_bytes = 16
  mac_bytes = 16
  mac_key_bytes = 0
  explicit_iv_bytes = 0

  encrypt key iv mac_key seq_no plaintext aad =
    let iv' = zipWith xor iv $ integer_to_be _ $ natToInteger seq_no
        ciphertext = zipWith xor plaintext (toList $ Stream.take (length plaintext) $ aes_keystream AES128 key iv')
        mac_tag = aes_gcm_create_aad AES128 key iv' aad ciphertext
    in ([], ciphertext, mac_tag)

  decrypt key iv [] mac_key seq_no ciphertext aadf mac_tag' =
    let iv' = zipWith xor iv $ integer_to_be _ $ natToInteger seq_no
        plaintext = zipWith xor ciphertext (toList $ Stream.take (length ciphertext) $ aes_keystream AES128 key iv')
        mac_tag = aes_gcm_create_aad AES128 key iv' (aadf plaintext) ciphertext
    in (plaintext, s_eq' (toList mac_tag) mac_tag')

public export
data TLS12_AES_128_GCM : Type where

public export
AEAD TLS12_AES_128_GCM where
  iv_bytes = 4
  key_bytes = 16
  mac_bytes = 16
  mac_key_bytes = 0
  explicit_iv_bytes = 8

  encrypt key iv mac_key seq_no plaintext aad =
    let explicit_iv = to_be {n=8} $ cast {to=Bits64} seq_no
        iv' = iv ++ explicit_iv
        ciphertext = zipWith xor plaintext (toList $ Stream.take (length plaintext) $ aes_keystream AES128 key iv')
        mac_tag = aes_gcm_create_aad AES128 key iv' aad ciphertext
    in (explicit_iv, ciphertext, mac_tag)

  decrypt key iv explicit_iv mac_key seq_no ciphertext aadf mac_tag' =
    let iv' = iv ++ explicit_iv
        plaintext = zipWith xor ciphertext (toList $ Stream.take (length ciphertext) $ aes_keystream AES128 key iv')
        mac_tag = aes_gcm_create_aad AES128 key iv' (aadf plaintext) ciphertext
    in (plaintext, s_eq' (toList mac_tag) mac_tag')

public export
data TLS13_AES_256_GCM : Type where

public export
AEAD TLS13_AES_256_GCM where
  iv_bytes = 12
  key_bytes = 32
  mac_bytes = 16
  mac_key_bytes = 0
  explicit_iv_bytes = 0

  encrypt key iv mac_key seq_no plaintext aad =
    let iv' = zipWith xor iv $ integer_to_be _ $ natToInteger seq_no
        ciphertext = zipWith xor plaintext (toList $ Stream.take (length plaintext) $ aes_keystream AES256 key iv')
        mac_tag = aes_gcm_create_aad AES256 key iv' aad ciphertext
    in ([], ciphertext, mac_tag)

  decrypt key iv [] mac_key seq_no ciphertext aadf mac_tag' =
    let iv' = zipWith xor iv $ integer_to_be _ $ natToInteger seq_no
        plaintext = zipWith xor ciphertext (toList $ Stream.take (length ciphertext) $ aes_keystream AES256 key iv')
        mac_tag = aes_gcm_create_aad AES256 key iv' (aadf plaintext) ciphertext
    in (plaintext, s_eq' (toList mac_tag) mac_tag')

public export
data TLS12_AES_256_GCM : Type where

public export
AEAD TLS12_AES_256_GCM where
  iv_bytes = 4
  key_bytes = 32
  mac_bytes = 16
  mac_key_bytes = 0
  explicit_iv_bytes = 8

  encrypt key iv mac_key seq_no plaintext aad =
    let explicit_iv = to_be {n=8} $ cast {to=Bits64} seq_no
        iv' = iv ++ explicit_iv
        ciphertext = zipWith xor plaintext (toList $ Stream.take (length plaintext) $ aes_keystream AES256 key iv')
        mac_tag = aes_gcm_create_aad AES256 key iv' aad ciphertext
    in (explicit_iv, ciphertext, mac_tag)

  decrypt key iv explicit_iv mac_key seq_no ciphertext aadf mac_tag' =
    let iv' = iv ++ explicit_iv
        plaintext = zipWith xor ciphertext (toList $ Stream.take (length ciphertext) $ aes_keystream AES256 key iv')
        mac_tag = aes_gcm_create_aad AES256 key iv' (aadf plaintext) ciphertext
    in (plaintext, s_eq' (toList mac_tag) mac_tag')


{-
public export
data ChaCha20_Poly1305 : Type where

clamp : Integer -> Integer
clamp r = r .&. 0x0ffffffc0ffffffc0ffffffc0fffffff

poly1305_prime : Integer
poly1305_prime = 0x3fffffffffffffffffffffffffffffffb

public export
AEAD ChaCha20_Poly1305 where
  iv_bytes = 12
  tls12_iv_bytes = 4
  key_bytes = 32
  mac_bytes = 16
  keystream key iv =
    let k' = from_le {n=4} <$> group 8 4 key
        i' = from_le {n=4} <$> group 3 4 iv
    in stream_concat $ map (\c => toList $ ChaCha.block 10 (cast c) k' i') $ drop 1 nats
  create_aad key iv aad ciphertext =
    let k' = from_le {n=4} <$> group 8 4 key
        i' = from_le {n=4} <$> group 3 4 iv
        s = le_to_integer $ take 32 $ ChaCha.block 10 0 k' i'
        r = clamp s
        length_aad = toList $ to_le {n=4} $ cast {to=Bits32} $ length aad
        length_ciphertext = toList $ to_le {n=4} $ cast {to=Bits32} $ length ciphertext
        ns = map (\x => le_to_integer' (x <+> [0x01])) $ chunk 16 (ciphertext ++ length_aad ++ length_ciphertext)
    in integer_to_le 16 (s + foldr (\n,a => mul_mod r (a + n) poly1305_prime) 0 ns)
-}