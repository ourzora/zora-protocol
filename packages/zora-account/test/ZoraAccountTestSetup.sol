// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";

import {IEntryPoint, EntryPoint} from "account-abstraction/contracts/core/EntryPoint.sol";
import {UserOperation} from "account-abstraction/contracts/interfaces/UserOperation.sol";

import {ZoraAccountFactoryImpl} from "../src/factory/ZoraAccountFactoryImpl.sol";
import {ZoraAccountImpl} from "../src/account/ZoraAccountImpl.sol";
import {ZoraAccountFactory} from "../src/proxy/ZoraAccountFactory.sol";
import {ZoraAccount} from "../src/proxy/ZoraAccount.sol";
import {ZoraAccountUpgradeGate} from "../src/upgrades/ZoraAccountUpgradeGate.sol";

import {MessageHashUtils} from "@openzeppelin/contracts/utils/cryptography/MessageHashUtils.sol";
import "./utils/MockNFTs.sol";

contract ZoraAccountTestSetup is Test {
    address internal accountOwnerEOA;
    uint256 internal accountOwnerPK;
    bytes32 internal accountOwnerSalt;
    address internal zora;
    address internal beneficiary;

    EntryPoint internal entryPoint;
    ZoraAccountUpgradeGate internal upgradeGate;
    ZoraAccountFactoryImpl internal zoraAccountFactoryImpl;
    ZoraAccountFactoryImpl internal zoraAccountFactory;
    ZoraAccountImpl internal account;

    MockERC721 internal mock721;
    MockERC1155 internal mock1155;

    function setUp() public virtual {
        (accountOwnerEOA, accountOwnerPK) = makeAddrAndKey("accountOwnerEOA");
        accountOwnerSalt = keccak256(abi.encodePacked("accountOwnerSalt"));
        zora = makeAddr("zora");
        beneficiary = makeAddr("beneficiary");

        entryPoint = new EntryPoint();
        upgradeGate = new ZoraAccountUpgradeGate();
        zoraAccountFactoryImpl = new ZoraAccountFactoryImpl(entryPoint, address(upgradeGate));
        zoraAccountFactory = ZoraAccountFactoryImpl(
            payable(address(new ZoraAccountFactory(address(zoraAccountFactoryImpl), abi.encodeWithSelector(zoraAccountFactoryImpl.initialize.selector, zora))))
        );
        account = deployAccount(accountOwnerEOA, uint256(accountOwnerSalt));

        mock721 = new MockERC721(address(account));
        mock1155 = new MockERC1155(address(account));
    }

    function deployAccount(address owner, uint256 salt) internal returns (ZoraAccountImpl) {
        return ZoraAccountImpl(payable(address(zoraAccountFactory.createAccount(owner, salt))));
    }

    function getUserOpCalldata(address to, uint256 value, bytes memory data) internal pure returns (bytes memory) {
        return abi.encodeWithSelector(ZoraAccountImpl.execute.selector, to, value, data);
    }

    function getSignedUserOp(uint256 fromAccountOwnerPK, address fromAccount, bytes memory userOpCalldata) internal view returns (UserOperation memory) {
        UserOperation memory userOp = getUserOp(fromAccount, userOpCalldata);

        bytes32 userOpHash = entryPoint.getUserOpHash(userOp);
        bytes32 digest = MessageHashUtils.toEthSignedMessageHash(userOpHash);

        userOp.signature = sign(fromAccountOwnerPK, digest);

        return userOp;
    }

    function getUserOp(address fromAccount, bytes memory userOpCalldata) internal pure returns (UserOperation memory) {
        return
            UserOperation({
                sender: fromAccount,
                nonce: 0,
                initCode: "",
                callData: userOpCalldata,
                callGasLimit: 1 << 24,
                verificationGasLimit: 1 << 24,
                preVerificationGas: 1 << 24,
                maxFeePerGas: 1 << 8,
                maxPriorityFeePerGas: 1 << 8,
                paymasterAndData: "",
                signature: ""
            });
    }

    function sign(uint256 privateKey, bytes32 digest) internal pure returns (bytes memory signature) {
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(privateKey, digest);
        signature = abi.encodePacked(r, s, v);
    }
}
