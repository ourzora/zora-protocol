// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";

import {IEntryPoint, EntryPoint} from "account-abstraction/contracts/core/EntryPoint.sol";
import {UserOperation} from "account-abstraction/contracts/interfaces/UserOperation.sol";

import {ZoraAccountFactoryImpl} from "../src/factory/ZoraAccountFactoryImpl.sol";
import {ZoraAccountImpl} from "../src/account/ZoraAccountImpl.sol";
import {ZoraAccountFactory} from "../src/proxy/ZoraAccountFactory.sol";
import {ZoraAccount} from "../src/proxy/ZoraAccount.sol";

contract ZoraAccountTestSetup is Test {
    address internal accountOwnerEOA;
    uint256 internal accountOwnerPK;
    bytes32 internal accountOwnerSalt;
    address internal zora;

    EntryPoint internal entryPoint;
    ZoraAccountFactoryImpl internal zoraAccountFactoryImpl;
    ZoraAccountFactoryImpl internal zoraAccountFactory;

    function setUp() public virtual {
        (accountOwnerEOA, accountOwnerPK) = makeAddrAndKey("accountOwnerEOA");
        accountOwnerSalt = keccak256(abi.encodePacked("accountOwnerSalt"));
        zora = makeAddr("zora");

        entryPoint = new EntryPoint();
        zoraAccountFactoryImpl = new ZoraAccountFactoryImpl(entryPoint);
        zoraAccountFactory = ZoraAccountFactoryImpl(
            payable(address(new ZoraAccountFactory(address(zoraAccountFactoryImpl), abi.encodeWithSelector(zoraAccountFactoryImpl.initialize.selector, zora))))
        );
    }

    function deployAccount(address owner, uint256 salt) internal returns (ZoraAccountImpl) {
        return ZoraAccountImpl(payable(address(zoraAccountFactory.createAccount(owner, salt))));
    }
}
