// SPDX-License-Identifier: ZORA-DELAYED-OSL-v1
// This software is licensed under the Zora Delayed Open Source License.
// Under this license, you may use, copy, modify, and distribute this software for
// non-commercial purposes only. Commercial use and competitive products are prohibited
// until the "Open Date" (3 years from first public distribution or earlier at Zora's discretion),
// at which point this software automatically becomes available under the MIT License.
// Full license terms available at: https://docs.zora.co/coins/license
pragma solidity ^0.8.23;

import {LimitOrderTypes} from "./LimitOrderTypes.sol";

library LimitOrderQueues {
    using LimitOrderQueues for LimitOrderTypes.Queue;

    // Slot offsets for doubly-linked list pointers in LimitOrder struct
    uint256 private constant NEXT_SLOT = 0;
    uint256 private constant PREV_SLOT = 1;

    /// @notice Appends an order to the tail of a tick's order queue
    function enqueue(LimitOrderTypes.Queue storage q, mapping(bytes32 => LimitOrderTypes.LimitOrder) storage orders, bytes32 id) internal {
        bytes32 tail = q.tail;

        if (tail == bytes32(0)) {
            // Empty tick queue: new order becomes head
            q.head = id;
        } else {
            // Link current tail to new order
            _writePointer(orders, tail, NEXT_SLOT, id);
        }

        // Link new order back to old tail (or 0 if empty)
        _writePointer(orders, id, PREV_SLOT, tail);
        q.tail = id;

        unchecked {
            q.length++;
        }
    }

    /// @notice Removes an order from a tick's queue and relinks its neighbors
    /// @return nextId The next order in the queue (for iteration during fills)
    function unlink(
        LimitOrderTypes.Queue storage q,
        mapping(bytes32 => LimitOrderTypes.LimitOrder) storage orders,
        LimitOrderTypes.LimitOrder storage order
    ) internal returns (bytes32 nextId) {
        bytes32 prevId;
        uint256 baseSlot;

        // Read prev/next pointers directly from storage slots for gas efficiency
        assembly ("memory-safe") {
            // Get the base storage slot for this order struct
            baseSlot := order.slot
            // Load nextId from slot 0 (first field in struct)
            nextId := sload(add(baseSlot, NEXT_SLOT))
            // Load prevId from slot 1 (second field in struct)
            prevId := sload(add(baseSlot, PREV_SLOT))
        }

        // Relink previous order (or update head if this was first)
        if (prevId == bytes32(0)) {
            q.head = nextId;
        } else {
            _writePointer(orders, prevId, NEXT_SLOT, nextId);
        }

        // Relink next order (or update tail if this was last)
        if (nextId == bytes32(0)) {
            q.tail = prevId;
        } else {
            _writePointer(orders, nextId, PREV_SLOT, prevId);
        }

        if (q.length > 0) {
            unchecked {
                q.length--;
            }
        }
    }

    /// @notice Clears the linked list pointers of an order after removal
    function clearLinks(LimitOrderTypes.LimitOrder storage order) internal {
        uint256 baseSlot;
        assembly ("memory-safe") {
            baseSlot := order.slot
            sstore(add(baseSlot, NEXT_SLOT), 0)
            sstore(add(baseSlot, PREV_SLOT), 0)
        }
    }

    /// @notice Writes a pointer value to a specific slot offset in an order
    function _writePointer(mapping(bytes32 => LimitOrderTypes.LimitOrder) storage orders, bytes32 id, uint256 slotOffset, bytes32 value) private {
        assembly ("memory-safe") {
            // Compute storage slot: keccak256(id . orders.slot) + slotOffset
            mstore(0x00, id) // Store id at memory[0:32]
            mstore(0x20, orders.slot) // Store mapping slot at memory[32:64]
            let base := keccak256(0x00, 0x40)
            sstore(add(base, slotOffset), value)
        }
    }
}
