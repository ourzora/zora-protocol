// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Test.sol";

import {ZoraAccountManagerImpl} from "../src/ZoraAccountManagerImpl.sol";
import {ZoraAccountManager} from "../src/ZoraAccountManager.sol";
import {ICoinbaseSmartWalletFactory} from "../src/interfaces/ICoinbaseSmartWalletFactory.sol";

contract ZoraAccountManagerTest is Test {
    struct Users {
        address alice;
        address bob;
        address charlie;
        address owner;
    }

    Users internal users;
    address[] internal mockOwners;

    ZoraAccountManagerImpl internal managerImpl;
    ZoraAccountManagerImpl internal manager;

    ICoinbaseSmartWalletFactory internal constant smartWalletFactory = ICoinbaseSmartWalletFactory(0x0BA5ED0c6AA8c49038F819E587E2633c4A9F428a);

    function setUp() public {
        vm.createSelectFork(vm.envString("ZORA_SEPOLIA_RPC_URL"));

        users = Users({alice: makeAddr("alice"), bob: makeAddr("bob"), charlie: makeAddr("charlie"), owner: makeAddr("owner")});
        mockOwners = new address[](3);
        mockOwners[0] = users.alice;
        mockOwners[1] = users.bob;
        mockOwners[2] = users.charlie;

        managerImpl = new ZoraAccountManagerImpl();
        manager = ZoraAccountManagerImpl(address(new ZoraAccountManager(address(managerImpl), "")));
        manager.initialize(users.owner);
    }

    function testDeploy() public view {
        assertEq(manager.implementation(), address(managerImpl));
        assertEq(manager.owner(), users.owner);
    }

    function testCreateSmartWallet() public {
        bytes[] memory encodedOwners = encodeOwners(mockOwners);
        uint256 nonce = 0;

        address smartWallet = manager.createSmartWallet(encodedOwners, nonce);

        assertEq(manager.getAddress(encodedOwners, nonce), smartWallet);
    }

    function encodeOwners(address[] memory owners) public pure returns (bytes[] memory) {
        bytes[] memory encodedOwners = new bytes[](owners.length);

        for (uint256 i; i < owners.length; ++i) {
            encodedOwners[i] = abi.encode(owners[i]);
        }

        return encodedOwners;
    }
}
