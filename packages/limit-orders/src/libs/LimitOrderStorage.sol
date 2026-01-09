// SPDX-License-Identifier: ZORA-DELAYED-OSL-v1
// This software is licensed under the Zora Delayed Open Source License.
// Under this license, you may use, copy, modify, and distribute this software for
// non-commercial purposes only. Commercial use and competitive products are prohibited
// until the "Open Date" (3 years from first public distribution or earlier at Zora's discretion),
// at which point this software automatically becomes available under the MIT License.
// Full license terms available at: https://docs.zora.co/coins/license
pragma solidity ^0.8.28;

import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {LimitOrderTypes} from "./LimitOrderTypes.sol";

library LimitOrderStorage {
    // keccak256("zora.limit.order.book.storage")
    bytes32 internal constant STORAGE_SLOT = 0x98b43bb10ca7bc310641b07883d9e14c04b3983640df6b07dd1c99d10a3c6cec;

    struct Layout {
        uint256 maxFillCount;
        mapping(bytes32 orderId => LimitOrderTypes.LimitOrder) limitOrders;
        mapping(address maker => uint256 nonce) makerNonces;
        mapping(bytes32 poolKeyHash => PoolKey) poolKeys;
        mapping(bytes32 poolKeyHash => uint256 epoch) poolEpochs;
        mapping(bytes32 poolKeyHash => mapping(address coin => mapping(int16 wordPosition => uint256 bitmap))) tickBitmaps;
        mapping(bytes32 poolKeyHash => mapping(address coin => mapping(int24 tick => LimitOrderTypes.Queue))) tickQueues;
        mapping(address maker => mapping(address coin => uint256 balance)) makerBalances;
    }

    function layout() internal pure returns (Layout storage l) {
        bytes32 slot = STORAGE_SLOT;
        assembly {
            l.slot := slot
        }
    }
}
