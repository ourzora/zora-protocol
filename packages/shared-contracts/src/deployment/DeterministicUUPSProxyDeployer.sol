// spdx-license-identifier: MIT
pragma solidity ^0.8.17;

import {Create2} from "@openzeppelin/contracts/utils/Create2.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts/proxy/utils/UUPSUpgradeable.sol";

/// Used to deploy the factory before we know the impl address
contract ProxyShim is UUPSUpgradeable {
    address immutable canUpgrade;

    constructor() {
        // defaults to msg.sender being address(this)
        canUpgrade = msg.sender;
    }

    function _authorizeUpgrade(address) internal view override {
        require(msg.sender == canUpgrade, "not authorized");
    }
}

/// @notice Safe create 2 deployer and intializer for deploying proxy contracts at a desired address, upgrading them to an initial implementation, and then initializing them
/// @notice First 20 bytes of salt must match the msg.sender
contract DeterministicUUPSProxyDeployer {
    error FactoryProxyAddressMismatch(address expected, address actual);

    constructor() {}

    bytes32 constant INITIAL_IMPLEMENTATION_SALT = bytes32(0x0000000000000000000000000000000000000000000000000000000000000000);

    /// Address of the proxy shim contract that is used to upgrade the factory proxy
    function proxyShimAddress() public view returns (address) {
        return Create2.computeAddress(INITIAL_IMPLEMENTATION_SALT, keccak256(type(ProxyShim).creationCode));
    }

    /// Constructor args when creating the proxy
    function proxyConstructorArgs() public view returns (bytes memory) {
        return abi.encode(proxyShimAddress());
    }

    /// Initialization code for the proxy, including the constructor args
    function proxyCreationCode(bytes memory transparentProxyCode) public view returns (bytes memory) {
        return abi.encodePacked(transparentProxyCode, proxyConstructorArgs());
    }

    /// Expected address of the proxy deployed from this contract, given a salt and proxy code
    function expectedProxyAddress(bytes32 proxySalt, bytes memory proxyCode) public view returns (address) {
        bytes memory _transparentProxyCreationCode = proxyCreationCode(proxyCode);

        return Create2.computeAddress(proxySalt, keccak256(_transparentProxyCreationCode));
    }

    error InvalidSalt(address signer, bytes32 salt);

    function _getOrCreateProxyShim() private returns (ProxyShim proxyShim) {
        // check if initial implementation has been created
        // get create 2 address for initial implementation
        address _proxyShimAddress = proxyShimAddress();

        if (_proxyShimAddress.code.length > 0) {
            proxyShim = ProxyShim(_proxyShimAddress);
        } else {
            // create initial implementation at determinstic address
            proxyShim = new ProxyShim{salt: INITIAL_IMPLEMENTATION_SALT}();
        }
    }

    function _requireContainsCaller(address signer, bytes32 salt) private pure {
        // prevent contract submissions from being stolen from tx.pool by requiring
        // that the first 20 bytes of the submitted salt match msg.sender.
        if (address(bytes20(salt)) != signer) {
            revert InvalidSalt(signer, salt);
        }
    }

    /// Creates a contract using create2, and then calls an initialization function on it.
    /// First 20 bytes of salt must match the msg.sender
    /// @param proxySalt Salt to create the contract with
    /// @param proxyCode contract creation code
    /// @param initialImplementation address to upgrade to
    /// @param postUpgradeCall what to call on the contract after upgrading
    /// @param _expectedAddress expected address of the created contract
    function safeCreate2AndUpgradeToAndCall(
        bytes32 proxySalt,
        bytes memory proxyCode,
        address initialImplementation,
        bytes memory postUpgradeCall,
        address _expectedAddress
    ) external payable {
        _requireContainsCaller(msg.sender, proxySalt);

        _getOrCreateProxyShim();

        bytes memory _proxyCreationCode = proxyCreationCode(proxyCode);

        // create the proxy
        address proxyAddress = Create2.deploy(0, proxySalt, _proxyCreationCode);

        if (proxyAddress != _expectedAddress) {
            revert FactoryProxyAddressMismatch(_expectedAddress, proxyAddress);
        }

        UUPSUpgradeable(proxyAddress).upgradeToAndCall(initialImplementation, postUpgradeCall);
    }
}
