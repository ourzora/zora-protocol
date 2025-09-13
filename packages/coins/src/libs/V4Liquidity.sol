// SPDX-License-Identifier: ZORA-DELAYED-OSL-v1
// This software is licensed under the Zora Delayed Open Source License.
// Under this license, you may use, copy, modify, and distribute this software for
// non-commercial purposes only. Commercial use and competitive products are prohibited
// until the "Open Date" (3 years from first public distribution or earlier at Zora's discretion),
// at which point this software automatically becomes available under the MIT License.
// Full license terms available at: https://docs.zora.co/coins/license
pragma solidity ^0.8.23;

import {TickMath} from "@uniswap/v4-core/src/libraries/TickMath.sol";
import {SqrtPriceMath} from "@uniswap/v4-core/src/libraries/SqrtPriceMath.sol";
import {FullMath} from "@uniswap/v4-core/src/libraries/FullMath.sol";
import {IUnlockCallback} from "@uniswap/v4-core/src/interfaces/callback/IUnlockCallback.sol";
import {IPoolManager, PoolKey, IHooks, ModifyLiquidityParams, BalanceDelta} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {StateLibrary} from "@uniswap/v4-core/src/libraries/StateLibrary.sol";
import {BalanceDeltaLibrary} from "@uniswap/v4-core/src/types/BalanceDelta.sol";
import {TransientStateLibrary} from "@uniswap/v4-core/src/libraries/TransientStateLibrary.sol";
import {Currency, CurrencyLibrary} from "@uniswap/v4-core/src/types/Currency.sol";
import {LpPosition} from "../types/LpPosition.sol";
import {SafeCast} from "@uniswap/v4-core/src/libraries/SafeCast.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC165} from "@openzeppelin/contracts/utils/introspection/IERC165.sol";
import {SwapParams} from "@uniswap/v4-core/src/types/PoolOperation.sol";
import {IHasRewardsRecipients} from "../interfaces/ICoin.sol";
import {IHasSwapPath} from "../interfaces/ICoin.sol";
import {UniV4SwapToCurrency} from "./UniV4SwapToCurrency.sol";
import {PathKey} from "@uniswap/v4-periphery/src/libraries/PathKey.sol";
import {Position} from "@uniswap/v4-core/src/libraries/Position.sol";
import {BurnedPosition, Delta, MigratedLiquidityResult, IUpgradeableV4Hook} from "../interfaces/IUpgradeableV4Hook.sol";
import {PoolStateReader} from "../libs/PoolStateReader.sol";
import {IUpgradeableDestinationV4Hook} from "../interfaces/IUpgradeableV4Hook.sol";
import {LiquidityAmounts} from "../utils/uniswap/LiquidityAmounts.sol";

// command = 1; mint
struct MintCallbackData {
    PoolKey poolKey;
    LpPosition[] positions;
}

struct BurnAllPositionsCallbackData {
    PoolKey poolKey;
    LpPosition[] positions;
    address coin;
    address newHook;
}

