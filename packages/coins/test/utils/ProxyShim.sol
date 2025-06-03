// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";

/// Used to deploy the factory before we know the impl address
contract ProxyShim is UUPSUpgradeable {
    address immutable canUpgrade;

    constructor() {
        canUpgrade = msg.sender;
    }

    function _authorizeUpgrade(address) internal view override {
        require(msg.sender == canUpgrade, "not authorized");
    }
}
