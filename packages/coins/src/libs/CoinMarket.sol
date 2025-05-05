// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {PoolConfiguration} from "../interfaces/ICoin.sol";
import {CoinLegacyMarket} from "./CoinLegacyMarket.sol";
import {CoinDopplerUniV3Market} from "./CoinDopplerUniV3Market.sol";
import {CoinConfigurationVersions} from "./CoinConfigurationVersions.sol";
import {LpPosition} from "../types/LpPosition.sol";

library CoinMarket {
    using SafeERC20 for IERC20;
    error InvalidPoolVersion();
    error InvalidMarketVersion();
    error ERC20TransferAmountMismatch();

    function setupMarket(bytes memory marketState, uint8 version, bytes memory marketConfig) internal returns (bytes memory) {
        if (version == CoinConfigurationVersions.LEGACY_POOL_VERSION) {
            return CoinLegacyMarket.setupMarket(marketState, marketConfig);
        } else if (version == CoinConfigurationVersions.DOPPLER_UNI_V3_POOL_VERSION) {
            return CoinDopplerUniV3Market.setupMarket(marketState, marketConfig);
        } else {
            revert InvalidMarketVersion();
        }
    }

    function buy(
        bytes memory _state,
        uint8 version,
        address currencyIn,
        address recipient,
        uint256 orderSize,
        uint256 minAmountOut,
        bytes memory tradeData
    ) internal returns (uint256, uint256) {
        // TODO: handle order referral rewards, market rewards, and payouts here

        _handleIncomingCurrency(currencyIn, orderSize);

        if (version == CoinConfigurationVersions.LEGACY_POOL_VERSION) {
            return CoinLegacyMarket.buy(_state, recipient, orderSize, minAmountOut, tradeData);
        } else if (version == CoinConfigurationVersions.DOPPLER_UNI_V3_POOL_VERSION) {
            return CoinDopplerUniV3Market.buy(_state, recipient, orderSize, minAmountOut, tradeData);
        } else {
            revert InvalidMarketVersion();
        }
    }

    function sell(
        bytes memory _state,
        uint8 version,
        address recipient,
        uint256 orderSize,
        uint256 minAmountOut,
        bytes memory tradeData
    ) internal returns (uint256, uint256) {
        // TODO: handle order referral rewards, market rewards, and payouts here

        if (version == CoinConfigurationVersions.LEGACY_POOL_VERSION) {
            return CoinLegacyMarket.sell(_state, orderSize, minAmountOut, tradeData);
        } else if (version == CoinConfigurationVersions.DOPPLER_UNI_V3_POOL_VERSION) {
            return CoinDopplerUniV3Market.sell(_state, orderSize, minAmountOut, tradeData);
        } else {
            revert InvalidMarketVersion();
        }
    }

    function _handleIncomingCurrency(address currencyIn, uint256 orderSize) internal {
        uint256 beforeBalance = IERC20(currencyIn).balanceOf(address(this));
        IERC20(currencyIn).safeTransferFrom(msg.sender, address(this), orderSize);
        uint256 afterBalance = IERC20(currencyIn).balanceOf(address(this));

        if ((afterBalance - beforeBalance) != orderSize) {
            revert ERC20TransferAmountMismatch();
        }
    }

    /// @notice deprecated
    function setupPoolWithVersion(
        uint8 version,
        bytes memory poolConfig_,
        bool isCoinToken0,
        address weth
    ) internal pure returns (uint160 sqrtPriceX96, PoolConfiguration memory poolConfiguration) {
        if (version == CoinConfigurationVersions.LEGACY_POOL_VERSION) {
            (sqrtPriceX96, poolConfiguration) = CoinLegacyMarket.setupPool(isCoinToken0, poolConfig_, weth);
        } else if (version == CoinConfigurationVersions.DOPPLER_UNI_V3_POOL_VERSION) {
            (sqrtPriceX96, poolConfiguration) = CoinDopplerUniV3Market.setupPool(isCoinToken0, poolConfig_);
        } else {
            revert InvalidPoolVersion();
        }
    }

    /// @notice deprecated
    function calculatePositions(bool isCoinToken0, PoolConfiguration memory poolConfiguration) internal pure returns (LpPosition[] memory positions) {
        if (poolConfiguration.version == CoinConfigurationVersions.LEGACY_POOL_VERSION) {
            positions = CoinLegacyMarket.calculatePositions(isCoinToken0, poolConfiguration);
        } else if (poolConfiguration.version == CoinConfigurationVersions.DOPPLER_UNI_V3_POOL_VERSION) {
            positions = CoinDopplerUniV3Market.calculatePositions(isCoinToken0, poolConfiguration);
        } else {
            revert InvalidPoolVersion();
        }
    }
}
