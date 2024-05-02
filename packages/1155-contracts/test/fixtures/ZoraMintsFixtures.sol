// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import {MockMintsManager} from "../mock/MockMints.sol";

library ZoraMintsFixtures {
    function createMockMints(uint256 initialTokenId, uint256 initialTokenPrice) internal returns (MockMintsManager) {
        // initialize to a dummy address, we will set the logic address later with upgradeToAndcall
        return new MockMintsManager(initialTokenId, initialTokenPrice);
    }
}
