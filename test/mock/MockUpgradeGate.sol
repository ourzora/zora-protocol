// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import {FactoryManagedUpgradeGate} from "../../src/upgrades/FactoryManagedUpgradeGate.sol";

contract MockUpgradeGate is FactoryManagedUpgradeGate {
    function initialize(address _initialOwner) external {
        _transferOwnership(_initialOwner);
    }
}
