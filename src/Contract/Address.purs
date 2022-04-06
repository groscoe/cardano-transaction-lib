-- | A module for Address-related functionality and querying own wallet.
module Contract.Address
  ( getNetworkId
  , getWalletAddress
  , getWalletCollateral
  , module ExportAddress
  , module Bech32
  , module ByteArray
  , module Scripts
  , module SerializationAddress
  , module Transaction
  , module UnbalancedTransaction
  , ownPaymentPubKeyHash
  , ownPubKeyHash
  ) where

import Address
  ( enterpriseAddressMintingPolicyHash
  , enterpriseAddressScriptHash
  , enterpriseAddressStakeValidatorHash
  , enterpriseAddressValidatorHash
  ) as ExportAddress
import Address (getNetworkId) as Address
import Contract.Monad (Contract)
import Data.Maybe (Maybe)
import Data.Newtype (wrap)
import QueryM
  ( getWalletAddress
  , getWalletCollateral
  , ownPaymentPubKeyHash
  , ownPubKeyHash
  ) as QueryM
import Scripts
  ( typedValidatorBaseAddress
  , typedValidatorEnterpriseAddress
  , validatorHashBaseAddress
  , validatorHashEnterpriseAddress
  ) as Scripts
import Serialization.Address (Address)
import Serialization.Address -- There are a lot of helpers we have ignored here, we may want to include them.
  ( Slot(Slot)
  , BlockId(BlockId)
  , TransactionIndex(TransactionIndex)
  , CertificateIndex(CertificateIndex)
  , Pointer
  , Address
  , BaseAddress
  , ByronAddress
  , EnterpriseAddress
  , PointerAddress
  , RewardAddress
  , StakeCredential
  , ByronProtocolMagic(ByronProtocolMagic)
  , NetworkId(TestnetId, MainnetId)
  ) as SerializationAddress
import Types.Aliases (Bech32String) as Bech32
import Types.ByteArray (ByteArray) as ByteArray
import Types.UnbalancedTransaction
  ( PubKeyHash
  , PaymentPubKeyHash
  )
import Types.UnbalancedTransaction
  ( PaymentPubKey(PaymentPubKey)
  , PaymentPubKeyHash(PaymentPubKeyHash)
  , PubKeyHash(PubKeyHash)
  , ScriptOutput(ScriptOutput)
  , StakeKeyHash(StakeKeyHash)
  , StakePubKeyHash(StakePubKeyHash)
  , payPubKeyHashBaseAddress
  , payPubKeyHashEnterpriseAddress
  , payPubKeyRequiredSigner
  , payPubKeyVkey
  -- , pubKeyHash
  , pubKeyHashBaseAddress
  , pubKeyHashEnterpriseAddress
  , stakeKeyHashRewardAddress
  , stakePubKeyHashRewardAddress
  ) as UnbalancedTransaction
import Types.Transaction
  ( Ed25519Signature(Ed25519Signature)
  , PublicKey(PublicKey)
  , RequiredSigner(RequiredSigner)
  , Vkey(Vkey)
  , Vkeywitness(Vkeywitness)
  ) as Transaction
import Types.TransactionUnspentOutput (TransactionUnspentOutput)

-- | Get the `Address` of the browser wallet.
getWalletAddress :: Contract (Maybe Address)
getWalletAddress = wrap QueryM.getWalletAddress

-- | Get the collateral of the browser wallet. This collateral will vary
-- | depending on the wallet.
-- | E.g. Nami creates a hardcoded 5 Ada collateral.
getWalletCollateral :: Contract (Maybe TransactionUnspentOutput)
getWalletCollateral = wrap QueryM.getWalletCollateral

-- | Gets the wallet `PaymentPubKeyHash` via `getWalletAddress`.
ownPaymentPubKeyHash :: Contract (Maybe PaymentPubKeyHash)
ownPaymentPubKeyHash = wrap QueryM.ownPaymentPubKeyHash

-- | Gets the wallet `PubKeyHash` via `getWalletAddress`.
ownPubKeyHash :: Contract (Maybe PubKeyHash)
ownPubKeyHash = wrap QueryM.ownPubKeyHash

-- | Gets the wallet `PubKeyHash` via `getWalletAddress`.
getNetworkId :: Contract SerializationAddress.NetworkId
getNetworkId = wrap Address.getNetworkId
