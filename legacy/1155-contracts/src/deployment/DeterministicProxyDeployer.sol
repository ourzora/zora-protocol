// spdx-license-identifier: mit
pragma solidity >=0.8.17;

import {Create2} from "@openzeppelin/contracts/utils/Create2.sol";
import {ProxyShim} from "../utils/ProxyShim.sol";
import {EIP712} from "@openzeppelin/contracts/utils/cryptography/EIP712.sol";
import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";

interface IUpgradeableProxy {
    function upgradeTo(address newImplementation) external;

    function initialize(address newOwner) external;
}

/// @notice Deterministic proxy deployer for deploying zora 1155 contract suite
/// @dev Supports both generic contracts and the UUPS shim proxy pattern used for ZORA 1155
/// @dev Requires approved signatures depending on the salt hashes (pattern from IMMUTABLE_CREATE2_FACTORY)
contract DeterministicProxyDeployer is EIP712 {
    error FactoryProxyAddressMismatch(address expected, address actual);
    error FailedToInitGenericDeployedContract();

    constructor() EIP712("DeterministicProxyDeployer", "1") {}

    /// Creates a new factory proxy at a Deterministic address, with this address as the owner
    /// Upgrades the proxy to the factory implementation, and sets the new owner as the owner.
    /// @param proxyShimSalt Salt for deterministic proxy shim address
    /// @param factoryProxySalt Salt for deterministic factory proxy address
    function _createAndInitializeNewFactoryProxyDeterministic(
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

    function _createAndInitGenericContractDeterministic(
        bytes32 genericCreationSalt,
        bytes calldata creationCode,
        bytes calldata initCall
    ) internal returns (address resultAddress) {
        resultAddress = Create2.deploy(0, genericCreationSalt, creationCode);

        (bool success, ) = resultAddress.call(initCall);
        if (!success) {
            revert FailedToInitGenericDeployedContract();
        }
    }

    bytes32 constant DOMAIN_UPGRADEABLE_PROXY =
        keccak256("createProxy(bytes32 proxyShimSalt,bytes32 proxySalt,bytes proxyCreationCode,address implementationAddress,address owner)");
    bytes32 constant DOMAIN_GENERIC_CREATION = keccak256("createGenericContract(bytes32 salt,bytes creationCode,bytes initCall)");

    function recoverSignature(bytes32 digest, bytes calldata signature) public pure returns (address) {
        return ECDSA.recover(digest, signature);
    }

    function hashedDigestFactoryProxy(
        bytes32 proxyShimSalt,
        bytes32 proxySalt,
        bytes calldata proxyCreationCode,
        address implementationAddress,
        address newOwner
    ) public view returns (bytes32) {
        return
            _hashTypedDataV4(
                keccak256(abi.encode(DOMAIN_UPGRADEABLE_PROXY, proxyShimSalt, proxySalt, keccak256(proxyCreationCode), implementationAddress, newOwner))
            );
    }

    function hashedDigestGenericCreation(bytes32 salt, bytes calldata creationCode, bytes calldata initCall) public view returns (bytes32) {
        return _hashTypedDataV4(keccak256(abi.encode(DOMAIN_GENERIC_CREATION, salt, keccak256(creationCode), keccak256(initCall))));
    }

    function requireContainsCaller(address caller, bytes32 salt) private pure {
        // prevent contract submissions from being stolen from tx.pool by requiring
        // that the first 20 bytes of the submitted salt match msg.sender.
        require((address(bytes20(salt)) == caller) || (bytes20(salt) == bytes20(0)), "Invalid salt - first 20 bytes of the salt must match calling address.");
    }

    /// Creates a new factory proxy at a Deterministic address, with this address as the owner
    /// Upgrades the proxy to the factory implementation, and sets the new owner as the owner.
    /// @param proxyShimSalt Salt for deterministic proxy shim address
    /// @param proxySalt Salt for deterministic factory proxy address
    function createFactoryProxyDeterministic(
        bytes32 proxyShimSalt,
        bytes32 proxySalt,
        bytes calldata proxyCreationCode,
        address expectedFactoryProxyAddress,
        address implementationAddress,
        address owner,
        bytes calldata signature
    ) external returns (address factoryProxyAddress) {
        address signer = recoverSignature(hashedDigestFactoryProxy(proxyShimSalt, proxySalt, proxyCreationCode, implementationAddress, owner), signature);

        requireContainsCaller(signer, proxyShimSalt);

        return
            _createAndInitializeNewFactoryProxyDeterministic(
                proxyShimSalt,
                proxySalt,
                proxyCreationCode,
                expectedFactoryProxyAddress,
                implementationAddress,
                owner
            );
    }

    function createAndInitGenericContractDeterministic(
        bytes32 genericCreationSalt,
        bytes calldata creationCode,
        bytes calldata initCall,
        bytes calldata signature
    ) external returns (address resultAddress) {
        address signer = recoverSignature(hashedDigestGenericCreation(genericCreationSalt, creationCode, initCall), signature);

        requireContainsCaller(signer, genericCreationSalt);

        return _createAndInitGenericContractDeterministic(genericCreationSalt, creationCode, initCall);
    }
}
