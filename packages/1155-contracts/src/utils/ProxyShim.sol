// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import {UUPSUpgradeable} from "@zoralabs/openzeppelin-contracts-upgradeable/contracts/proxy/utils/UUPSUpgradeable.sol";

/// Used to deploy the factory before we know the impl address
contract ProxyShim is UUPSUpgradeable {
    address immutable canUpgrade;

    constructor(address _canUpgrade) {
        canUpgrade = _canUpgrade;
    }

    function _authorizeUpgrade(address) internal view override {
        require(msg.sender == canUpgrade, "not authorized");
    }
}
