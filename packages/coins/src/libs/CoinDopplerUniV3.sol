// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {TickMath} from "../utils/uniswap/TickMath.sol";
import {CoinConfigurationVersions} from "./CoinConfigurationVersions.sol";
import {ICoin} from "../interfaces/ICoin.sol";
import {LpPosition} from "../types/LpPosition.sol";
import {MarketConstants} from "./MarketConstants.sol";
import {FullMath} from "../utils/uniswap/FullMath.sol";
import {SqrtPriceMath} from "../utils/uniswap/SqrtPriceMath.sol";
import {LiquidityAmounts} from "../utils/uniswap/LiquidityAmounts.sol";
import {IDopplerErrors} from "../interfaces/IDopplerErrors.sol";
import {DopplerMath} from "./DopplerMath.sol";
import {PoolConfiguration} from "../types/PoolConfiguration.sol";

library CoinDopplerUniV3 {
    function setupPool(bool isCoinToken0, bytes memory poolConfig_) internal pure returns (uint160 sqrtPriceX96, PoolConfiguration memory poolConfiguration) {
        (, , int24 tickLower_, int24 tickUpper_, uint16 numDiscoveryPositions_, uint256 maxDiscoverySupplyShare_) = CoinConfigurationVersions
            .decodeDopplerUniV3(poolConfig_);

        require(numDiscoveryPositions_ > 1 && numDiscoveryPositions_ <= 200, IDopplerErrors.NumDiscoveryPositionsOutOfRange());

        if (maxDiscoverySupplyShare_ > MarketConstants.WAD) {
            revert IDopplerErrors.MaxShareToBeSoldExceeded(maxDiscoverySupplyShare_, MarketConstants.WAD);
        }

        uint256[] memory maxDiscoverySupplyShare = new uint256[](1);
        uint16[] memory numDiscoveryPositions = new uint16[](1);
        int24[] memory savedTickLower = new int24[](1);
        int24[] memory savedTickUpper = new int24[](1);

        maxDiscoverySupplyShare[0] = maxDiscoverySupplyShare_;
        numDiscoveryPositions[0] = numDiscoveryPositions_;
        savedTickLower[0] = isCoinToken0 ? tickLower_ : -tickUpper_;
        savedTickUpper[0] = isCoinToken0 ? tickUpper_ : -tickLower_;

        sqrtPriceX96 = TickMath.getSqrtPriceAtTick(isCoinToken0 ? savedTickLower[0] : savedTickUpper[0]);

        poolConfiguration = PoolConfiguration({
            version: CoinConfigurationVersions.DOPPLER_UNI_V3_POOL_VERSION,
            fee: MarketConstants.LP_FEE,
            tickSpacing: MarketConstants.TICK_SPACING,
            tickLower: savedTickLower,
            tickUpper: savedTickUpper,
            numPositions: numDiscoveryPositions_ + 1, // Add one for the final tail position
            maxDiscoverySupplyShare: maxDiscoverySupplyShare,
            numDiscoveryPositions: numDiscoveryPositions
        });
    }
}
