module Wallet
  ( NamiConnection
  , NamiWallet
  , Wallet(..)
  , mkNamiWalletAff
  ) where

import Prelude
import Control.Promise as Promise
import Control.Promise (Promise)
import Data.Maybe (Maybe(..), maybe)
import Data.Typelevel.Undefined (undefined)
import Deserialization as Deserialization
import Effect (Effect)
import Effect.Aff (Aff)
import Effect.Class (liftEffect)
import Effect.Ref as Ref
import Serialization as Serialization
import Types.ByteArray
import Types.Transaction (Address, TransactionOutput, Transaction)

-- At the moment, we only support Nami's wallet. In the future we will expand
-- this with more constructors to represent out-of-browser wallets (e.g. WBE)
data Wallet = Nami NamiWallet

-------------------------------------------------------------------------------
-- Nami backend
-------------------------------------------------------------------------------
-- Record-of-functions for real or mocked Nami wallet, includes `Ref` to
-- connection (e.g. with `window.cardano.nami` as a `NamiConnection`)
type NamiWallet =
  { -- A reference to a connection with Nami, i.e. `window.cardano.nami`
    connection :: Ref.Ref NamiConnection
  -- Get the address associated with the wallet (Nami does not support
  -- multiple addresses)
  , getWalletAddress :: NamiConnection -> Aff (Maybe Address)
  -- Get the collateral UTxO associated with the Nami wallet
  , getCollateral :: NamiConnection -> Aff (Maybe TransactionOutput)
  -- Sign a transaction with the current wallet
  , signTx :: NamiConnection -> Transaction -> Aff Transaction
  }

mkNamiWalletAff :: Aff Wallet
mkNamiWalletAff = do
  nami <- enable
  connection <- liftEffect $ Ref.new nami
  pure $ Nami
    { connection
    , getWalletAddress
    , getCollateral: undefined -- TODO
    , signTx: undefined -- TODO
    }

  where
  enable :: Aff NamiConnection
  enable = Promise.toAffE $ _enableNami

  getWalletAddress :: NamiConnection -> Aff (Maybe Address)
  getWalletAddress nami = do
    bytes <- hexToByteArrayUnsafe <$> Promise.toAffE (_getNamiAddress nami)
    liftEffect $
      Deserialization.convertAddress
        <$> Serialization.newAddressFromBytes bytes

-------------------------------------------------------------------------------
-- FFI stuff
-------------------------------------------------------------------------------
foreign import data NamiConnection :: Type

foreign import _enableNami :: Effect (Promise NamiConnection)

foreign import _getNamiAddress :: NamiConnection -> Effect (Promise String)
