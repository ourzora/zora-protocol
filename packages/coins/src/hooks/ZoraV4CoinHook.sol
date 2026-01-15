// SPDX-License-Identifier: ZORA-DELAYED-OSL-v1
// This software is licensed under the Zora Delayed Open Source License.
// Under this license, you may use, copy, modify, and distribute this software for
// non-commercial purposes only. Commercial use and competitive products are prohibited
// until the "Open Date" (3 years from first public distribution or earlier at Zora's discretion),
// at which point this software automatically becomes available under the MIT License.
// Full license terms available at: https://docs.zora.co/coins/license
pragma solidity ^0.8.28;

import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {IHooks} from "@uniswap/v4-core/src/interfaces/IHooks.sol";
import {BaseHook} from "@uniswap/v4-periphery/src/utils/BaseHook.sol";
import {Hooks} from "@uniswap/v4-core/src/libraries/Hooks.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {BalanceDelta, BalanceDeltaLibrary} from "@uniswap/v4-core/src/types/BalanceDelta.sol";
import {Currency} from "@uniswap/v4-core/src/types/Currency.sol";
import {SwapParams} from "@uniswap/v4-core/src/types/PoolOperation.sol";
import {BeforeSwapDelta} from "@uniswap/v4-core/src/types/BeforeSwapDelta.sol";
import {StateLibrary} from "@uniswap/v4-core/src/libraries/StateLibrary.sol";
import {ERC165} from "@openzeppelin/contracts/utils/introspection/ERC165.sol";
import {TransientSlot} from "@openzeppelin/contracts/utils/TransientSlot.sol";

import {IZoraV4CoinHook} from "../interfaces/IZoraV4CoinHook.sol";
import {IMsgSender} from "../interfaces/IMsgSender.sol";
import {ITrustedMsgSenderProviderLookup} from "../interfaces/ITrustedMsgSenderProviderLookup.sol";
import {ICoin, IHasSwapPath, IHasRewardsRecipients, IHasCoinType} from "../interfaces/ICoin.sol";
import {IDeployedCoinVersionLookup} from "../interfaces/IDeployedCoinVersionLookup.sol";
import {IUpgradeableV4Hook, IUpgradeableDestinationV4Hook, IUpgradeableDestinationV4HookWithUpdateableFee, BurnedPosition} from "../interfaces/IUpgradeableV4Hook.sol";
import {IHooksUpgradeGate} from "../interfaces/IHooksUpgradeGate.sol";
import {IZoraHookRegistry} from "../interfaces/IZoraHookRegistry.sol";
import {IZoraLimitOrderBookCoinsInterface} from "../interfaces/IZoraLimitOrderBookCoinsInterface.sol";
import {LpPosition} from "../types/LpPosition.sol";
import {V4Liquidity} from "../libs/V4Liquidity.sol";
import {CoinRewardsV4} from "../libs/CoinRewardsV4.sol";
import {CoinCommon} from "../libs/CoinCommon.sol";
import {CoinDopplerMultiCurve} from "../libs/CoinDopplerMultiCurve.sol";
import {PoolStateReader} from "../libs/PoolStateReader.sol";
import {CoinConfigurationVersions} from "../libs/CoinConfigurationVersions.sol";
import {CoinConstants} from "../libs/CoinConstants.sol";
import {LiquidityAmounts} from "../utils/uniswap/LiquidityAmounts.sol";
import {TickMath} from "../utils/uniswap/TickMath.sol";
import {ContractVersionBase, IVersionedContract} from "../version/ContractVersionBase.sol";
import {ISupportsLimitOrderFill} from "../interfaces/ISupportsLimitOrderFill.sol";

