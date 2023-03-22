// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import {FactoryManagedUpgradeGate} from "../../src/upgrades/FactoryManagedUpgradeGate.sol";

contract MockUpgradeGateBase is FactoryManagedUpgradeGate {
    function setup(address initialOwner) public initializer {
        __Ownable_init(initialOwner);
    }
}
