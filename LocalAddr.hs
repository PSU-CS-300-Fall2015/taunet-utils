-- Copyright © 2015 Bart Massey
-- [This program is licensed under the GPL version 3 or later.]
-- Please see the file COPYING in the source
-- distribution of this software for license terms.

-- Check address for locality.

module LocalAddr (AddressData(..), getLocalAddresses)
where

import Data.Word
import Network.Info

data AddressData = AddressDataIPv4 !Word32
                 | AddressDataIPv6 !(Word32, Word32, Word32, Word32)
                 deriving (Ord, Eq)

class AddressClass a where
    fromAddress :: a -> AddressData

instance AddressClass IPv4 where
    fromAddress (IPv4 w) = AddressDataIPv4 w

instance AddressClass IPv6 where
    fromAddress (IPv6 w1 w2 w3 w4) = AddressDataIPv6 (w1, w2, w3, w4)

instance Show AddressData where
    show (AddressDataIPv4 w) = show $ IPv4 w
    show (AddressDataIPv6 (w1, w2, w3, w4)) = show $ IPv6 w1 w2 w3 w4

getLocalAddresses :: IO [AddressData]
getLocalAddresses = do
  ifaces <- getNetworkInterfaces
  let translate f = map (fromAddress . f) ifaces
  return $ translate ipv4 ++ translate ipv6
