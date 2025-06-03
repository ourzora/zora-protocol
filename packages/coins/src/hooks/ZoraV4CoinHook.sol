// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {BaseHook} from "@uniswap/v4-periphery/src/utils/BaseHook.sol";
import {Hooks} from "@uniswap/v4-core/src/libraries/Hooks.sol";
import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {PoolIdLibrary} from "@uniswap/v4-core/src/types/PoolId.sol";
import {BalanceDelta, BalanceDeltaLibrary} from "@uniswap/v4-core/src/types/BalanceDelta.sol";
import {SwapParams} from "@uniswap/v4-core/src/types/PoolOperation.sol";
import {IZoraV4CoinHook} from "../interfaces/IZoraV4CoinHook.sol";
import {IMsgSender} from "../interfaces/IMsgSender.sol";
import {LpPosition} from "../types/LpPosition.sol";
import {SafeCast} from "@uniswap/v4-core/src/libraries/SafeCast.sol";
import {FixedPointMathLib} from "solmate/utils/FixedPointMathLib.sol";
import {V4Liquidity} from "../libs/V4Liquidity.sol";
import {CoinRewardsV4} from "../libs/CoinRewardsV4.sol";
import {ICoinV4} from "../interfaces/ICoinV4.sol";
import {IDeployedCoinVersionLookup} from "../interfaces/IDeployedCoinVersionLookup.sol";
import {IHasRewardsRecipients} from "../interfaces/ICoin.sol";
import {Currency} from "@uniswap/v4-core/src/types/Currency.sol";
import {CoinCommon} from "../libs/CoinCommon.sol";
import {PoolConfiguration} from "../types/PoolConfiguration.sol";
import {CoinFactoryConfigurationVersions} from "../types/CoinFactoryConfigurationVersions.sol";
import {CoinDopplerMultiCurve} from "../libs/CoinDopplerMultiCurve.sol";
import {PoolStateReader} from "../libs/PoolStateReader.sol";
import {IHasSwapPath} from "../interfaces/ICoinV4.sol";

contract ZoraV4CoinHook is BaseHook, IZoraV4CoinHook {
    using BalanceDeltaLibrary for BalanceDelta;

    mapping(address => bool) internal trustedMessageSender;

    IDeployedCoinVersionLookup internal immutable coinVersionLookup;

    /// @inheritdoc IZoraV4CoinHook
    function isTrustedMessageSender(address sender) external view returns (bool) {
        return trustedMessageSender[sender];
    }

    /// @notice The constructor for the ZoraV4CoinHook.
    /// @param poolManager_ The pool manager for the coin.
    /// @param trustedMessageSenders_ The addresses of the trusted message senders.
    constructor(IPoolManager poolManager_, IDeployedCoinVersionLookup coinVersionLookup_, address[] memory trustedMessageSenders_) BaseHook(poolManager_) {
        if (address(coinVersionLookup_) == address(0)) {
            revert CoinVersionLookupCannotBeZeroAddress();
        }

        coinVersionLookup = coinVersionLookup_;

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

    mapping(bytes32 => IZoraV4CoinHook.PoolCoin) internal poolCoins;

    function getPoolCoinByHash(bytes23 poolKeyHash) external view returns (IZoraV4CoinHook.PoolCoin memory) {
        return poolCoins[poolKeyHash];
    }

    function getPoolCoin(PoolKey memory key) external view returns (IZoraV4CoinHook.PoolCoin memory) {
        return poolCoins[CoinCommon.hashPoolKey(key)];
    }

    /// @notice Internal fn generating the positions for a given pool key.
    /// @param coin The coin address.
    /// @param key The pool key for the coin.
    /// @return positions The contract-created liquidity positions the positions for the coin's pool.
    function _generatePositions(ICoinV4 coin, PoolKey memory key) internal view returns (LpPosition[] memory positions) {
        bool isCoinToken0 = Currency.unwrap(key.currency0) == address(coin);

        positions = CoinDopplerMultiCurve.calculatePositions(isCoinToken0, coin.getPoolConfiguration());
    }

    /// @notice Internal fn called when a pool is initialized.
    /// @dev This hook is called from BaseHook library from uniswap v4.
    /// @param sender The address of the sender.
    /// @param key The pool key.
    /// @return selector The selector of the afterInitialize hook to confirm the action.
    function _afterInitialize(address sender, PoolKey calldata key, uint160, int24) internal override returns (bytes4) {
        address coin = sender;
        if (coinVersionLookup.getVersionForDeployedCoin(coin) < CoinFactoryConfigurationVersions.V4_0) {
            revert NotACoin(coin);
        }

        LpPosition[] memory positions = _generatePositions(ICoinV4(coin), key);

        poolCoins[CoinCommon.hashPoolKey(key)] = PoolCoin({coin: coin, positions: positions});

        V4Liquidity.lockAndMint(poolManager, key, positions);

        return BaseHook.afterInitialize.selector;
    }

    /// @notice Internal fn called when a swap is executed.
    /// @dev This hook is called from BaseHook library from uniswap v4.
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

        // Collect accrued LP fees from all positions, swap them to the target payout currency,
        // and transfer the converted amount to this hook contract for distribution
        (, , Currency receivedCurrency, uint128 receivedAmount) = CoinRewardsV4.collectFeesAndConvertToPayout(
            poolManager,
            key,
            poolCoins[poolKeyHash].positions,
            payoutSwapPath
        );

        // Distribute the collected and converted fees to all reward recipients (creator, referrers, protocol, etc.)
        CoinRewardsV4.distributeMarketRewards(receivedCurrency, receivedAmount, ICoinV4(coin), CoinRewardsV4.getTradeReferral(hookData));

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

    /// @notice Internal fn called when a liquidity is unlocked. Only callable from the PoolManager.
    /// @dev This hook is called from BaseHook library from uniswap v4.
    /// @param data The data.
    /// @return selector The selector of the unlockCallback hook to confirm the action.
    function unlockCallback(bytes calldata data) external onlyPoolManager returns (bytes memory) {
        return abi.encode(V4Liquidity.handleCallback(poolManager, data));
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
}
