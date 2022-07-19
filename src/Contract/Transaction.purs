-- | A module that defines the different transaction data types, balancing
-- | functionality, transaction fees, signing and submission.
module Contract.Transaction
  ( BalancedSignedTransaction(BalancedSignedTransaction)
  , balanceAndSignTx
  , balanceAndSignTxs
  , balanceAndSignTxE
  , balanceAndSignTxE'
  , balanceTx
  , balanceTxM
  , calculateMinFee
  , calculateMinFeeM
  , module BalanceTxError
  , module ExportQueryM
  , module PTransaction
  , module ReindexRedeemersExport
  , module ScriptLookups
  , module Transaction
  , module TransactionMetadata
  , module UnbalancedTx
  , reindexSpentScriptRedeemers
  , scriptOutputToTransactionOutput
  , signTransaction
  , submit
  , withBalancedTxs
  , withBalancedTx
  , withBalancedAndSignedTxs
  , withBalancedAndSignedTx
  ) where

import Prelude

import BalanceTx (BalanceTxError) as BalanceTxError
import BalanceTx (FinalizedTransaction)
import BalanceTx (balanceTx') as BalanceTx
import Cardano.Types.Transaction
  ( AuxiliaryData(AuxiliaryData)
  , AuxiliaryDataHash(AuxiliaryDataHash)
  , BootstrapWitness
  , Certificate
      ( StakeRegistration
      , StakeDeregistration
      , StakeDelegation
      , PoolRegistration
      , PoolRetirement
      , GenesisKeyDelegation
      , MoveInstantaneousRewardsCert
      )
  , CostModel(CostModel)
  , Costmdls(Costmdls)
  , Ed25519Signature(Ed25519Signature)
  , Epoch(Epoch)
  , ExUnitPrices
  , ExUnits
  , GenesisHash(GenesisHash)
  , Language(PlutusV1)
  , Mint(Mint)
  , NativeScript
      ( ScriptPubkey
      , ScriptAll
      , ScriptAny
      , ScriptNOfK
      , TimelockStart
      , TimelockExpiry
      )
  , Nonce(IdentityNonce, HashNonce)
  , ProposedProtocolParameterUpdates(ProposedProtocolParameterUpdates)
  , ProtocolParamUpdate
  , ProtocolVersion
  , PublicKey(PublicKey)
  , Redeemer
  , RequiredSigner(RequiredSigner)
  , ScriptDataHash(ScriptDataHash)
  , SubCoin
  , Transaction(Transaction)
  , TransactionWitnessSet(TransactionWitnessSet)
  , TxBody(TxBody)
  , UnitInterval
  , Update
  , Vkey(Vkey)
  , Vkeywitness(Vkeywitness)
  , _auxiliaryData
  , _auxiliaryDataHash
  , _body
  , _bootstraps
  , _certs
  , _collateral
  , _fee
  , _inputs
  , _isValid
  , _mint
  , _nativeScripts
  , _networkId
  , _outputs
  , _plutusData
  , _plutusScripts
  , _requiredSigners
  , _scriptDataHash
  , _ttl
  , _update
  , _validityStartInterval
  , _vkeys
  , _withdrawals
  , _witnessSet
  ) as Transaction
import Cardano.Types.Transaction (Transaction)
import Contract.Monad (Contract, liftedE, liftedM, wrapContract)
import Control.Monad.Error.Class (try, catchError, throwError)
import Control.Monad.Reader (asks, runReaderT, ReaderT)
import Data.Array.NonEmpty as NonEmptyArray
import Data.Either (Either, hush)
import Data.Generic.Rep (class Generic)
import Data.Maybe (Maybe(Nothing))
import Data.Newtype (class Newtype, unwrap, wrap)
import Data.Show.Generic (genericShow)
import Data.Traversable (class Traversable, for_, traverse)
import Data.Tuple.Nested (type (/\))
import Effect.Class (liftEffect)
import Effect.Exception (Error, throw)
import Plutus.Conversion (toPlutusCoin, toPlutusTxOutput)
import Plutus.Types.Transaction (TransactionOutput(TransactionOutput)) as PTransaction
import Plutus.Types.Value (Coin)
import QueryM (FeeEstimate(FeeEstimate), ClientError(..)) as ExportQueryM
import QueryM (calculateMinFee, signTransaction, submitTxOgmios) as QueryM
import ReindexRedeemers (ReindexErrors(CannotGetTxOutRefIndexForRedeemer)) as ReindexRedeemersExport
import ReindexRedeemers (reindexSpentScriptRedeemers) as ReindexRedeemers
import Serialization (convertTransaction, toBytes) as Serialization
import Serialization.Address (Address, NetworkId)
import TxOutput (scriptOutputToTransactionOutput) as TxOutput
import Types.ScriptLookups (MkUnbalancedTxError(..), mkUnbalancedTx) as ScriptLookups
import Types.ScriptLookups (UnattachedUnbalancedTx)
import Types.Transaction
  ( DataHash(DataHash)
  , TransactionHash(TransactionHash)
  , TransactionInput(TransactionInput)
  ) as Transaction
import Types.Transaction (TransactionHash)
import Types.TransactionMetadata
  ( GeneralTransactionMetadata(GeneralTransactionMetadata)
  , TransactionMetadatumLabel(TransactionMetadatumLabel)
  , TransactionMetadatum(MetadataMap, MetadataList, Int, Bytes, Text)
  ) as TransactionMetadata
import Types.UnbalancedTransaction
  ( ScriptOutput(ScriptOutput)
  , UnbalancedTx(UnbalancedTx)
  , _transaction
  , _utxoIndex
  , emptyUnbalancedTx
  ) as UnbalancedTx
import Types.UsedTxOuts
  ( UsedTxOuts
  , lockTransactionInputs
  , unlockTransactionInputs
  )
import Untagged.Union (asOneOf)

-- | This module defines transaction-related requests. Currently signing and
-- | submission is done with Nami.

-- | Signs a `Transaction` with potential failure.
signTransaction
  :: forall (r :: Row Type). Transaction -> Contract r (Maybe Transaction)
signTransaction = wrapContract <<< QueryM.signTransaction

-- | Signs a `FinalizedTransaction` with potential failure.
signTransaction'
  :: forall (r :: Row Type)
   . FinalizedTransaction
  -> Contract r (Maybe BalancedSignedTransaction)
signTransaction' =
  map (map BalancedSignedTransaction) <<< signTransaction <<< unwrap

-- | Submits a `BalancedSignedTransaction`, which is the output of
-- | `signTransaction` or `balanceAndSignTx`
submit
  :: forall (r :: Row Type)
   . BalancedSignedTransaction
  -> Contract r TransactionHash
submit tx = wrapContract <<< map (wrap <<< unwrap) <<< QueryM.submitTxOgmios =<<
  liftEffect
    ( wrap <<< Serialization.toBytes <<< asOneOf <$>
        Serialization.convertTransaction (unwrap tx)
    )

-- | Query the Haskell server for the minimum transaction fee
calculateMinFee
  :: forall (r :: Row Type)
   . Transaction
  -> Contract r (Either ExportQueryM.ClientError Coin)
calculateMinFee = (map <<< map) toPlutusCoin
  <<< wrapContract
  <<< QueryM.calculateMinFee

-- | Same as `calculateMinFee` hushing the error.
calculateMinFeeM
  :: forall (r :: Row Type). Transaction -> Contract r (Maybe Coin)
calculateMinFeeM = map hush <<< calculateMinFee

-- | Helper to adapt to UsedTxOuts
withUsedTxouts
  :: forall (r :: Row Type) (a :: Type)
   . ReaderT UsedTxOuts (Contract r) a
  -> Contract r a
withUsedTxouts f = asks (_.usedTxOuts <<< unwrap) >>= runReaderT f

-- | Attempts to balance an `UnattachedUnbalancedTx`.
balanceTx
  :: forall (r :: Row Type)
   . UnattachedUnbalancedTx
  -> Contract r (Either BalanceTxError.BalanceTxError FinalizedTransaction)
balanceTx = balanceTx' Nothing

balanceTx'
  :: forall (r :: Row Type)
   . Maybe Address
  -> UnattachedUnbalancedTx
  -> Contract r (Either BalanceTxError.BalanceTxError FinalizedTransaction)
balanceTx' addr = wrapContract <<< BalanceTx.balanceTx' addr

-- Helper to avoid repetition
withTransactions
  :: forall (a :: Type)
       (t :: Type -> Type)
       (r :: Row Type)
       (tx :: Type)
   . Traversable t
  => (t UnattachedUnbalancedTx -> Contract r (t tx))
  -> (tx -> Transaction)
  -> t UnattachedUnbalancedTx
  -> (t tx -> Contract r a)
  -> Contract r a
withTransactions prepare extract utxs action = do
  txs <- prepare utxs
  res <- try $ action txs
  void $ traverse (withUsedTxouts <<< unlockTransactionInputs)
    $ map extract
    $ txs
  liftedE $ pure res

withSingleTransaction
  :: forall (a :: Type) (tx :: Type) (r :: Row Type)
   . (UnattachedUnbalancedTx -> Contract r tx)
  -> (tx -> Transaction)
  -> UnattachedUnbalancedTx
  -> (tx -> Contract r a)
  -> Contract r a
withSingleTransaction prepare extract utx action =
  withTransactions (traverse prepare) extract (NonEmptyArray.singleton utx)
    (action <<< NonEmptyArray.head)

-- | Execute an action on an array of balanced
-- | transactions (`balanceTxs` will be called). Within
-- | this function, all transaction inputs used by these
-- | transactions will be locked, so that they are not used
-- | in any other context.
-- | After the function completes, the locks will be removed.
-- | Errors will be thrown.
withBalancedTxs
  :: forall (a :: Type) (r :: Row Type)
   . Array UnattachedUnbalancedTx
  -> (Array FinalizedTransaction -> Contract r a)
  -> Contract r a
withBalancedTxs = withTransactions (balanceTxs Nothing) unwrap

-- | Execute an action on a balanced transaction (`balanceTx` will
-- | be called). Within this function, all transaction inputs
-- | used by this transaction will be locked, so that they are not
-- | used in any other context.
-- | After the function completes, the locks will be removed.
-- | Errors will be thrown.
withBalancedTx
  :: forall (a :: Type) (r :: Row Type)
   . UnattachedUnbalancedTx
  -> (FinalizedTransaction -> Contract r a)
  -> Contract r a
withBalancedTx = withSingleTransaction (liftedE <<< balanceTx) unwrap

-- | Execute an action on an array of balanced and signed
-- | transactions (`balanceAndSignTxs` will be called). Within
-- | this function, all transaction inputs used by these
-- | transactions will be locked, so that they are not used
-- | in any other context.
-- | After the function completes, the locks will be removed.
-- | Errors will be thrown.
withBalancedAndSignedTxs
  :: forall (r :: Row Type) (a :: Type)
   . Array UnattachedUnbalancedTx
  -> (Array BalancedSignedTransaction -> Contract r a)
  -> Contract r a
withBalancedAndSignedTxs = withTransactions balanceAndSignTxs unwrap

-- | Execute an action on a balanced and signed transaction.
-- | (`balanceAndSignTx` will be called). Within this function,
-- | all transaction inputs used by this transaction will be
-- | locked, so that they are not used in any other context.
-- | After the function completes, the locks will be removed.
-- | Errors will be thrown.
withBalancedAndSignedTx
  :: forall (a :: Type) (r :: Row Type)
   . UnattachedUnbalancedTx
  -> (BalancedSignedTransaction -> Contract r a)
  -> Contract r a
withBalancedAndSignedTx = withSingleTransaction
  (liftedE <<< balanceAndSignTxE)
  unwrap

-- | Balances each transaction and locks the used inputs
-- | so that they cannot be reused by subsequent transactions.
balanceTxs
  :: forall
       (t :: Type -> Type)
       (r :: Row Type)
   . Traversable t
  => Maybe Address
  -> t UnattachedUnbalancedTx
  -> Contract r (t FinalizedTransaction)
balanceTxs addr unbalancedTxs =
  unlockAllOnError $ traverse balanceAndLock unbalancedTxs
  where
  unlockAllOnError :: forall (a :: Type). Contract r a -> Contract r a
  unlockAllOnError f = catchError f $ \e -> do
    for_ unbalancedTxs $
      withUsedTxouts <<< unlockTransactionInputs <<< uutxToTx
    throwError e

  uutxToTx :: UnattachedUnbalancedTx -> Transaction
  uutxToTx = _.transaction <<< unwrap <<< _.unbalancedTx <<< unwrap

  balanceAndLock :: UnattachedUnbalancedTx -> Contract r FinalizedTransaction
  balanceAndLock unbalancedTx = do
    balancedTx <- liftedE $ balanceTx' addr unbalancedTx
    void $ withUsedTxouts $ lockTransactionInputs (unwrap balancedTx)
    pure balancedTx

-- | Attempts to balance an `UnattachedUnbalancedTx` hushing the error.
balanceTxM
  :: forall (r :: Row Type)
   . UnattachedUnbalancedTx
  -> Contract r (Maybe FinalizedTransaction)
balanceTxM = map hush <<< balanceTx

-- | Reindex the `Spend` redeemers. Since we insert to an ordered array, we must
-- | reindex the redeemers with such inputs. This must be crucially called after
-- | balancing when all inputs are in place so they cannot be reordered.
reindexSpentScriptRedeemers
  :: forall (r :: Row Type)
   . Array Transaction.TransactionInput
  -> Array (Transaction.Redeemer /\ Maybe Transaction.TransactionInput)
  -> Contract r
       ( Either
           ReindexRedeemersExport.ReindexErrors
           (Array Transaction.Redeemer)
       )
reindexSpentScriptRedeemers balancedTx =
  wrapContract <<< ReindexRedeemers.reindexSpentScriptRedeemers balancedTx

newtype BalancedSignedTransaction = BalancedSignedTransaction Transaction

derive instance Generic BalancedSignedTransaction _
derive instance Newtype BalancedSignedTransaction _
derive newtype instance Eq BalancedSignedTransaction

instance Show BalancedSignedTransaction where
  show = genericShow

-- | Like `balanceAndSignTx`, but for more than one transaction.
-- | This function may throw errors through the contract Monad.
-- | If successful, transaction inputs will be locked afterwards.
-- | If you want to re-use them in the same 'QueryM' context, call
-- | `unlockTransactionInputs`.
balanceAndSignTxs
  :: forall (r :: Row Type)
   . Array UnattachedUnbalancedTx
  -> Contract r (Array BalancedSignedTransaction)
balanceAndSignTxs = balanceAndSignTxs' Nothing

balanceAndSignTxs'
  :: forall (r :: Row Type)
   . Maybe Address
  -> Array UnattachedUnbalancedTx
  -> Contract r (Array BalancedSignedTransaction)
balanceAndSignTxs' addr txs = (balanceTxs addr) txs >>= traverse
  (liftedM "error signing a transaction" <<< signTransaction')

-- | Balances an unbalanced transaction and signs it.
-- |
-- | The return type includes the balanced (but unsigned) transaction for
-- | logging and more importantly, the `ByteArray` to be used with `submit` to
-- | submit the transaction.
-- | If successful, transaction inputs will be locked afterwards.
-- | If you want to re-use them in the same 'QueryM' context, call
-- | `unlockTransactionInputs`.
balanceAndSignTxE
  :: forall (r :: Row Type)
   . UnattachedUnbalancedTx
  -> Contract r (Either Error BalancedSignedTransaction)
balanceAndSignTxE = balanceAndSignTxE' Nothing

balanceAndSignTxE'
  :: forall (r :: Row Type)
   . Maybe Address
  -> UnattachedUnbalancedTx
  -> Contract r (Either Error BalancedSignedTransaction)
balanceAndSignTxE' addr tx = try $ balanceAndSignTxs' addr [ tx ] >>=
  case _ of
    [ x ] -> pure x
    -- Which error should we throw here?
    _ -> liftEffect $ throw $
      "Unexpected internal error during transaction signing"

-- | A helper that wraps a few steps into: balance an unbalanced transaction
-- | (`balanceTx`), reindex script spend redeemers (not minting redeemers)
-- | (`reindexSpentScriptRedeemers`), attach datums and redeemers to the
-- | transaction (`finalizeTx`), and finally sign (`signTransactionBytes`).
-- | The return type includes the balanced (but unsigned) transaction for
-- | logging and more importantly, the `ByteArray` to be used with `Submit` to
-- | submit the transaction.
-- | If successful, transaction inputs will be locked afterwards.
-- | If you want to re-use them in the same 'QueryM' context, call
-- | `unlockTransactionInputs`.
balanceAndSignTx
  :: forall (r :: Row Type)
   . UnattachedUnbalancedTx
  -> Contract r (Maybe BalancedSignedTransaction)
balanceAndSignTx = map hush <<< balanceAndSignTxE

scriptOutputToTransactionOutput
  :: NetworkId
  -> UnbalancedTx.ScriptOutput
  -> Maybe PTransaction.TransactionOutput
scriptOutputToTransactionOutput networkId =
  toPlutusTxOutput
    <<< TxOutput.scriptOutputToTransactionOutput networkId
