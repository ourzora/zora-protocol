// spdx-license-identifier: mit
pragma solidity ^0.8.17;

// import ownable contract from openzeppelin:
import {ProxyShim} from "../utils/ProxyShim.sol";
import {Zora1155Factory} from "../proxies/Zora1155Factory.sol";
import {EIP712} from "@openzeppelin/contracts/utils/cryptography/EIP712.sol";
import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";

interface IUpgradeableProxy {
    function upgradeTo(address newImplementation) external;

    function initialize(address newOwner) external;
}

contract NewFactoryProxyDeployer is EIP712 {
    error FactoryProxyAddressMismatch(address expected, address actual);

    constructor() EIP712("NewFactoryProxyDeployer", "1") {}

    /// Creates a new factory proxy at a determinstic address, with this address as the owner
    /// Upgrades the proxy to the factory implementation, and sets the new owner as the owner.
    /// @param proxyShimSalt Salt for deterministic proxy shim address
    /// @param factoryProxySalt Salt for deterministic factory proxy address
    function _createNewFactoryProxyDeterminstic(
        bytes32 proxyShimSalt,
        bytes32 factoryProxySalt,
        address expectedFactoryProxyAddress
    ) internal returns (address factoryProxyAddress) {
        // create proxy shim and factory proxy deterministically
        ProxyShim proxyShim = new ProxyShim{salt: proxyShimSalt}({_canUpgrade: address(this)});
        Zora1155Factory factoryProxy = new Zora1155Factory{salt: factoryProxySalt}(address(proxyShim), "");

        if (address(factoryProxy) != expectedFactoryProxyAddress) {
            revert FactoryProxyAddressMismatch(expectedFactoryProxyAddress, address(factoryProxy));
        }

        return factoryProxyAddress;
    }

    bytes32 constant DOMAIN = keccak256("createFactoryProxy(bytes32 proxyShimSalt,bytes32 factoryProxySalt,address factoryImplAddress,address owner)");

    function recoverSignature(
        bytes32 proxyShimSalt,
        bytes32 factoryProxySalt,
        address factoryImplAddress,
        address owner,
        bytes calldata signature
    ) public view returns (address) {
        bytes32 digest = hashedDigest(proxyShimSalt, factoryProxySalt, factoryImplAddress, owner);

        return ECDSA.recover(digest, signature);
    }

    function hashedDigest(bytes32 proxyShimSalt, bytes32 factoryProxySalt, address factoryImplAddress, address newOwner) public view returns (bytes32) {
        return _hashTypedDataV4(keccak256(abi.encode(DOMAIN, proxyShimSalt, factoryProxySalt, factoryImplAddress, newOwner)));
    }

    function requireContainsCaller(address caller, bytes32 salt) private pure {
        // prevent contract submissions from being stolen from tx.pool by requiring
        // that the first 20 bytes of the submitted salt match msg.sender.
        require((address(bytes20(salt)) == caller) || (bytes20(salt) == bytes20(0)), "Invalid salt - first 20 bytes of the salt must match calling address.");
    }

    /// Creates a new factory proxy at a determinstic address, with this address as the owner
    /// Upgrades the proxy to the factory implementation, and sets the new owner as the owner.
    /// @param proxyShimSalt Salt for deterministic proxy shim address
    /// @param factoryProxySalt Salt for deterministic factory proxy address
    function createFactoryProxyDeterminstic(
        bytes32 proxyShimSalt,
        bytes32 factoryProxySalt,
        address expectedFactoryProxyAddress,
        address factoryImplAddress,
        address owner,
        bytes calldata signature
    ) external returns (address factoryProxyAddress) {
        address signer = recoverSignature(proxyShimSalt, factoryProxySalt, factoryImplAddress, owner, signature);

        requireContainsCaller(signer, proxyShimSalt);

        return _createNewFactoryProxyDeterminstic(proxyShimSalt, factoryProxySalt, expectedFactoryProxyAddress);
    }

    /// Creates a new factory proxy at a determinstic address, with this address as the owner
    /// Upgrades the proxy to the factory implementation, and sets the new owner as the owner.
    /// @param proxyShimSalt Salt for deterministic proxy shim address
    /// @param factoryProxySalt Salt for deterministic factory proxy address
    function initializeFactoryProxy(
        bytes32 proxyShimSalt,
        bytes32 factoryProxySalt,
        address expectedFactoryProxyAddress,
        address factoryImplAddress,
        address owner,
        bytes calldata signature
    ) external {
        address signer = recoverSignature(proxyShimSalt, factoryProxySalt, factoryImplAddress, owner, signature);

        requireContainsCaller(signer, proxyShimSalt);

        IUpgradeableProxy proxy = IUpgradeableProxy(address(expectedFactoryProxyAddress));
        proxy.upgradeTo(factoryImplAddress);
        proxy.initialize(owner);
    }
}
