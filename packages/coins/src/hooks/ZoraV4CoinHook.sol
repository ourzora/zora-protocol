// SPDX-License-Identifier: ZORA-DELAYED-OSL-v1
// This software is licensed under the Zora Delayed Open Source License.
// Under this license, you may use, copy, modify, and distribute this software for
// non-commercial purposes only. Commercial use and competitive products are prohibited
// until the "Open Date" (3 years from first public distribution or earlier at Zora's discretion),
// at which point this software automatically becomes available under the MIT License.
// Full license terms available at: https://docs.zora.co/coins/license
pragma solidity ^0.8.23;

import {BaseHook} from "@uniswap/v4-periphery/src/utils/BaseHook.sol";
import {Hooks} from "@uniswap/v4-core/src/libraries/Hooks.sol";
import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {BalanceDelta, BalanceDeltaLibrary} from "@uniswap/v4-core/src/types/BalanceDelta.sol";
import {Currency} from "@uniswap/v4-core/src/types/Currency.sol";
import {SwapParams} from "@uniswap/v4-core/src/types/PoolOperation.sol";
import {IZoraV4CoinHook} from "../interfaces/IZoraV4CoinHook.sol";
import {IMsgSender} from "../interfaces/IMsgSender.sol";
import {IHasSwapPath} from "../interfaces/ICoin.sol";
import {LpPosition} from "../types/LpPosition.sol";
import {V4Liquidity} from "../libs/V4Liquidity.sol";
import {CoinRewardsV4} from "../libs/CoinRewardsV4.sol";
import {ICoin} from "../interfaces/ICoin.sol";
import {IDeployedCoinVersionLookup} from "../interfaces/IDeployedCoinVersionLookup.sol";
import {CoinCommon} from "../libs/CoinCommon.sol";
import {CoinDopplerMultiCurve} from "../libs/CoinDopplerMultiCurve.sol";
import {PoolStateReader} from "../libs/PoolStateReader.sol";
import {IHasRewardsRecipients} from "../interfaces/ICoin.sol";
import {CoinConfigurationVersions} from "../libs/CoinConfigurationVersions.sol";
import {IUpgradeableV4Hook} from "../interfaces/IUpgradeableV4Hook.sol";
import {IHooksUpgradeGate} from "../interfaces/IHooksUpgradeGate.sol";
import {MultiOwnable} from "../utils/MultiOwnable.sol";
import {ERC165} from "@openzeppelin/contracts/utils/introspection/ERC165.sol";
import {IUpgradeableDestinationV4Hook} from "../interfaces/IUpgradeableV4Hook.sol";
import {IHooks} from "@uniswap/v4-core/src/interfaces/IHooks.sol";
import {BurnedPosition} from "../interfaces/IUpgradeableV4Hook.sol";
import {LiquidityAmounts} from "../utils/uniswap/LiquidityAmounts.sol";
import {TickMath} from "../utils/uniswap/TickMath.sol";
import {ContractVersionBase, IVersionedContract} from "../version/ContractVersionBase.sol";
import {IHasCoinType} from "../interfaces/ICoin.sol";

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
contract ZoraV4CoinHook is BaseHook, ContractVersionBase, IZoraV4CoinHook, ERC165, IUpgradeableDestinationV4Hook {
    using BalanceDeltaLibrary for BalanceDelta;

    /// @notice Mapping of trusted message senders - these are addresses that are trusted to provide a
    /// an original msg.sender
    mapping(address => bool) internal trustedMessageSender;

    /// @notice Mapping of pool keys to coins.
    mapping(bytes32 => IZoraV4CoinHook.PoolCoin) internal poolCoins;

    /// @notice The coin version lookup contract - used to determine if an address is a coin and what version it is.
    IDeployedCoinVersionLookup internal immutable coinVersionLookup;

    /// @notice The upgrade gate contract - used to verify allowed upgrade paths
    IHooksUpgradeGate internal immutable upgradeGate;

    /// @notice The constructor for the ZoraV4CoinHook.
    /// @param poolManager_ The Uniswap V4 pool manager
    /// @param coinVersionLookup_ The coin version lookup contract - used to determine if an address is a coin and what version it is.
    /// @param trustedMessageSenders_ The addresses of the trusted message senders - these are addresses that are trusted to provide a
    /// @param upgradeGate_ The upgrade gate contract for managing hook upgrades
    constructor(
        IPoolManager poolManager_,
        IDeployedCoinVersionLookup coinVersionLookup_,
        address[] memory trustedMessageSenders_,
        IHooksUpgradeGate upgradeGate_
    ) BaseHook(poolManager_) {
        require(address(coinVersionLookup_) != address(0), CoinVersionLookupCannotBeZeroAddress());

        require(address(upgradeGate_) != address(0), UpgradeGateCannotBeZeroAddress());

        coinVersionLookup = coinVersionLookup_;
        upgradeGate = upgradeGate_;

        for (uint256 i = 0; i < trustedMessageSenders_.length; i++) {
            trustedMessageSender[trustedMessageSenders_[i]] = true;
        }
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
                beforeSwap: false,
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
        return trustedMessageSender[sender];
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
            interfaceId == type(IVersionedContract).interfaceId;
    }

    /// @notice Internal fn generating the positions for a given pool key.
    /// @param coin The coin address.
    /// @param key The pool key for the coin.
    /// @return positions The contract-created liquidity positions the positions for the coin's pool.
    function _generatePositions(ICoin coin, PoolKey memory key) internal view returns (LpPosition[] memory positions) {
        bool isCoinToken0 = Currency.unwrap(key.currency0) == address(coin);

        positions = CoinDopplerMultiCurve.calculatePositions(isCoinToken0, coin.getPoolConfiguration(), coin.totalSupplyForPositions());
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
    function initializeFromMigration(
        PoolKey calldata poolKey,
        address coin,
        uint160 sqrtPriceX96,
        BurnedPosition[] calldata migratedLiquidity,
        bytes calldata
    ) external {
        address oldHook = msg.sender;
        address newHook = address(this);

        // Verify that the caller (new hook) is authorized to perform this migration
        // Only registered upgrade paths in the upgrade gate are allowed to migrate liquidity
        if (!upgradeGate.isRegisteredUpgradePath(oldHook, newHook)) {
            revert IUpgradeableV4Hook.UpgradePathNotRegistered(oldHook, newHook);
        }

        // Create a new pool key with the same parameters but pointing to this hook
        // This ensures the migrated pool uses the new hook implementation
        PoolKey memory newKey = PoolKey({
            currency0: poolKey.currency0,
            currency1: poolKey.currency1,
            fee: poolKey.fee,
            tickSpacing: poolKey.tickSpacing,
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

        // Handle any remaining token balances by adding them to the last position
        // This ensures no tokens are left unminted during the migration process
        _mintExtraLiquidityAtLastPosition(sqrtPriceX96, newKey);
    }

    /// @notice Internal fn to add any remaining token balances to the last liquidity position.
    /// @param sqrtPriceX96 The sqrt price x96.
    /// @param poolKey The pool key.
    function _mintExtraLiquidityAtLastPosition(uint160 sqrtPriceX96, PoolKey memory poolKey) internal {
        // Check if there are any leftover token balances in the hook after migration
        // These could result from rounding or partial liquidity transfers
        uint256 currency0Balance = poolKey.currency0.balanceOfSelf();
        uint256 currency1Balance = poolKey.currency1.balanceOfSelf();

        // Get the stored positions for this pool to access the last position
        LpPosition[] storage positions = poolCoins[CoinCommon.hashPoolKey(poolKey)].positions;

        // Only proceed if there are actually leftover tokens to mint
        if (currency0Balance > 0 || currency1Balance > 0) {
            // Get reference to the last position where we'll add the extra liquidity
            LpPosition storage lastPosition = positions[positions.length - 1];

            // Calculate how much liquidity we can create with the remaining token balances
            // This uses the current pool price and the last position's tick range
            uint128 newLiquidity = LiquidityAmounts.getLiquidityForAmounts(
                sqrtPriceX96,
                TickMath.getSqrtPriceAtTick(lastPosition.tickLower),
                TickMath.getSqrtPriceAtTick(lastPosition.tickUpper),
                currency0Balance,
                currency1Balance
            );

            // Create a temporary array with just the last position to mint the extra liquidity
            LpPosition[] memory newPositions = new LpPosition[](1);
            newPositions[0] = lastPosition;
            newPositions[0].liquidity = newLiquidity; // Set the calculated liquidity amount

            // Mint the extra liquidity into the pool using the V4 liquidity manager
            V4Liquidity.lockAndMint(poolManager, poolKey, newPositions);

            // Update our internal tracking of the last position's liquidity
            // This keeps our records in sync with the actual pool state
            positions[positions.length - 1].liquidity += newPositions[0].liquidity;
        }
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

        return (BaseHook.afterSwap.selector, 0);
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

    /// @notice Internal fn called when the PoolManager is unlocked.  Used to mint initial liquidity positions.
    function unlockCallback(bytes calldata data) external onlyPoolManager returns (bytes memory) {
        return V4Liquidity.handleCallback(poolManager, data);
    }

    /// @notice Internal fn to get the original message sender.
    /// @param sender The address of the sender.
    /// @return swapper The original message sender.
    /// @return senderIsTrusted Whether the sender is a trusted message sender.
    function _getOriginalMsgSender(address sender) internal view returns (address swapper, bool senderIsTrusted) {
        senderIsTrusted = trustedMessageSender[sender];

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
    }

    receive() external payable onlyPoolManager {}
}
