// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

interface IHooksUpgradeGate {
    function isRegisteredUpgradePath(address baseImpl, address upgradeImpl) external view returns (bool);

    function registerUpgradePath(address[] memory baseImpls, address upgradeImpl) external;

    function removeUpgradePath(address baseImpl, address upgradeImpl) external;

    event UpgradeRegistered(address fromImpl, address toImpl);

    event UpgradeRemoved(address fromImpl, address toImpl);
}
