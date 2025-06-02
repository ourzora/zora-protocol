// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {BaseHook} from "@uniswap/v4-periphery/src/utils/BaseHook.sol";
import {Hooks} from "@uniswap/v4-core/src/libraries/Hooks.sol";
import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {PoolIdLibrary} from "@uniswap/v4-core/src/types/PoolId.sol";
import {BalanceDelta, BalanceDeltaLibrary} from "@uniswap/v4-core/src/types/BalanceDelta.sol";
import {SwapParams} from "@uniswap/v4-core/src/types/PoolOperation.sol";
import {IZoraV4CoinHook, IMsgSender} from "../interfaces/IZoraV4CoinHook.sol";
import {LpPosition} from "../types/LpPosition.sol";
import {SafeCast} from "@uniswap/v4-core/src/libraries/SafeCast.sol";
import {FixedPointMathLib} from "solmate/utils/FixedPointMathLib.sol";
import {V4Liquidity} from "../libs/V4Liquidity.sol";
import {CoinRewardsV4} from "../libs/CoinRewardsV4.sol";
import {ICoinV4} from "../interfaces/ICoinV4.sol";
import {IHasRewardsRecipients} from "../interfaces/ICoin.sol";
import {Currency} from "@uniswap/v4-core/src/types/Currency.sol";
import {CoinCommon} from "../libs/CoinCommon.sol";
import {PoolConfiguration} from "../types/PoolConfiguration.sol";
import {CoinDopplerMultiCurve} from "../libs/CoinDopplerMultiCurve.sol";

contract ZoraV4CoinHook is BaseHook, IZoraV4CoinHook {
    using BalanceDeltaLibrary for BalanceDelta;

    mapping(address => bool) public isTrustedMessageSender;

    constructor(IPoolManager _poolManager, address[] memory _trustedMessageSenders) BaseHook(_poolManager) {
        for (uint256 i = 0; i < _trustedMessageSenders.length; i++) {
            isTrustedMessageSender[_trustedMessageSenders[i]] = true;
        }
    }

    bool initialized;
    error AlreadyInitialized();

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

    struct PoolCoin {
        address coin;
        LpPosition[] positions;
    }

    mapping(bytes32 => PoolCoin) public poolCoins;

    function _generatePositions(ICoinV4 coin, PoolKey memory key) internal view returns (LpPosition[] memory positions) {
        bool isCoinToken0 = Currency.unwrap(key.currency0) == address(coin);

        positions = CoinDopplerMultiCurve.calculatePositions(isCoinToken0, coin.getPoolConfiguration());
    }

    function _afterInitialize(address sender, PoolKey calldata key, uint160, int24) internal override returns (bytes4) {
        address coin = sender;
        if (!V4Liquidity.isCoin(coin)) {
            revert NotACoin(coin);
        }

        LpPosition[] memory positions = _generatePositions(ICoinV4(coin), key);

        poolCoins[CoinCommon.hashPoolKey(key)] = PoolCoin({coin: coin, positions: positions});

        V4Liquidity.lockAndMint(poolManager, key, positions);

        return BaseHook.afterInitialize.selector;
    }

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

        CoinRewardsV4.collectAndDistributeMarketRewards(poolManager, key, poolCoins[poolKeyHash].positions, hookData, ICoinV4(coin));

        {
            (address swapper, bool isTrustedSwapSenderAddress) = _getOriginalMsgSender(sender);
            bool isCoinBuy = params.zeroForOne ? Currency.unwrap(key.currency1) == address(coin) : Currency.unwrap(key.currency0) == address(coin);
            emit Swapped(sender, swapper, isTrustedSwapSenderAddress, key, poolKeyHash, params, delta.amount0(), delta.amount1(), isCoinBuy, hookData);
        }

        return (BaseHook.afterSwap.selector, 0);
    }

    function unlockCallback(bytes calldata data) external onlyPoolManager returns (bytes memory) {
        return abi.encode(V4Liquidity.handleCallback(poolManager, data));
    }

    function _getOriginalMsgSender(address sender) internal view returns (address swapper, bool senderIsTrusted) {
        senderIsTrusted = isTrustedMessageSender[sender];

        try IMsgSender(sender).msgSender() returns (address _swapper) {
            swapper = _swapper;
        } catch {}
    }
}
