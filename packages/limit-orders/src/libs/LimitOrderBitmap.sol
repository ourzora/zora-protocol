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

    function getExecutableTicks(
        mapping(int16 => uint256) storage bm,
        mapping(int24 => LimitOrderTypes.Queue) storage poolQueue,
        int24 tickSpacing,
        bool zeroForOne,
        int24 tickBeforeSwap,
        int24 tickAfterSwap
    ) internal view returns (int24[] memory) {
        uint256 numTicksCrossed = uint256(int256(_abs(tickBeforeSwap - tickAfterSwap)));
        uint256 numTicksToCheck = numTicksCrossed / uint256(int256(tickSpacing)) + 1;

        int24[] memory ticksToCheck = new int24[](numTicksToCheck);
        uint256 numExecutableTicks;

        int24 targetTick = tickAfterSwap;
        int24 currentTick = tickBeforeSwap;

        while (true) {
            if (zeroForOne ? currentTick <= targetTick : currentTick >= targetTick) {
                break;
            }

            (int24 nextInitializedTick, bool initialized) = TickBitmap.nextInitializedTickWithinOneWord(bm, currentTick, tickSpacing, zeroForOne);

            bool crossesTarget = zeroForOne ? nextInitializedTick <= targetTick : nextInitializedTick > targetTick;

            if (crossesTarget) {
                nextInitializedTick = targetTick;
                initialized = false;
            }

            if (initialized) {
                if (poolQueue[nextInitializedTick].length > 0) {
                    ticksToCheck[numExecutableTicks++] = nextInitializedTick;
                }
            }

            if (nextInitializedTick == targetTick) {
                break;
            }

            currentTick = zeroForOne ? nextInitializedTick - 1 : nextInitializedTick;
        }

        assembly {
            mstore(ticksToCheck, numExecutableTicks)
        }

        return ticksToCheck;
    }

    function _abs(int24 x) private pure returns (int24) {
        return x < 0 ? -x : x;
    }
}
