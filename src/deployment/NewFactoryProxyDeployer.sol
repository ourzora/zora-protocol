// spdx-license-identifier: mit
pragma solidity ^0.8.17;

// import ownable contract from openzeppelin:
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ProxyShim} from "../utils/ProxyShim.sol";
import {Zora1155Factory} from "../proxies/Zora1155Factory.sol";

interface IUpgradeableProxy {
    function upgradeTo(address newImplementation) external;

    function initialize(address newOwner) external;
}

contract NewFactoryProxyDeployer is Ownable {
    constructor(address owner) {
        _transferOwnership(owner);
    }

    error FactoryProxyAddressMismatch(address expected, address actual);

    /// Creates a new factory proxy at a determinstic address, with this address as the owner
    /// Upgrades the proxy to the factory implementation, and sets the new owner as the owner.
    /// @param proxyShimSalt Salt for deterministic proxy shim address
    /// @param factoryProxySalt Salt for deterministic factory proxy address
    function createAndInitializeNewFactoryProxyDeterminstic(
        bytes32 proxyShimSalt,
        bytes32 factoryProxySalt,
        address expectedFactoryProxyAddress,
        address factoryImplAddress,
        address newOwner
    ) external onlyOwner returns (address factoryProxyAddress) {
        // create proxy shim and factory proxy deterministically
        ProxyShim proxyShim = new ProxyShim{salt: proxyShimSalt}({_canUpgrade: address(this)});
        Zora1155Factory factoryProxy = new Zora1155Factory{salt: factoryProxySalt}(address(proxyShim), "");

        if (address(factoryProxy) != expectedFactoryProxyAddress) {
            revert FactoryProxyAddressMismatch(expectedFactoryProxyAddress, address(factoryProxy));
        }

        factoryProxyAddress = address(factoryProxy);
        IUpgradeableProxy proxy = IUpgradeableProxy(address(factoryProxy));
        proxy.upgradeTo(factoryImplAddress);
        proxy.initialize(newOwner);

        return factoryProxyAddress;
    }
}
