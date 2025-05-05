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
        address poolAddress;
        uint160 sqrtPriceX96;
        PoolConfiguration poolConfiguration;
        address pairedCurrency;
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

        address weth = marketConfig.weth;
        address currency = marketConfig.pairedCurrency;
        int24 tickLower = marketConfig.tickLower;

        // If WETH is the pool's currency, validate the lower tick
        if ((currency == weth || currency == address(0)) && tickLower > MarketConstants.LP_TICK_LOWER_WETH) {
            revert ICoin.InvalidWethLowerTick();
        }
    }

    function _isCoinToken0(address coin, address currency) internal pure returns (bool isCoinToken0, address token0, address token1) {
        token0 = coin < currency ? coin : currency;
        token1 = token1 = coin < currency ? currency : coin;
        isCoinToken0 = token0 == coin;
    }

    function setupMarket(bytes memory _marketConfig, address coin) internal returns (bytes memory) {
        MarketConfig memory marketConfig = abi.decode(_marketConfig, (MarketConfig));
        _validateMarketConfig(marketConfig);

        (bool isCoinToken0, address token0, address token1) = _isCoinToken0(coin, marketConfig.pairedCurrency);

        (uint160 sqrtPriceX96, PoolConfiguration memory poolConfiguration) = setupPool(
            isCoinToken0,
            marketConfig.pairedCurrency,
            marketConfig.tickLower,
            marketConfig.weth
        );

        address poolAddress = _createPool(token0, token1, sqrtPriceX96, marketConfig.uniswapv3Factory);

        LpPosition[] memory positions = calculatePositions(isCoinToken0, poolConfiguration);

        _mintPositions(positions, poolAddress);

        State memory state = State({
            poolAddress: poolAddress,
            sqrtPriceX96: sqrtPriceX96,
            poolConfiguration: poolConfiguration,
            pairedCurrency: marketConfig.pairedCurrency
        });

        return abi.encode(state);
    }

    function buy(bytes memory _state, address recipient, uint256 orderSize, uint256 minAmountOut, bytes memory tradeData) internal returns (uint256, uint256) {
        State memory state = abi.decode(_state, (State));
        (uint160 sqrtPriceLimitX96, address swapRouter, address tradeReferrer) = abi.decode(tradeData, (uint160, address, address));

        // Calculate the trade reward
        // uint256 tradeReward = _calculateReward(orderSize, TOTAL_FEE_BPS);

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

    /// @dev Creates the Uniswap V3 pool for the coin/currency pair
    function _createPool(address token0, address token1, uint160 sqrtPriceX96, address v3Factory) internal returns (address pool) {
        pool = IUniswapV3Factory(v3Factory).createPool(token0, token1, MarketConstants.LP_FEE);

        // This pool should be new, if it has already been initialized
        // then we will fail the creation step prompting the user to try again.
        IUniswapV3Pool(pool).initialize(sqrtPriceX96);
    }

    function setupPool(
        bool isCoinToken0,
        address currency,
        int24 tickLower_,
        address weth
    ) internal pure returns (uint160 sqrtPriceX96, PoolConfiguration memory poolConfiguration) {
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

    function calculatePositions(bool isCoinToken0, PoolConfiguration memory poolConfiguration) internal pure returns (LpPosition[] memory positions) {
        positions = new LpPosition[](1);

        uint160 sqrtPriceX96 = TickMath.getSqrtPriceAtTick(isCoinToken0 ? poolConfiguration.tickLower : poolConfiguration.tickUpper);
        uint160 farSqrtPriceX96 = TickMath.getSqrtPriceAtTick(isCoinToken0 ? poolConfiguration.tickUpper : poolConfiguration.tickLower);
        uint128 liquidity = isCoinToken0
            ? LiquidityAmounts.getLiquidityForAmount0(sqrtPriceX96, farSqrtPriceX96, MarketConstants.POOL_LAUNCH_SUPPLY)
            : LiquidityAmounts.getLiquidityForAmount1(sqrtPriceX96, farSqrtPriceX96, MarketConstants.POOL_LAUNCH_SUPPLY);
        positions[0] = LpPosition({tickLower: poolConfiguration.tickLower, tickUpper: poolConfiguration.tickUpper, liquidity: liquidity});
    }

    /// @dev Mints the calculated liquidity positions into the Uniswap V3 pool
    function _mintPositions(LpPosition[] memory lbpPositions, address poolAddress) internal {
        for (uint256 i; i < lbpPositions.length; i++) {
            IUniswapV3Pool(poolAddress).mint(address(this), lbpPositions[i].tickLower, lbpPositions[i].tickUpper, lbpPositions[i].liquidity, "");
        }
    }
}
