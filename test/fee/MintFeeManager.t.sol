// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import "forge-std/Test.sol";
import {ZoraCreator1155Impl} from "../../src/nft/ZoraCreator1155Impl.sol";
import {ZoraCreator1155Proxy} from "../../src/proxies/ZoraCreator1155Proxy.sol";
import {IZoraCreator1155} from "../../src/interfaces/IZoraCreator1155.sol";
import {IZoraCreator1155TypesV1} from "../../src/nft/IZoraCreator1155TypesV1.sol";
import {ICreatorRoyaltiesControl} from "../../src/interfaces/ICreatorRoyaltiesControl.sol";
import {IZoraCreator1155Factory} from "../../src/interfaces/IZoraCreator1155Factory.sol";
import {IMintFeeManager} from "../../src/interfaces/IMintFeeManager.sol";
import {SimpleMinter} from "../mock/SimpleMinter.sol";

contract MintFeeManagerTest is Test {
    ZoraCreator1155Impl internal zoraCreator1155Impl;
    ZoraCreator1155Impl internal target;
    address internal admin;
    address internal recipient;
    uint256 internal adminRole;
    uint256 internal minterRole;
    uint256 internal fundsManagerRole;

    function setUp() external {
        admin = vm.addr(0x1);
        recipient = vm.addr(0x2);
    }

    function _emptyInitData() internal returns (bytes[] memory response) {
        response = new bytes[](0);
    }

    function test_mintFeeSent(
        uint32 mintFee,
        uint256 purchasePrice,
        uint256 quantity
    ) external {
        vm.assume(purchasePrice > mintFee);
        zoraCreator1155Impl = new ZoraCreator1155Impl( mintFee, recipient);
        target = ZoraCreator1155Impl(address(new ZoraCreator1155Proxy(address(zoraCreator1155Impl))));
        adminRole = target.PERMISSION_BIT_ADMIN();
        target.initialize("test", ICreatorRoyaltiesControl.RoyaltyConfiguration(0, address(0)), admin, _emptyInitData());

        vm.prank(admin);
        uint256 tokenId = target.setupNewToken("test", quantity);

        address minter = address(new SimpleMinter());
        vm.prank(admin);
        target.addPermission(tokenId, minter, adminRole);

        vm.deal(admin, purchasePrice);
        vm.prank(admin);
        target.purchase{value: purchasePrice}(SimpleMinter(payable(minter)), tokenId, quantity, abi.encode(recipient));

        vm.prank(admin);
        target.withdrawAll();

        // Mint fee is not paid if the recipient is address(0)
        assertEq(recipient.balance, recipient == address(0) ? 0 : mintFee);
        assertEq(admin.balance, recipient == address(0) ? purchasePrice : purchasePrice - mintFee);
    }

    function test_mintFeeSent_revertCannotSendMintFee(
        uint32 mintFee,
        uint256 purchasePrice,
        uint256 quantity
    ) external {
        vm.assume(purchasePrice > mintFee);

        // Use this mock contract as a recipient so we can reject ETH payments.
        SimpleMinter _recip = new SimpleMinter();
        _recip.setReceiveETH(false);
        address _recipient = address(_recip);

        zoraCreator1155Impl = new ZoraCreator1155Impl( mintFee, _recipient);
        target = ZoraCreator1155Impl(address(new ZoraCreator1155Proxy(address(zoraCreator1155Impl))));
        adminRole = target.PERMISSION_BIT_ADMIN();
        target.initialize("test", ICreatorRoyaltiesControl.RoyaltyConfiguration(0, address(0)), admin, _emptyInitData());

        vm.prank(admin);
        uint256 tokenId = target.setupNewToken("test", quantity);

        address minter = address(new SimpleMinter());
        vm.prank(admin);
        target.addPermission(tokenId, minter, adminRole);

        vm.deal(admin, purchasePrice);
        vm.expectRevert(abi.encodeWithSelector(IMintFeeManager.CannotSendMintFee.selector, _recipient, mintFee));
        vm.prank(admin);
        target.purchase{value: purchasePrice}(SimpleMinter(payable(minter)), tokenId, quantity, abi.encode(recipient));
    }
}
