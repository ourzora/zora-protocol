// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "./ZoraAccountTestSetup.sol";

contract ZoraAccountFactoryTest is ZoraAccountTestSetup {
    function setUp() public override {
        super.setUp();
    }

    function testFactoryGetAddress(address fuzzOwner, uint256 fuzzOwnerSalt) public {
        address precomputedAccountAddress = zoraAccountFactory.getAddress(fuzzOwner, fuzzOwnerSalt);

        account = deployAccount(fuzzOwner, fuzzOwnerSalt);

        assertEq(address(account), precomputedAccountAddress);
    }

    function testFactoryGetAddressWhenAccountExists(address fuzzOwner, uint256 fuzzOwnerSalt) public {
        account = deployAccount(fuzzOwner, fuzzOwnerSalt);

        address precomputedAccountAddress = zoraAccountFactory.getAddress(fuzzOwner, fuzzOwnerSalt);

        assertEq(address(account), precomputedAccountAddress);
    }

    function testFactoryImpl() public {
        assertEq(address(zoraAccountFactoryImpl), zoraAccountFactory.implementation());
    }

    function testFactoryAccountImpl() public {
        account = deployAccount(accountOwnerEOA, uint256(accountOwnerSalt));

        assertEq(account.implementation(), address(zoraAccountFactory.zoraAccountImpl()));
    }
}