/// @title ZoraV4CoinHook
/// @notice Uniswap V4 hook that automatically handles fee collection and reward distributions on every swap,
/// paying out all rewards in a backing currency.
/// @dev This hook executes on afterSwap withdraw fees, swap for a backing currency, and distribute rewards.
///      On pool initialization, it creates multiple liquidity positions based on the coin's pool configuration.
///      On every swap, it automatically:
///      1. Collects accrued LP fees from all positions
///      2. Swaps collected fees to the backing currency through multi-hop paths
///      3. Distributes converted fees as rewards
/// @author oveddan
contract ZoraV4CoinHook is
    BaseHook,
    ContractVersionBase,
    IZoraV4CoinHook,
    ERC165,
    IUpgradeableDestinationV4Hook,
    IUpgradeableDestinationV4HookWithUpdateableFee
{
    using BalanceDeltaLibrary for BalanceDelta;

    /// @dev DEPRECATED: This mapping is kept for storage compatibility. It doesn't matter that storage slots moved around
    /// between versions since the contracts are immutable, but in some tests we do etching to test if a new hook fixes some bugs, so we want to maintain the storage slot order.
    /// This slot previously held the mappings of trusted message senders.
    mapping(address => bool) internal legacySlot0;

    /// @notice Mapping of pool keys to coins.
    mapping(bytes32 => IZoraV4CoinHook.PoolCoin) internal poolCoins;

    /// @notice The coin version lookup contract - used to determine if an address is a coin and what version it is.
    IDeployedCoinVersionLookup internal immutable coinVersionLookup;

    /// @notice The upgrade gate contract - used to verify allowed upgrade paths
    IHooksUpgradeGate internal immutable upgradeGate;

    /// @notice The trusted message sender lookup contract - used to determine if an address is trusted
    ITrustedMsgSenderProviderLookup internal immutable trustedMsgSenderLookup;

    /// @notice The Zora limit order book contract - used to fill limit orders during swaps
    IZoraLimitOrderBookCoinsInterface internal immutable zoraLimitOrderBook;

    /// @notice The Zora hook registry
    IZoraHookRegistry internal immutable zoraHookRegistry;

    /// @notice The constructor for the ZoraV4CoinHook.
    /// @param poolManager_ The Uniswap V4 pool manager
    /// @param coinVersionLookup_ The coin version lookup contract - used to determine if an address is a coin and what version it is.
    /// @param trustedMsgSenderLookup_ The trusted message sender lookup contract - used to determine if an address is trusted
    /// @param upgradeGate_ The upgrade gate contract for managing hook upgrades
    /// @param zoraLimitOrderBook_ The Zora limit order book contract for filling orders during swaps
    /// @param zoraHookRegistry_ The Zora hook registry contract for identifying registered hooks
    constructor(
        IPoolManager poolManager_,
        IDeployedCoinVersionLookup coinVersionLookup_,
        ITrustedMsgSenderProviderLookup trustedMsgSenderLookup_,
        IHooksUpgradeGate upgradeGate_,
        IZoraLimitOrderBookCoinsInterface zoraLimitOrderBook_,
        IZoraHookRegistry zoraHookRegistry_
    ) BaseHook(poolManager_) {
        require(address(coinVersionLookup_) != address(0), CoinVersionLookupCannotBeZeroAddress());
        require(address(upgradeGate_) != address(0), UpgradeGateCannotBeZeroAddress());
        require(address(zoraLimitOrderBook_) != address(0), ZoraLimitOrderBookCannotBeZeroAddress());
        require(address(zoraHookRegistry_) != address(0), ZoraHookRegistryCannotBeZeroAddress());
        require(address(trustedMsgSenderLookup_) != address(0), TrustedMsgSenderLookupCannotBeZeroAddress());

        coinVersionLookup = coinVersionLookup_;
        upgradeGate = upgradeGate_;
        trustedMsgSenderLookup = trustedMsgSenderLookup_;
        zoraLimitOrderBook = zoraLimitOrderBook_;
        zoraHookRegistry = zoraHookRegistry_;
    }

    /// @notice Returns the trusted message sender lookup contract
    function getTrustedMsgSenderLookup() external view returns (ITrustedMsgSenderProviderLookup) {
        return trustedMsgSenderLookup;
    }

    /// @notice Returns the uniswap v4 hook settings / permissions.
    /// @dev The permissions currently requested are: afterInitialize and afterSwap.
    function getHookPermissions() public pure override returns (Hooks.Permissions memory) {
        return
            Hooks.Permissions({
                beforeInitialize: false,
                afterInitialize: true,
                beforeAddLiquidity: false,
                afterAddLiquidity: false,
                beforeRemoveLiquidity: false,
                afterRemoveLiquidity: false,
                beforeSwap: true,
                afterSwap: true,
                beforeDonate: false,
                afterDonate: false,
                beforeSwapReturnDelta: false,
                afterSwapReturnDelta: false,
                afterAddLiquidityReturnDelta: false,
                afterRemoveLiquidityReturnDelta: false
            });
    }

    /// @inheritdoc IZoraV4CoinHook
    function isTrustedMessageSender(address sender) external view returns (bool) {
        return trustedMsgSenderLookup.isTrustedMsgSenderProvider(sender);
    }

    /// @inheritdoc IZoraV4CoinHook
    function getPoolCoinByHash(bytes32 poolKeyHash) external view returns (IZoraV4CoinHook.PoolCoin memory) {
        return poolCoins[poolKeyHash];
    }

    /// @inheritdoc IZoraV4CoinHook
    function getPoolCoin(PoolKey memory key) external view returns (IZoraV4CoinHook.PoolCoin memory) {
        return poolCoins[CoinCommon.hashPoolKey(key)];
    }

    /// @inheritdoc ERC165
    function supportsInterface(bytes4 interfaceId) public view virtual override returns (bool) {
        return
            super.supportsInterface(interfaceId) ||
            interfaceId == type(IUpgradeableDestinationV4Hook).interfaceId ||
            interfaceId == type(IUpgradeableDestinationV4HookWithUpdateableFee).interfaceId ||
            interfaceId == type(IVersionedContract).interfaceId ||
            interfaceId == type(ISupportsLimitOrderFill).interfaceId;
    }

    /// @notice Internal fn generating the positions for a given pool key.
    /// @param coin The coin address.
    /// @param key The pool key for the coin.
    /// @return positions The contract-created liquidity positions the positions for the coin's pool.
    function _generatePositions(ICoin coin, PoolKey memory key) internal view returns (LpPosition[] memory) {
        bool isCoinToken0 = Currency.unwrap(key.currency0) == address(coin);

        LpPosition[] memory calculatedPositions = CoinDopplerMultiCurve.calculatePositions(
            isCoinToken0,
            coin.getPoolConfiguration(),
            coin.totalSupplyForPositions()
        );

        // sometimes the calculated positions have liquidity added in duplicated positions.   So here we dedupe them
        // to save on gas in future swaps.
        return V4Liquidity.dedupePositions(calculatedPositions);
    }

    /// @notice Internal fn called when a pool is initialized.
    /// @dev This hook is called from BaseHook library from uniswap v4.
    /// @param sender The address of the sender.
    /// @param key The pool key.
    /// @return selector The selector of the afterInitialize hook to confirm the action.
    function _afterInitialize(address sender, PoolKey calldata key, uint160, int24) internal override returns (bytes4) {
        // If the sender is the hook itself, we assume this is a migration and we return early.
        if (sender == address(this)) {
            return BaseHook.afterInitialize.selector;
        }

        // Otherwise, we initialize the hook positions.
        address coin = sender;
        if (!CoinConfigurationVersions.isV4(coinVersionLookup.getVersionForDeployedCoin(coin))) {
            revert NotACoin(coin);
        }

        LpPosition[] memory positions = _generatePositions(ICoin(coin), key);

        _initializeForPositions(key, coin, positions);

        return BaseHook.afterInitialize.selector;
    }

    /// @inheritdoc IUpgradeableDestinationV4Hook
    /// @dev left for backward compatibility for migrating from hooks that dont support
    /// updating the fee
    function initializeFromMigration(
        PoolKey calldata poolKey,
        address coin,
        uint160 sqrtPriceX96,
        BurnedPosition[] calldata migratedLiquidity,
        bytes calldata additionalData
    ) external {
        // keep the existing fee and tick spacing.
        uint24 fee = poolKey.fee;
        int24 tickSpacing = poolKey.tickSpacing;

        _initializeFromMigration(poolKey, coin, sqrtPriceX96, migratedLiquidity, additionalData, fee, tickSpacing);
    }

    /// @inheritdoc IUpgradeableDestinationV4HookWithUpdateableFee
    function initializeFromMigrationWithUpdateableFee(
        PoolKey calldata poolKey,
        address coin,
        uint160 sqrtPriceX96,
        BurnedPosition[] calldata migratedLiquidity,
        bytes calldata additionalData
    ) external returns (uint24 fee, int24 tickSpacing) {
        // update the fee to the current one.
        fee = CoinConstants.LP_FEE_V4;
        tickSpacing = CoinConstants.TICK_SPACING;

        _initializeFromMigration(poolKey, coin, sqrtPriceX96, migratedLiquidity, additionalData, fee, tickSpacing);
    }

    function _initializeFromMigration(
        PoolKey calldata poolKey,
        address coin,
        uint160 sqrtPriceX96,
        BurnedPosition[] calldata migratedLiquidity,
        bytes calldata,
        uint24 fee,
        int24 tickSpacing
    ) internal {
        address oldHook = msg.sender;
        address newHook = address(this);

        // Verify that the caller (old hook) is authorized to perform this migration
        // Only registered upgrade paths in the upgrade gate are allowed to migrate liquidity
        if (!upgradeGate.isRegisteredUpgradePath(oldHook, newHook)) {
            revert IUpgradeableV4Hook.UpgradePathNotRegistered(oldHook, newHook);
        }

        // Create a new pool key with the same parameters but pointing to this hook
        // This ensures the migrated pool uses the new hook implementation
        PoolKey memory newKey = PoolKey({
            currency0: poolKey.currency0,
            currency1: poolKey.currency1,
            fee: fee,
            tickSpacing: tickSpacing,
            hooks: IHooks(newHook)
        });

        // Initialize the new pool with the migrated price
        // This creates the actual Uniswap V4 pool with the current market price
        // A side effect is that the _afterInitialize hook is called here, so we find self-referential calls there and return early.
        // This preserves the previous sqrtPriceX96 in the new pools.
        poolManager.initialize(newKey, sqrtPriceX96);

        // Convert the burned/migrated liquidity positions into new LP positions
        // This recreates the liquidity structure from the old hook in the new hook
        LpPosition[] memory positions = V4Liquidity.generatePositionsFromMigratedLiquidity(sqrtPriceX96, migratedLiquidity);

        // Store the positions and mint the initial liquidity into the new pool
        _initializeForPositions(newKey, coin, positions);
    }

    /// @notice Saves the positions for the coin and mints them into the pool
    /// @param key The pool key.
    /// @param coin The coin address.
    /// @param positions The positions.
    function _initializeForPositions(PoolKey memory key, address coin, LpPosition[] memory positions) internal {
        // Store the association between this pool and its coin + positions
        // This creates the internal mapping that tracks which coin owns which positions
        poolCoins[CoinCommon.hashPoolKey(key)] = PoolCoin({coin: coin, positions: positions});

        // Mint all the calculated liquidity positions into the Uniswap V4 pool
        // This actually provides the liquidity that users can trade against
        V4Liquidity.lockAndMint(poolManager, key, positions);
    }

    /// @notice Transiently stores the tick before a swap.
    /// @dev This is used in `_afterSwap` to determine the ticks crossed during the swap.
    function _beforeSwap(
        address sender,
        PoolKey calldata key,
        SwapParams calldata,
        bytes calldata
    ) internal virtual override returns (bytes4, BeforeSwapDelta, uint24) {
        if (_isInternalSwap(sender)) {
            return (BaseHook.beforeSwap.selector, BeforeSwapDelta.wrap(0), 0);
        }

        // Store tick for user-initiated swaps only
        (, int24 currentTick, , ) = StateLibrary.getSlot0(poolManager, key.toId());

        TransientSlot.Int256Slot slot = TransientSlot.asInt256(CoinConstants._BEFORE_SWAP_TICK_SLOT);
        TransientSlot.tstore(slot, int256(currentTick));

        return (BaseHook.beforeSwap.selector, BeforeSwapDelta.wrap(0), 0);
    }

    /// @notice Internal fn called when a swap is executed.
    /// @dev This hook is called from BaseHook library from uniswap v4.
    /// This hook:
    /// 1. Collects accrued LP fees from all positions
    /// 2. Mints a new LP position back into the pool
    /// 3. Swaps remaining collected fees to the backing currency through multi-hop paths
    /// 4. Distributes converted fees as rewards
    /// @param sender The address of the sender.
    /// @param key The pool key.
    /// @param params The swap parameters.
    /// @param delta The balance delta.
    /// @param hookData The hook data.
    /// @return selector The selector of the afterSwap hook to confirm the action.
    function _afterSwap(
        address sender,
        PoolKey calldata key,
        SwapParams calldata params,
        BalanceDelta delta,
        bytes calldata hookData
    ) internal virtual override returns (bytes4, int128) {
        if (_isInternalSwap(sender)) {
            return (BaseHook.afterSwap.selector, 0);
        }

        bytes32 poolKeyHash = CoinCommon.hashPoolKey(key);

        // get the coin address and positions for the pool key; they must have been set in the afterInitialize callback
        address coin = poolCoins[poolKeyHash].coin;
        require(coin != address(0), NoCoinForHook(key));

        // get path for swapping the payout to a single currency
        IHasSwapPath.PayoutSwapPath memory payoutSwapPath = IHasSwapPath(coin).getPayoutSwapPath(coinVersionLookup);

        // collect lp fees
        (int128 fees0, int128 fees1) = V4Liquidity.collectFees(poolManager, key, poolCoins[poolKeyHash].positions);

        (uint128 marketRewardsAmount0, uint128 marketRewardsAmount1) = CoinRewardsV4.mintLpReward(poolManager, key, fees0, fees1);

        // convert remaining fees to payout currency for market rewards
        (Currency payoutCurrency, uint128 payoutAmount) = CoinRewardsV4.convertToPayoutCurrency(
            poolManager,
            marketRewardsAmount0,
            marketRewardsAmount1,
            payoutSwapPath
        );

        _distributeMarketRewards(payoutCurrency, payoutAmount, ICoin(coin), CoinRewardsV4.getTradeReferral(hookData));

        {
            (address swapper, bool isTrustedSwapSenderAddress) = _getOriginalMsgSender(sender);
            bool isCoinBuy = params.zeroForOne ? Currency.unwrap(key.currency1) == address(coin) : Currency.unwrap(key.currency0) == address(coin);
            emit Swapped(
                sender,
                swapper,
                isTrustedSwapSenderAddress,
                key,
                poolKeyHash,
                params,
                delta.amount0(),
                delta.amount1(),
                isCoinBuy,
                hookData,
                PoolStateReader.getSqrtPriceX96(key, poolManager)
            );
        }

        (int24 tickBeforeSwap, int24 tickAfterSwap) = _getSwapTickRange(key);

        // Derive fill direction from actual tick movement
        if (tickAfterSwap != tickBeforeSwap) {
            bool isCurrency0 = tickAfterSwap > tickBeforeSwap;
            zoraLimitOrderBook.fill(key, isCurrency0, tickBeforeSwap, tickAfterSwap, CoinConstants.SENTINEL_DEFAULT_LIMIT_ORDER_FILL_COUNT, address(0));
        }

        return (BaseHook.afterSwap.selector, 0);
    }

    /// @dev Get the tick range of a swap
    function _getSwapTickRange(PoolKey calldata key) internal view returns (int24 tickBeforeSwap, int24 tickAfterSwap) {
        TransientSlot.Int256Slot slot = TransientSlot.asInt256(CoinConstants._BEFORE_SWAP_TICK_SLOT);
        tickBeforeSwap = int24(int256(TransientSlot.tload(slot)));
        (, tickAfterSwap, , ) = StateLibrary.getSlot0(poolManager, key.toId());
    }

    /// @dev Internal fn to allow for overriding market reward distribution logic
    function _distributeMarketRewards(Currency currency, uint128 fees, IHasRewardsRecipients coin, address tradeReferrer) internal virtual {
        // get rewards distribution methodology from the coin
        IHasCoinType.CoinType coinType = _getCoinType(coin);
        CoinRewardsV4.distributeMarketRewards(currency, fees, coin, tradeReferrer, coinType);
    }

    function _getCoinType(IHasRewardsRecipients coin) internal view returns (IHasCoinType.CoinType) {
        return CoinRewardsV4.getCoinType(coin);
    }

    /// @notice Internal fn called when the PoolManager is unlocked. Used to mint initial liquidity positions and burn positions during migration.
    function unlockCallback(bytes calldata data) external onlyPoolManager returns (bytes memory) {
        return V4Liquidity.handleCallback(poolManager, data);
    }

    /// @notice Internal fn to get the original message sender.
    /// @param sender The address of the sender.
    /// @return swapper The original message sender.
    /// @return senderIsTrusted Whether the sender is a trusted message sender.
    function _getOriginalMsgSender(address sender) internal view returns (address swapper, bool senderIsTrusted) {
        senderIsTrusted = trustedMsgSenderLookup.isTrustedMsgSenderProvider(sender);

        // If getter function reverts, we return a 0 address by default and continue execution.
        try IMsgSender(sender).msgSender() returns (address _swapper) {
            swapper = _swapper;
        } catch {
            swapper = address(0);
        }
    }

    /// @inheritdoc IUpgradeableV4Hook
    function migrateLiquidity(address newHook, PoolKey memory poolKey, bytes calldata additionalData) external returns (PoolKey memory newPoolKey) {
        bytes32 poolKeyHash = CoinCommon.hashPoolKey(poolKey);
        PoolCoin storage poolCoin = poolCoins[poolKeyHash];
        // check that the coin associated with the poolkey is the caller
        require(poolCoin.coin == msg.sender, OnlyCoin(msg.sender, poolCoin.coin));

        // Verify upgrade path is allowed
        if (!upgradeGate.isRegisteredUpgradePath(address(this), newHook)) {
            revert IUpgradeableV4Hook.UpgradePathNotRegistered(address(this), newHook);
        }

        newPoolKey = V4Liquidity.lockAndMigrate(poolManager, poolKey, poolCoin.positions, poolCoin.coin, newHook, additionalData);

        // Delete the old pool key mapping to prevent future operations on the migrated pool
        delete poolCoins[poolKeyHash];
    }

    /// @dev Checks if the swap is internal and should skip hook operations
    function _isInternalSwap(address sender) internal view returns (bool) {
        return sender == address(this) ||
               sender == address(zoraLimitOrderBook) ||
               zoraHookRegistry.isRegisteredHook(sender);
    }

    /// @notice Receives ETH from the pool manager for ETH-backed coins during fee collection.
    /// @dev Only required for coins using ETH as backing currency (currency = address(0)).
    ///      Restricted to onlyPoolManager to prevent ETH from getting stuck in the contract.
    ///      Unused for ERC20-backed coins.
    receive() external payable onlyPoolManager {}
}
