// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import {TrustedMsgSenderProviderLookup} from "../src/utils/TrustedMsgSenderProviderLookup.sol";
import {ITrustedMsgSenderProviderLookup} from "../src/interfaces/ITrustedMsgSenderProviderLookup.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {Ownable2Step} from "@openzeppelin/contracts/access/Ownable2Step.sol";

contract TrustedMsgSenderProviderLookupTest is Test {
    ITrustedMsgSenderProviderLookup internal trustedMsgSenderLookup;

    address internal owner;
    address internal nonOwner;
    address internal trustedSender1;
    address internal trustedSender2;

    event TrustedSenderAdded(address indexed sender);
    event TrustedSenderRemoved(address indexed sender);

    function setUp() public {
        owner = makeAddr("owner");
        nonOwner = makeAddr("nonOwner");
        trustedSender1 = makeAddr("trustedSender1");
        trustedSender2 = makeAddr("trustedSender2");
    }

    function deployAndInitializeLookup(address[] memory initialTrustedSenders, address initialOwner) internal returns (ITrustedMsgSenderProviderLookup) {
        // Deploy the contract directly using constructor
        TrustedMsgSenderProviderLookup lookup = new TrustedMsgSenderProviderLookup(initialTrustedSenders, initialOwner);
        return ITrustedMsgSenderProviderLookup(address(lookup));
    }

    function test_constructor_initializesCorrectly() public {
        address[] memory initialTrustedSenders = new address[](2);
        initialTrustedSenders[0] = trustedSender1;
        initialTrustedSenders[1] = trustedSender2;

        trustedMsgSenderLookup = deployAndInitializeLookup(initialTrustedSenders, owner);

        assertEq(Ownable2Step(address(trustedMsgSenderLookup)).owner(), owner);
        assertTrue(trustedMsgSenderLookup.isTrustedMsgSenderProvider(trustedSender1));
        assertTrue(trustedMsgSenderLookup.isTrustedMsgSenderProvider(trustedSender2));
    }

    function test_isTrustedMsgSenderProvider_returnsCorrectValues() public {
        address[] memory initialTrustedSenders = new address[](1);
        initialTrustedSenders[0] = trustedSender1;

        trustedMsgSenderLookup = deployAndInitializeLookup(initialTrustedSenders, owner);

        assertTrue(trustedMsgSenderLookup.isTrustedMsgSenderProvider(trustedSender1));
        assertFalse(trustedMsgSenderLookup.isTrustedMsgSenderProvider(trustedSender2));
        assertFalse(trustedMsgSenderLookup.isTrustedMsgSenderProvider(address(0)));
    }

    function test_addTrustedMsgSenderProviders_worksCorrectly() public {
        address[] memory emptyTrustedSenders = new address[](0);
        trustedMsgSenderLookup = deployAndInitializeLookup(emptyTrustedSenders, owner);

        address[] memory sendersToAdd = new address[](2);
        sendersToAdd[0] = trustedSender1;
        sendersToAdd[1] = trustedSender2;

        vm.prank(owner);
        TrustedMsgSenderProviderLookup(address(trustedMsgSenderLookup)).addTrustedMsgSenderProviders(sendersToAdd);

        assertTrue(trustedMsgSenderLookup.isTrustedMsgSenderProvider(trustedSender1));
        assertTrue(trustedMsgSenderLookup.isTrustedMsgSenderProvider(trustedSender2));
    }

    function test_addTrustedMsgSenderProviders_onlyOwnerCanAdd() public {
        address[] memory emptyTrustedSenders = new address[](0);
        trustedMsgSenderLookup = deployAndInitializeLookup(emptyTrustedSenders, owner);

        address[] memory sendersToAdd = new address[](1);
        sendersToAdd[0] = trustedSender1;

        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, nonOwner));
        vm.prank(nonOwner);
        TrustedMsgSenderProviderLookup(address(trustedMsgSenderLookup)).addTrustedMsgSenderProviders(sendersToAdd);
    }

    function test_removeTrustedMsgSenderProviders_worksCorrectly() public {
        address[] memory initialTrustedSenders = new address[](2);
        initialTrustedSenders[0] = trustedSender1;
        initialTrustedSenders[1] = trustedSender2;
        trustedMsgSenderLookup = deployAndInitializeLookup(initialTrustedSenders, owner);

        address[] memory sendersToRemove = new address[](1);
        sendersToRemove[0] = trustedSender1;

        vm.prank(owner);
        TrustedMsgSenderProviderLookup(address(trustedMsgSenderLookup)).removeTrustedMsgSenderProviders(sendersToRemove);

        assertFalse(trustedMsgSenderLookup.isTrustedMsgSenderProvider(trustedSender1));
        assertTrue(trustedMsgSenderLookup.isTrustedMsgSenderProvider(trustedSender2));
    }

    function test_removeTrustedMsgSenderProviders_onlyOwnerCanRemove() public {
        address[] memory initialTrustedSenders = new address[](1);
        initialTrustedSenders[0] = trustedSender1;
        trustedMsgSenderLookup = deployAndInitializeLookup(initialTrustedSenders, owner);

        address[] memory sendersToRemove = new address[](1);
        sendersToRemove[0] = trustedSender1;

        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, nonOwner));
        vm.prank(nonOwner);
        TrustedMsgSenderProviderLookup(address(trustedMsgSenderLookup)).removeTrustedMsgSenderProviders(sendersToRemove);
    }
}
