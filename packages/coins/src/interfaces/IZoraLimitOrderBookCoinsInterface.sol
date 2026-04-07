// SPDX-License-Identifier: ZORA-DELAYED-OSL-v1
// This software is licensed under the Zora Delayed Open Source License.
// Under this license, you may use, copy, modify, and distribute this software for
// non-commercial purposes only. Commercial use and competitive products are prohibited
// until the "Open Date" (3 years from first public distribution or earlier at Zora's discretion),
// at which point this software automatically becomes available under the MIT License.
// Full license terms available at: https://docs.zora.co/coins/license
pragma solidity ^0.8.23;

import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";

interface IZoraLimitOrderBookCoinsInterface {
    /// @notice Fills limit orders within a tick window.
    /// @param key Pool key whose orders should be processed.
    /// @param isCurrency0 Whether currency0 orders are targeted; otherwise currency1.
    /// @param startTick Inclusive starting tick. Use `-type(int24).max` for the default lower bound.
    /// @param endTick Inclusive ending tick. Use `type(int24).max` for the default upper bound.
    /// @param maxFillCount Maximum orders to fill in this pass.
    /// @param fillReferral Address to receive accrued LP fees; use address(0) to give fees to maker.
    function fill(PoolKey calldata key, bool isCurrency0, int24 startTick, int24 endTick, uint256 maxFillCount, address fillReferral) external;
}
