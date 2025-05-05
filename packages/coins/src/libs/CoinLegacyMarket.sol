// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IUniswapV3Factory} from "../interfaces/IUniswapV3Factory.sol";
import {IUniswapV3Pool} from "../interfaces/IUniswapV3Pool.sol";
import {ISwapRouter} from "../interfaces/ISwapRouter.sol";
import {PoolConfiguration, ICoin} from "../interfaces/ICoin.sol";
import {TickMath} from "../utils/uniswap/TickMath.sol";
import {MarketConstants} from "./MarketConstants.sol";
import {LiquidityAmounts} from "../utils/uniswap/LiquidityAmounts.sol";
import {LpPosition} from "../types/LpPosition.sol";
import {CoinConfigurationVersions} from "./CoinConfigurationVersions.sol";
import {UniV3Errors} from "./UniV3Errors.sol";

library CoinLegacyMarket {
    struct State {
        address uniswapv3Factory;
        address poolAddress;
        address pairedCurrency;
        address weth;
        uint160 sqrtPriceX96;
        bool isCoinToken0;
        int24 tickLower;
        int24 tickUpper;
    }

    struct MarketConfig {
        address uniswapv3Factory;
        address weth;
        address pairedCurrency;
        int24 tickLower;
    }

    function _validateMarketConfig(MarketConfig memory marketConfig) internal pure {
        if (marketConfig.uniswapv3Factory == address(0)) {
            revert UniV3Errors.InvalidUniswapV3Factory();
        }

        if (marketConfig.weth == address(0)) {
            revert UniV3Errors.InvalidWeth();
        }

        // TODO: validate tickLower
    }

    function setupMarket(bytes memory _state, bytes memory _marketConfig) internal returns (bytes memory) {
        State memory state = abi.decode(_state, (State));
        MarketConfig memory marketConfig = abi.decode(_marketConfig, (MarketConfig));
        _validateMarketConfig(marketConfig);

        state.uniswapv3Factory = marketConfig.uniswapv3Factory;
        state.weth = marketConfig.weth;
        state.tickLower = marketConfig.tickLower;

        // If the pairedCurrency is not set, default to WETH
        if (marketConfig.pairedCurrency == address(0)) {
            state.pairedCurrency = marketConfig.weth;
        } else {
            state.pairedCurrency = marketConfig.pairedCurrency;
        }

        address pairedCurrency = state.pairedCurrency;
        int24 tickLower = state.tickLower;

        // Compute and store the pool configuration
        address token0 = address(this) < pairedCurrency ? address(this) : pairedCurrency;
        address token1 = address(this) < pairedCurrency ? pairedCurrency : address(this);
        
        bool isCoinToken0 = token0 == address(this);
        state.isCoinToken0 = isCoinToken0;
        

        if ((pairedCurrency == state.weth || pairedCurrency == address(0)) && tickLower > MarketConstants.LP_TICK_LOWER_WETH) {
            revert UniV3Errors.InvalidTickLower();
        }

        int24 savedTickLower = isCoinToken0 ? tickLower : -MarketConstants.LP_TICK_UPPER;
        int24 savedTickUpper = isCoinToken0 ? MarketConstants.LP_TICK_UPPER : -tickLower;

        state.sqrtPriceX96 = TickMath.getSqrtPriceAtTick(isCoinToken0 ? savedTickLower : savedTickUpper);
        state.tickLower = savedTickLower;
        state.tickUpper = savedTickUpper;


        // Deploy the pool
        state.poolAddress = _createPool(token0, token1, state.uniswapv3Factory, state.sqrtPriceX96);

        // Mint the positions
        uint160 farSqrtPriceX96 = TickMath.getSqrtPriceAtTick(isCoinToken0 ? savedTickUpper : savedTickLower);
        uint128 liquidity = isCoinToken0
            ? LiquidityAmounts.getLiquidityForAmount0(state.sqrtPriceX96, farSqrtPriceX96, MarketConstants.POOL_LAUNCH_SUPPLY)
            : LiquidityAmounts.getLiquidityForAmount1(state.sqrtPriceX96, farSqrtPriceX96, MarketConstants.POOL_LAUNCH_SUPPLY);
        
        IUniswapV3Pool(state.poolAddress).mint(address(this), state.tickLower, state.tickUpper, liquidity, "");

        return abi.encode(state);
    }


    function buy(bytes memory _state, address recipient, uint256 orderSize, uint256 minAmountOut, bytes memory tradeData) internal returns (uint256, uint256) {
        State memory state = abi.decode(_state, (State));
        (uint160 sqrtPriceLimitX96, address swapRouter) = abi.decode(tradeData, (uint160, address));

        ISwapRouter.ExactInputSingleParams memory params = ISwapRouter.ExactInputSingleParams({
            tokenIn: state.pairedCurrency,
            tokenOut: address(this),
            fee: MarketConstants.LP_FEE,
            recipient: recipient,
            amountIn: orderSize,
            amountOutMinimum: minAmountOut,
            sqrtPriceLimitX96: sqrtPriceLimitX96
        });

        uint256 amountOut = ISwapRouter(swapRouter).exactInputSingle(params);

        return (orderSize, amountOut);
    }

    function sell(bytes memory _state, uint256 orderSize, uint256 minAmountOut, bytes memory tradeData) internal returns (uint256, uint256) {
        State memory state = abi.decode(_state, (State));
        (uint160 sqrtPriceLimitX96, address swapRouter) = abi.decode(tradeData, (uint160, address));

        // Approve the swap router to spend the coin
        IERC20(address(this)).approve(swapRouter, orderSize);

        // Set the swap parameters
        ISwapRouter.ExactInputSingleParams memory params = ISwapRouter.ExactInputSingleParams({
            tokenIn: address(this),
            tokenOut: state.pairedCurrency,
            fee: MarketConstants.LP_FEE,
            recipient: address(this),
            amountIn: orderSize,
            amountOutMinimum: minAmountOut,
            sqrtPriceLimitX96: sqrtPriceLimitX96
        });

        // Execute the swap
        uint256 amountOut = ISwapRouter(swapRouter).exactInputSingle(params);

        return (orderSize, amountOut);
    }

    function _createPool(address token0, address token1, address uniswapv3Factory, uint160 sqrtPriceX96) internal returns (address pool) {
        pool = IUniswapV3Factory(uniswapv3Factory).createPool(token0, token1, MarketConstants.LP_FEE);
        IUniswapV3Pool(pool).initialize(sqrtPriceX96);

        return pool;
    }

    /// @notice deprecated
    function setupPool(
        bool isCoinToken0,
        bytes memory poolConfig_,
        address weth
    ) internal pure returns (uint160 sqrtPriceX96, PoolConfiguration memory poolConfiguration) {
        (, address currency, int24 tickLower_) = abi.decode(poolConfig_, (uint8, address, int24));

        // If WETH is the pool's currency, validate the lower tick
        if ((currency == weth || currency == address(0)) && tickLower_ > MarketConstants.LP_TICK_LOWER_WETH) {
            revert ICoin.InvalidWethLowerTick();
        }

        int24 savedTickLower = isCoinToken0 ? tickLower_ : -MarketConstants.LP_TICK_UPPER;
        int24 savedTickUpper = isCoinToken0 ? MarketConstants.LP_TICK_UPPER : -tickLower_;

        sqrtPriceX96 = TickMath.getSqrtPriceAtTick(isCoinToken0 ? savedTickLower : savedTickUpper);

        poolConfiguration = PoolConfiguration({
            version: CoinConfigurationVersions.LEGACY_POOL_VERSION,
            tickLower: savedTickLower,
            tickUpper: savedTickUpper,
            numPositions: 1,
            maxDiscoverySupplyShare: 0
        });
    }

    /// @notice deprecated
    function calculatePositions(bool isCoinToken0, PoolConfiguration memory poolConfiguration) internal pure returns (LpPosition[] memory positions) {
        positions = new LpPosition[](1);

        uint160 sqrtPriceX96 = TickMath.getSqrtPriceAtTick(isCoinToken0 ? poolConfiguration.tickLower : poolConfiguration.tickUpper);
        uint160 farSqrtPriceX96 = TickMath.getSqrtPriceAtTick(isCoinToken0 ? poolConfiguration.tickUpper : poolConfiguration.tickLower);
        uint128 liquidity = isCoinToken0
            ? LiquidityAmounts.getLiquidityForAmount0(sqrtPriceX96, farSqrtPriceX96, MarketConstants.POOL_LAUNCH_SUPPLY)
            : LiquidityAmounts.getLiquidityForAmount1(sqrtPriceX96, farSqrtPriceX96, MarketConstants.POOL_LAUNCH_SUPPLY);
        positions[0] = LpPosition({tickLower: poolConfiguration.tickLower, tickUpper: poolConfiguration.tickUpper, liquidity: liquidity});
    }
}
