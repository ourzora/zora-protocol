// SPDX-License-Identifier: ZORA-DELAYED-OSL-v1
// This software is licensed under the Zora Delayed Open Source License.
// Under this license, you may use, copy, modify, and distribute this software for
// non-commercial purposes only. Commercial use and competitive products are prohibited
// until the "Open Date" (3 years from first public distribution or earlier at Zora's discretion),
// at which point this software automatically becomes available under the MIT License.
// Full license terms available at: https://docs.zora.co/coins/license
pragma solidity ^0.8.23;

import {TickBitmap} from "@uniswap/v4-core/src/libraries/TickBitmap.sol";
import {LimitOrderTypes} from "./LimitOrderTypes.sol";

library LimitOrderBitmap {
    function setIfFirst(mapping(int16 => uint256) storage bm, int24 tick, int24 spacing, uint256 sizeBefore) internal {
        if (sizeBefore == 0) {
            int24 compressed = TickBitmap.compress(tick, spacing);
            (int16 wordPos, uint8 bitPos) = TickBitmap.position(compressed);
            bm[wordPos] |= (1 << bitPos);
        }
    }

    function clearIfEmpty(mapping(int16 => uint256) storage bm, int24 tick, int24 spacing, uint256 sizeAfter) internal {
        if (sizeAfter == 0) {
            int24 compressed = TickBitmap.compress(tick, spacing);
            (int16 wordPos, uint8 bitPos) = TickBitmap.position(compressed);
            bm[wordPos] &= ~(1 << bitPos);
        }
    }

    function _abs(int24 x) private pure returns (int24) {
        return x < 0 ? -x : x;
    }
}
