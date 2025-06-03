// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {BaseTest} from "../utils/BaseTest.sol";
import {DeployedCoinVersionLookup} from "../../src/utils/DeployedCoinVersionLookup.sol";

contract TestDeployedCoinVersionLookupImplementation is DeployedCoinVersionLookup {
    function setVersionForTesting(address coin, uint8 version) external {
        _setVersionForDeployedCoin(coin, version);
    }
}

/**
 * @title Mock implementation with different namespace
 * @dev Used to verify that different namespaces don't collide
 */
contract DifferentNamespaceVersionLookup {
    /// @custom:storage-location erc7201:different.namespace
    struct DeployedCoinVersionStorage {
        mapping(address => uint8) deployedCoinWithVersion;
    }

    // keccak256(abi.encode(uint256(keccak256("different.namespace")) - 1)) & ~bytes32(uint256(0xff))
    bytes32 private constant DEPLOYED_COIN_VERSION_STORAGE_LOCATION = 0xf0ec9c7ea8b861b539967dd0659fb8887a9724eca55e932839a2a8e01f50c400;

    function _getDeployedCoinVersionStorage() private pure returns (DeployedCoinVersionStorage storage $) {
        assembly {
            $.slot := DEPLOYED_COIN_VERSION_STORAGE_LOCATION
        }
    }

    function getVersionForDeployedCoin(address coin) public view returns (uint8) {
        return _getDeployedCoinVersionStorage().deployedCoinWithVersion[coin];
    }

    function setVersionForTesting(address coin, uint8 version) external {
        _getDeployedCoinVersionStorage().deployedCoinWithVersion[coin] = version;
    }
}

contract DeployedCoinVersionLookupTest is BaseTest {
    TestDeployedCoinVersionLookupImplementation public versionLookup;
    DifferentNamespaceVersionLookup public differentNamespaceLookup;
    address public testCoin1;
    address public testCoin2;
    address public testContractAddress;

    function setUp() public override {
        super.setUp();
        versionLookup = new TestDeployedCoinVersionLookupImplementation();
        differentNamespaceLookup = new DifferentNamespaceVersionLookup();
        testCoin1 = makeAddr("testCoin1");
        testCoin2 = makeAddr("testCoin2");
        testContractAddress = makeAddr("testContractAddress");
    }

    function test_getAndSetVersionForDeployedCoin() public {
        // Default version should be 0
        assertEq(versionLookup.getVersionForDeployedCoin(testCoin1), 0);

        // Set version and verify
        versionLookup.setVersionForTesting(testCoin1, 1);
        assertEq(versionLookup.getVersionForDeployedCoin(testCoin1), 1);

        // Set version for a different coin
        versionLookup.setVersionForTesting(testCoin2, 2);
        assertEq(versionLookup.getVersionForDeployedCoin(testCoin2), 2);

        // First coin's version should remain unchanged
        assertEq(versionLookup.getVersionForDeployedCoin(testCoin1), 1);

        // Update version and verify
        versionLookup.setVersionForTesting(testCoin1, 3);
        assertEq(versionLookup.getVersionForDeployedCoin(testCoin1), 3);
    }

    function test_differentNamespaceIndependence() public {
        // First deploy the original implementation at a fixed address
        TestDeployedCoinVersionLookupImplementation originalImpl = new TestDeployedCoinVersionLookupImplementation();
        bytes memory originalBytecode = address(originalImpl).code;

        // Deploy a different implementation
        DifferentNamespaceVersionLookup differentImpl = new DifferentNamespaceVersionLookup();
        bytes memory differentBytecode = address(differentImpl).code;

        // Etch the original implementation to the test address
        vm.etch(testContractAddress, originalBytecode);

        // Test setting values with the first implementation
        TestDeployedCoinVersionLookupImplementation(testContractAddress).setVersionForTesting(testCoin1, 42);
        assertEq(TestDeployedCoinVersionLookupImplementation(testContractAddress).getVersionForDeployedCoin(testCoin1), 42);

        // Save the bytecode location for the first implementation
        bytes32 firstSlot = vm.load(
            testContractAddress,
            bytes32(uint256(keccak256(abi.encode(testCoin1, 0x9a79df0b86f39d0543c14aee714123562f798115071e932933bcc3e29cc86f00))))
        );
        assertEq(uint256(firstSlot), 42);

        // Now replace the code with the different namespace implementation
        vm.etch(testContractAddress, differentBytecode);

        // Set a value with the different implementation
        DifferentNamespaceVersionLookup(testContractAddress).setVersionForTesting(testCoin1, 99);

        // This should use a different storage slot, so it shouldn't affect the original value
        assertEq(DifferentNamespaceVersionLookup(testContractAddress).getVersionForDeployedCoin(testCoin1), 99);

        // Verify the original storage slot still has the original value
        bytes32 secondSlot = vm.load(
            testContractAddress,
            bytes32(uint256(keccak256(abi.encode(testCoin1, 0xf0ec9c7ea8b861b539967dd0659fb8887a9724eca55e932839a2a8e01f50c400))))
        );
        assertEq(uint256(secondSlot), 99);

        // Switch back to the original implementation to verify its storage is unchanged
        vm.etch(testContractAddress, originalBytecode);
        assertEq(TestDeployedCoinVersionLookupImplementation(testContractAddress).getVersionForDeployedCoin(testCoin1), 42);

        // Change the value in the original implementation
        TestDeployedCoinVersionLookupImplementation(testContractAddress).setVersionForTesting(testCoin1, 123);

        // Switch back to the different namespace implementation to verify its storage is unchanged
        vm.etch(testContractAddress, differentBytecode);
        assertEq(DifferentNamespaceVersionLookup(testContractAddress).getVersionForDeployedCoin(testCoin1), 99);
    }
}
