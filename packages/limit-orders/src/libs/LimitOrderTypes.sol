// SPDX-License-Identifier: ZORA-DELAYED-OSL-v1
// This software is licensed under the Zora Delayed Open Source License.
// Under this license, you may use, copy, modify, and distribute this software for
// non-commercial purposes only. Commercial use and competitive products are prohibited
// until the "Open Date" (3 years from first public distribution or earlier at Zora's discretion),
// at which point this software automatically becomes available under the MIT License.
// Full license terms available at: https://docs.zora.co/coins/license
pragma solidity ^0.8.23;

interface LimitOrderTypes {
    enum OrderStatus {
        INACTIVE,
        OPEN,
        FILLED
    }

    struct LimitOrder {
        // Linked-list pointers
        bytes32 nextId;
        bytes32 prevId;
        // Pool binding
        bytes32 poolKeyHash;
        // Amounts (packed)
        uint128 orderSize;
        uint128 liquidity;
        // Small fields + address (packed into one slot)
        int24 tickLower;
        int24 tickUpper;
        uint32 createdEpoch;
        OrderStatus status;
        bool isCurrency0;
        address maker;
    }

    struct Queue {
        bytes32 head;
        bytes32 tail;
        uint128 length;
        uint128 balance;
    }
}