library V4Liquidity {
    using BalanceDeltaLibrary for BalanceDelta;
    using CurrencyLibrary for Currency;

    uint8 constant MINT_CALLBACK_ID = 1;
    uint8 constant BURN_ALL_POSITIONS_CALLBACK_ID = 2;

    error InvalidCallbackId(uint8 callbackId);

    /// @notice Locks the pool, and mint initial positions to the hook
    /// @param poolManager The pool manager.
    /// @param poolKey The pool key.
    /// @param positions The positions.
    function lockAndMint(IPoolManager poolManager, PoolKey memory poolKey, LpPosition[] memory positions) internal {
        bytes memory data = abi.encode(MINT_CALLBACK_ID, abi.encode(MintCallbackData({poolKey: poolKey, positions: positions})));

        IPoolManager(poolManager).unlock(data);
    }

    /// @notice Locks the pool, burns positions, and transfers deltas to the new hook
    function lockAndMigrate(
        IPoolManager poolManager,
        PoolKey memory poolKey,
        LpPosition[] memory positions,
        address coin,
        address newHook,
        bytes calldata additionalData
    ) internal returns (PoolKey memory) {
        bytes memory data = abi.encode(
            BURN_ALL_POSITIONS_CALLBACK_ID,
            abi.encode(BurnAllPositionsCallbackData({poolKey: poolKey, positions: positions, coin: coin, newHook: newHook}))
        );

        // lock the pool and burn positions - this hook will then have a balance of the deltas
        bytes memory result = IPoolManager(poolManager).unlock(data);

        MigratedLiquidityResult memory migratedLiquidityResult = abi.decode(result, (MigratedLiquidityResult));

        // Check if new hook supports the upgradeable destination interface
        require(IERC165(newHook).supportsInterface(type(IUpgradeableDestinationV4Hook).interfaceId), IUpgradeableV4Hook.InvalidNewHook(newHook));
        // Initialize new hook with migration data
        IUpgradeableDestinationV4Hook(address(newHook)).initializeFromMigration(
            poolKey,
            coin,
            migratedLiquidityResult.sqrtPriceX96,
            migratedLiquidityResult.burnedPositions,
            additionalData
        );

        return
            PoolKey({currency0: poolKey.currency0, currency1: poolKey.currency1, fee: poolKey.fee, tickSpacing: poolKey.tickSpacing, hooks: IHooks(newHook)});
    }

    /// @notice Handles the callback from the pool manager.  Called by the hook upon unlock.
    function handleCallback(IPoolManager poolManager, bytes memory data) internal returns (bytes memory) {
        (uint8 callbackId, bytes memory contents) = abi.decode(data, (uint8, bytes));

        if (callbackId == MINT_CALLBACK_ID) {
            _handleMintPositionsCallback(poolManager, abi.decode(contents, (MintCallbackData)));
            return bytes("");
        }
        if (callbackId == BURN_ALL_POSITIONS_CALLBACK_ID) {
            return _handleBurnAllPositionsCallback(poolManager, abi.decode(contents, (BurnAllPositionsCallbackData)));
        }
        revert InvalidCallbackId(callbackId);
    }

    function _handleMintPositionsCallback(IPoolManager poolManager, MintCallbackData memory callbackData) private {
        mintPositions(poolManager, callbackData.poolKey, callbackData.positions);

        _settleUp(poolManager, callbackData.poolKey);
    }

    function _handleBurnAllPositionsCallback(IPoolManager poolManager, BurnAllPositionsCallbackData memory callbackData) private returns (bytes memory) {
        uint160 sqrtPriceX96 = PoolStateReader.getSqrtPriceX96(callbackData.poolKey, poolManager);
        BurnedPosition[] memory burnedPositions = burnPositions(poolManager, callbackData.poolKey, callbackData.positions);

        int256 deltas0 = TransientStateLibrary.currencyDelta(poolManager, address(this), callbackData.poolKey.currency0);
        int256 deltas1 = TransientStateLibrary.currencyDelta(poolManager, address(this), callbackData.poolKey.currency1);

        // settle deltas, transferring the balance to destination hook contract
        _settleDeltas(poolManager, callbackData.poolKey, deltas0, deltas1, callbackData.newHook);

        // transfer deltas to the new hook
        MigratedLiquidityResult memory result = MigratedLiquidityResult({
            sqrtPriceX96: sqrtPriceX96,
            burnedPositions: burnedPositions,
            totalAmount0: uint256(deltas0),
            totalAmount1: uint256(deltas1)
        });

        return abi.encode(result);
    }

    function generatePositionsFromMigratedLiquidity(
        uint160 sqrtPriceX96,
        BurnedPosition[] calldata migratedLiquidity
    ) internal pure returns (LpPosition[] memory positions) {
        positions = new LpPosition[](migratedLiquidity.length);

        for (uint256 i = 0; i < migratedLiquidity.length; i++) {
            uint128 liquidity = LiquidityAmounts.getLiquidityForAmounts(
                sqrtPriceX96,
                TickMath.getSqrtPriceAtTick(migratedLiquidity[i].tickLower),
                TickMath.getSqrtPriceAtTick(migratedLiquidity[i].tickUpper),
                migratedLiquidity[i].amount0Received,
                migratedLiquidity[i].amount1Received
            );
            positions[i] = LpPosition({liquidity: liquidity, tickLower: migratedLiquidity[i].tickLower, tickUpper: migratedLiquidity[i].tickUpper});
        }
    }

    function collectFees(IPoolManager poolManager, PoolKey memory poolKey, LpPosition[] storage positions) internal returns (int128 balance0, int128 balance1) {
        ModifyLiquidityParams memory params;
        uint256 numPositions = positions.length;

        for (uint256 i; i < numPositions; i++) {
            // if there is no liquidity, skip
            uint128 liquidity = getLiquidity(poolManager, address(this), poolKey, positions[i].tickLower, positions[i].tickUpper);
            if (liquidity == 0) {
                continue;
            }

            // skip lps with no fees to collect
            (uint256 feeGrowthInside0DeltaX128, uint256 feeGrowthInside1DeltaX128) = getFeeGrowth(poolManager, poolKey, positions[i]);
            if (feeGrowthInside0DeltaX128 == 0 && feeGrowthInside1DeltaX128 == 0) {
                continue;
            }

            params = ModifyLiquidityParams({
                tickLower: positions[i].tickLower,
                tickUpper: positions[i].tickUpper,
                liquidityDelta: 0, // only collect
                salt: 0
            });

            (, BalanceDelta feesDelta) = poolManager.modifyLiquidity(poolKey, params, "");

            // check if there is enough erc20 balance for each token to take the fees
            balance0 += feesDelta.amount0();
            balance1 += feesDelta.amount1();
        }
    }

    function burnPositions(
        IPoolManager poolManager,
        PoolKey memory poolKey,
        LpPosition[] memory positions
    ) internal returns (BurnedPosition[] memory burnedPositions) {
        burnedPositions = new BurnedPosition[](positions.length);

        for (uint256 i; i < positions.length; i++) {
            uint128 liquidity = getLiquidity(poolManager, address(this), poolKey, positions[i].tickLower, positions[i].tickUpper);

            ModifyLiquidityParams memory params = ModifyLiquidityParams({
                tickLower: positions[i].tickLower,
                tickUpper: positions[i].tickUpper,
                liquidityDelta: -SafeCast.toInt256(liquidity),
                salt: 0
            });

            (BalanceDelta liquidityDelta, BalanceDelta feesAccrued) = poolManager.modifyLiquidity(poolKey, params, "");

            burnedPositions[i] = BurnedPosition({
                tickLower: positions[i].tickLower,
                tickUpper: positions[i].tickUpper,
                amount0Received: uint128(liquidityDelta.amount0() + feesAccrued.amount0()),
                amount1Received: uint128(liquidityDelta.amount1() + feesAccrued.amount1())
            });
        }
    }

    function getLiquidity(
        IPoolManager poolManager,
        address owner,
        PoolKey memory poolKey,
        int24 tickLower,
        int24 tickUpper
    ) internal view returns (uint128 liquidity) {
        bytes32 positionId = Position.calculatePositionKey(owner, tickLower, tickUpper, bytes32(0));
        liquidity = StateLibrary.getPositionLiquidity(poolManager, poolKey.toId(), positionId);
    }

    function getFeeGrowth(
        IPoolManager poolManager,
        PoolKey memory poolKey,
        LpPosition memory position
    ) private view returns (uint256 feeGrowthInside0DeltaX128, uint256 feeGrowthInside1DeltaX128) {
        (, uint256 feeGrowthInside0LastX128, uint256 feeGrowthInside1LastX128) = StateLibrary.getPositionInfo(
            poolManager,
            poolKey.toId(),
            address(this),
            position.tickLower,
            position.tickUpper,
            bytes32(0)
        );
        (uint256 feeGrowthInside0X128, uint256 feeGrowthInside1X128) = StateLibrary.getFeeGrowthInside(
            poolManager,
            poolKey.toId(),
            position.tickLower,
            position.tickUpper
        );

        feeGrowthInside0DeltaX128 = feeGrowthInside0X128 - feeGrowthInside0LastX128;
        feeGrowthInside1DeltaX128 = feeGrowthInside1X128 - feeGrowthInside1LastX128;
    }

    function mintPositions(IPoolManager poolManager, PoolKey memory poolKey, LpPosition[] memory positions) internal returns (int128 amount0, int128 amount1) {
        ModifyLiquidityParams memory params;
        uint256 numPositions = positions.length;

        for (uint256 i; i < numPositions; i++) {
            params = ModifyLiquidityParams({
                tickLower: positions[i].tickLower,
                tickUpper: positions[i].tickUpper,
                liquidityDelta: SafeCast.toInt256(positions[i].liquidity),
                salt: 0
            });

            (BalanceDelta delta, ) = poolManager.modifyLiquidity(poolKey, params, "");

            amount0 += delta.amount0();
            amount1 += delta.amount1();
        }
    }

    function _settleUp(IPoolManager poolManager, PoolKey memory poolKey) private returns (int256 currency0Delta, int256 currency1Delta) {
        // calculate the current deltas
        currency0Delta = TransientStateLibrary.currencyDelta(poolManager, address(this), poolKey.currency0);
        currency1Delta = TransientStateLibrary.currencyDelta(poolManager, address(this), poolKey.currency1);

        _settleDeltas(poolManager, poolKey, currency0Delta, currency1Delta, address(this));
    }

    function _settleDeltas(IPoolManager poolManager, PoolKey memory poolKey, int256 currency0Delta, int256 currency1Delta, address to) private {
        if (currency0Delta > 0) {
            poolManager.take(poolKey.currency0, to, uint256(currency0Delta));
        }

        if (currency1Delta > 0) {
            poolManager.take(poolKey.currency1, to, uint256(currency1Delta));
        }

        if (currency0Delta < 0) {
            poolManager.sync(poolKey.currency0);
            poolKey.currency0.transfer(address(poolManager), uint256(-currency0Delta));
            poolManager.settle();
        }

        if (currency1Delta < 0) {
            poolManager.sync(poolKey.currency1);
            poolKey.currency1.transfer(address(poolManager), uint256(-currency1Delta));
            poolManager.settle();
        }
    }
}
