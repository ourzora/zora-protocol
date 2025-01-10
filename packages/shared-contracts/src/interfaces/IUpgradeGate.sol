// SPDX-License-Identifier: MIT
pragma solidity >=0.8.17;

/// @notice Factory Upgrade Gate Admin Factory Implementation – Allows specific contract upgrades as a safety measure
interface IUpgradeGate {
    function contractName() external view returns (string memory);

    function contractURI() external view returns (string memory);

    /// @notice If an implementation is registered by the Builder DAO as an optional upgrade
    /// @param baseImpl The base implementation address
    /// @param upgradeImpl The upgrade implementation address
    function isRegisteredUpgradePath(address baseImpl, address upgradeImpl) external view returns (bool);

    /// @notice Called by the Builder DAO to offer implementation upgrades for created DAOs
    /// @param baseImpls The base implementation addresses
    /// @param upgradeImpl The upgrade implementation address
    function registerUpgradePath(address[] memory baseImpls, address upgradeImpl) external;

    /// @notice Called by the Builder DAO to remove an upgrade
    /// @param baseImpl The base implementation address
    /// @param upgradeImpl The upgrade implementation address
    function removeUpgradePath(address baseImpl, address upgradeImpl) external;

    event UpgradeRegistered(address indexed baseImpl, address indexed upgradeImpl);
    event UpgradeRemoved(address indexed baseImpl, address indexed upgradeImpl);
}
