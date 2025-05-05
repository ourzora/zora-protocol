// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {PoolConfiguration} from "../interfaces/ICoin.sol";
import {CoinLegacyMarket} from "./CoinLegacyMarket.sol";
import {CoinDopplerUniV3Market} from "./CoinDopplerUniV3Market.sol";
import {CoinConfigurationVersions} from "./CoinConfigurationVersions.sol";
import {LpPosition} from "../types/LpPosition.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

library CoinMarket {
    using SafeERC20 for IERC20;
    error InvalidPoolVersion();
    error InvalidMarketVersion();
    error ERC20TransferAmountMismatch();
    error ETHTransferAmountMismatch();

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

        // TODO: ensure legacy buy function wraps ETH to WETH
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
        // Record the coin balance of this contract before the swap
        uint256 beforeCoinBalance = IERC20(address(this)).balanceOf(address(this));
        // Transfer the coins from the seller to this contract
        IERC20(address(this)).transferFrom(msg.sender, address(this), orderSize);

        if (version == CoinConfigurationVersions.LEGACY_POOL_VERSION) {
            return CoinLegacyMarket.sell(_state, orderSize, minAmountOut, tradeData);
        } else if (version == CoinConfigurationVersions.DOPPLER_UNI_V3_POOL_VERSION) {
            return CoinDopplerUniV3Market.sell(_state, orderSize, minAmountOut, tradeData);
        } else {
            revert InvalidMarketVersion();
        }
    }

    function _handleIncomingCurrency(address currencyIn, uint256 orderSize) internal {
        if (currencyIn == address(0)) {
            if (msg.value != orderSize) {
                revert ETHTransferAmountMismatch();
            }
        } else {
            uint256 beforeBalance = IERC20(currencyIn).balanceOf(address(this));
            IERC20(currencyIn).safeTransferFrom(msg.sender, address(this), orderSize);
            uint256 afterBalance = IERC20(currencyIn).balanceOf(address(this));

            if ((afterBalance - beforeBalance) != orderSize) {
                revert ERC20TransferAmountMismatch();
            }
        }
    }

    /// @dev Utility for computing amounts in basis points.
    function _calculateReward(uint256 amount, uint256 bps) internal pure returns (uint256) {
        return (amount * bps) / 10_000;
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
