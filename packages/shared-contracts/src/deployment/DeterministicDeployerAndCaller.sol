// spdx-license-identifier: MIT
pragma solidity ^0.8.17;

import {Create2} from "@openzeppelin/contracts/utils/Create2.sol";
import {EIP712} from "@openzeppelin/contracts/utils/cryptography/EIP712.sol";
import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts/proxy/utils/UUPSUpgradeable.sol";

/// Used to deploy the factory before we know the impl address
contract ProxyShim is UUPSUpgradeable {
    address immutable canUpgrade;

    constructor() {
        // defaults to msg.sender being address(this)
        canUpgrade = msg.sender;
    }

    function _authorizeUpgrade(address) internal view override {}
}

/// @notice Deploys and calls a contract using create2 deterministically
/// @notice First 20 bytes of salt must match the msg.sender
contract DeterministicDeployerAndCaller is EIP712 {
    error FactoryProxyAddressMismatch(address expected, address actual);

    ProxyShim public immutable proxyShim;

    bytes32 constant PROXY_SHIM_SALT = bytes32(0x0000000000000000000000000000000000000000000000000000000000000000);

    constructor() EIP712("DeterministicDeployerAndCaller", "1") {
        // create proxy shim at predictable address, regardless of block
        proxyShim = new ProxyShim{salt: PROXY_SHIM_SALT}();
    }

    error InvalidSalt(address signer, bytes32 salt);

    error CallFailed(bytes returnData);

    bytes32 constant DOMAIN = keccak256("create(bytes32 salt,bytes code,bytes postCreateCall)");

    function hashDigest(bytes32 salt, bytes memory code, bytes memory postCreateCall) public view returns (bytes32) {
        return _hashTypedDataV4(keccak256(abi.encode(DOMAIN, salt, keccak256(code), keccak256(postCreateCall))));
    }

    bytes32 constant INITIAL_IMPLEMENTATION_SALT = bytes32(0x0000000000000000000000000000000000000000000000000000000000000000);

    /// Constructor args when creating the proxy
    function proxyConstructorArgs() public view returns (bytes memory) {
        return abi.encode(address(proxyShim));
    }

    /// Initialization code for the proxy, including the constructor args
    function proxyCreationCode(bytes memory proxyCode) public view returns (bytes memory) {
        return abi.encodePacked(proxyCode, proxyConstructorArgs());
    }

    function _requireContainsCaller(address signer, bytes32 salt) private pure {
        // prevent contract submissions from being stolen from tx.pool by requiring
        // that the first 20 bytes of the submitted salt match msg.sender.
        if (address(bytes20(salt)) != signer) {
            revert InvalidSalt(signer, salt);
        }
    }

    function _safeCreate2AndCall(bytes32 salt, bytes memory code, bytes memory postCreateCall, address _expectedAddress) private returns (address) {
        address deterministicAddress = Create2.computeAddress(salt, keccak256(code), address(this));
        if (_expectedAddress != deterministicAddress) {
            revert FactoryProxyAddressMismatch(_expectedAddress, deterministicAddress);
        }

        // create the proxy
        address proxyAddress = Create2.deploy(0, salt, code);

        (bool success, bytes memory returnData) = proxyAddress.call(postCreateCall);

        if (!success) {
            revert CallFailed(returnData);
        }

        return proxyAddress;
    }

    /// Creates a contract using create2, and then calls an initialization function on it.
    /// First 20 bytes of salt must match the msg.sender
    /// @param salt Salt to create the contract with
    /// @param code contract creation code
    /// @param postCreateCall what to call on the contract after deploying it
    /// @param _expectedAddress expected address of the created contract
    function safeCreate2AndCall(bytes32 salt, bytes memory code, bytes memory postCreateCall, address _expectedAddress) external payable returns (address) {
        _requireContainsCaller(msg.sender, salt);

        return _safeCreate2AndCall(salt, code, postCreateCall, _expectedAddress);
    }

    function permitSafeCreate2AndCall(
        bytes memory signature,
        bytes32 salt,
        bytes memory code,
        bytes memory postCreateCall,
        address _expectedAddress
    ) external payable returns (address) {
        address signer = ECDSA.recover(hashDigest(salt, code, postCreateCall), signature);

        _requireContainsCaller(signer, salt);

        return _safeCreate2AndCall(salt, code, postCreateCall, _expectedAddress);
    }
}
