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

contract CreatorRoyaltiesControlTest is Test {
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

    function _emptyInitData() internal pure returns (bytes[] memory response) {
        response = new bytes[](0);
    }

    function test_GetsRoyaltiesInfoGlobalDefault() external {
        address royaltyPayout = address(0x999);
        zoraCreator1155Impl = new ZoraCreator1155Impl(0, recipient);
        target = ZoraCreator1155Impl(address(new ZoraCreator1155Proxy(address(zoraCreator1155Impl))));
        adminRole = target.PERMISSION_BIT_ADMIN();
        target.initialize("test", ICreatorRoyaltiesControl.RoyaltyConfiguration(10, address(royaltyPayout)), admin, _emptyInitData());

        vm.prank(admin);
        uint256 tokenId = target.setupNewToken("test", 100);

        (address royaltyRecipient, uint256 amount) = target.royaltyInfo(tokenId, 1 ether);
        assertEq(amount, 0.001 ether);
        assertEq(royaltyRecipient, royaltyPayout);
    }

    function test_GetsRoyaltiesInfoSpecificToken() external {
        address royaltyPayout = address(0x999);
        zoraCreator1155Impl = new ZoraCreator1155Impl(0, recipient);
        target = ZoraCreator1155Impl(address(new ZoraCreator1155Proxy(address(zoraCreator1155Impl))));
        adminRole = target.PERMISSION_BIT_ADMIN();
        target.initialize("test", ICreatorRoyaltiesControl.RoyaltyConfiguration(10, address(royaltyPayout)), admin, _emptyInitData());

        vm.startPrank(admin);
        uint256 tokenIdFirst = target.setupNewToken("test", 100);
        uint256 tokenIdSecond = target.setupNewToken("test", 100);

        target.updateRoyaltiesForToken(tokenIdSecond, ICreatorRoyaltiesControl.RoyaltyConfiguration(100, address(0x992)));

        vm.stopPrank();

        (address royaltyRecipient, uint256 amount) = target.royaltyInfo(tokenIdFirst, 1 ether);
        assertEq(amount, 0.001 ether);
        assertEq(royaltyRecipient, royaltyPayout);

        (address royaltyRecipientSecond, uint256 amountSecond) = target.royaltyInfo(tokenIdSecond, 1 ether);
        assertEq(amountSecond, 0.01 ether);
        assertEq(royaltyRecipientSecond, address(0x992));
    }
}
