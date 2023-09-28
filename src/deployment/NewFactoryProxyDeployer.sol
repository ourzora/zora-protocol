// spdx-license-identifier: mit
pragma solidity ^0.8.17;

import {Create2} from "@openzeppelin/contracts/utils/Create2.sol";
import {ProxyShim} from "../utils/ProxyShim.sol";
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
    function _createAndInitializeNewFactoryProxyDeterminstic(
        bytes32 proxyShimSalt,
        bytes32 factoryProxySalt,
        bytes calldata proxyCreationCode,
        address expectedFactoryProxyAddress,
        address implementationAddress,
        address newOwner
    ) internal returns (address factoryProxyAddress) {
        // create proxy shim and factory proxy deterministically
        ProxyShim proxyShim = new ProxyShim{salt: proxyShimSalt}({_canUpgrade: address(this)});

        bytes memory creationCode = abi.encodePacked(proxyCreationCode, abi.encode(address(proxyShim), ""));

        address factoryProxy = Create2.deploy(0, factoryProxySalt, creationCode);

        if (factoryProxy != expectedFactoryProxyAddress) {
            revert FactoryProxyAddressMismatch(expectedFactoryProxyAddress, address(factoryProxy));
        }

        factoryProxyAddress = address(factoryProxy);
        IUpgradeableProxy proxy = IUpgradeableProxy(address(factoryProxy));
        proxy.upgradeTo(implementationAddress);
        proxy.initialize(newOwner);

        return factoryProxyAddress;
    }

    bytes32 constant DOMAIN =
        keccak256("createProxy(bytes32 proxyShimSalt,bytes32 proxySalt,bytes proxyCreationCode,address implementationAddress,address owner)");

    function recoverSignature(
        bytes32 proxyShimSalt,
        bytes32 proxySalt,
        bytes calldata proxyCreationCode,
        address implementationAddress,
        address owner,
        bytes calldata signature
    ) public view returns (address) {
        bytes32 digest = hashedDigest(proxyShimSalt, proxySalt, proxyCreationCode, implementationAddress, owner);

        return ECDSA.recover(digest, signature);
    }

    function hashedDigest(
        bytes32 proxyShimSalt,
        bytes32 proxySalt,
        bytes calldata proxyCreationCode,
        address implementationAddress,
        address newOwner
    ) public view returns (bytes32) {
        return _hashTypedDataV4(keccak256(abi.encode(DOMAIN, proxyShimSalt, proxySalt, keccak256(bytes(proxyCreationCode)), implementationAddress, newOwner)));
    }

    function requireContainsCaller(address caller, bytes32 salt) private pure {
        // prevent contract submissions from being stolen from tx.pool by requiring
        // that the first 20 bytes of the submitted salt match msg.sender.
        require((address(bytes20(salt)) == caller) || (bytes20(salt) == bytes20(0)), "Invalid salt - first 20 bytes of the salt must match calling address.");
    }

    /// Creates a new factory proxy at a determinstic address, with this address as the owner
    /// Upgrades the proxy to the factory implementation, and sets the new owner as the owner.
    /// @param proxyShimSalt Salt for deterministic proxy shim address
    /// @param proxySalt Salt for deterministic factory proxy address
    function createFactoryProxyDeterminstic(
        bytes32 proxyShimSalt,
        bytes32 proxySalt,
        bytes calldata proxyCreationCode,
        address expectedFactoryProxyAddress,
        address implementationAddress,
        address owner,
        bytes calldata signature
    ) external returns (address factoryProxyAddress) {
        address signer = recoverSignature(proxyShimSalt, proxySalt, proxyCreationCode, implementationAddress, owner, signature);

        requireContainsCaller(signer, proxyShimSalt);

        return
            _createAndInitializeNewFactoryProxyDeterminstic(
                proxyShimSalt,
                proxySalt,
                proxyCreationCode,
                expectedFactoryProxyAddress,
                implementationAddress,
                owner
            );
    }
}
