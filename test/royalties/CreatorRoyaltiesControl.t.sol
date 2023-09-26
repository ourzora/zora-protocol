// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import "forge-std/Test.sol";
import {ProtocolRewards} from "@zoralabs/protocol-rewards/src/ProtocolRewards.sol";
import {ZoraCreator1155Impl} from "../../src/nft/ZoraCreator1155Impl.sol";
import {Zora1155} from "../../src/proxies/Zora1155.sol";
import {IZoraCreator1155Errors} from "../../src/interfaces/IZoraCreator1155Errors.sol";
import {IZoraCreator1155TypesV1} from "../../src/nft/IZoraCreator1155TypesV1.sol";
import {ICreatorRoyaltiesControl} from "../../src/interfaces/ICreatorRoyaltiesControl.sol";
import {IZoraCreator1155Factory} from "../../src/interfaces/IZoraCreator1155Factory.sol";
import {IMintFeeManager} from "../../src/interfaces/IMintFeeManager.sol";
import {SimpleMinter} from "../mock/SimpleMinter.sol";

contract CreatorRoyaltiesControlTest is Test {
    ProtocolRewards internal protocolRewards;
    ZoraCreator1155Impl internal zoraCreator1155Impl;
    ZoraCreator1155Impl internal target;
    address payable internal admin;
    address internal recipient;
    uint256 internal adminRole;
    uint256 internal minterRole;
    uint256 internal fundsManagerRole;

    function setUp() external {
        protocolRewards = new ProtocolRewards();
        admin = payable(vm.addr(0x1));
        recipient = vm.addr(0x2);
    }

    function _emptyInitData() internal pure returns (bytes[] memory response) {
        response = new bytes[](0);
    }

    /// @notice Returns the supply royalty information for a given token.
    /// @param tokenId The token ID to get the royalty information for.
    /// @param mintAmount The amount of tokens being minted.
    /// @param totalSupply The total supply of the token,
    function supplyRoyaltyInfo(uint256 tokenId, uint256 totalSupply, uint256 mintAmount) public view returns (address receiver, uint256 royaltyAmount) {
        ICreatorRoyaltiesControl.RoyaltyConfiguration memory config = target.getRoyalties(tokenId);
        if (config.royaltyMintSchedule == 0) {
            return (config.royaltyRecipient, 0);
        }
        uint256 totalRoyaltyMints = (mintAmount + (totalSupply % config.royaltyMintSchedule)) / (config.royaltyMintSchedule - 1);
        return (config.royaltyRecipient, totalRoyaltyMints);
    }

    function test_GetsRoyaltiesInfoGlobalDefault() external {
        address royaltyPayout = address(0x999);

        zoraCreator1155Impl = new ZoraCreator1155Impl(recipient, address(0), address(protocolRewards));
        target = ZoraCreator1155Impl(address(new Zora1155(address(zoraCreator1155Impl))));
        adminRole = target.PERMISSION_BIT_ADMIN();
        target.initialize("", "test", ICreatorRoyaltiesControl.RoyaltyConfiguration(10, 10, address(royaltyPayout)), admin, _emptyInitData());

        vm.prank(admin);
        uint256 tokenId = target.setupNewToken("test", 100);

        (address royaltyRecipient, uint256 amount) = target.royaltyInfo(tokenId, 1 ether);
        (, uint256 supplyAmount) = supplyRoyaltyInfo(tokenId, 0, 100);
        assertEq(amount, 0.001 ether);
        assertEq(royaltyRecipient, royaltyPayout);
        assertEq(supplyAmount, 11);
    }

    function test_GetsRoyaltiesInfoSpecificToken() external {
        address royaltyPayout = address(0x999);
        zoraCreator1155Impl = new ZoraCreator1155Impl(recipient, address(0), address(protocolRewards));
        target = ZoraCreator1155Impl(address(new Zora1155(address(zoraCreator1155Impl))));
        adminRole = target.PERMISSION_BIT_ADMIN();
        target.initialize("", "test", ICreatorRoyaltiesControl.RoyaltyConfiguration(100, 10, address(royaltyPayout)), admin, _emptyInitData());

        vm.startPrank(admin);
        uint256 tokenIdFirst = target.setupNewToken("test", 100);
        uint256 tokenIdSecond = target.setupNewToken("test", 100);

        target.updateRoyaltiesForToken(tokenIdSecond, ICreatorRoyaltiesControl.RoyaltyConfiguration(10, 100, address(0x992)));

        vm.stopPrank();

        (address royaltyRecipient, uint256 amount) = target.royaltyInfo(tokenIdFirst, 1 ether);
        (, uint256 supplyAmount) = supplyRoyaltyInfo(tokenIdFirst, 0, 100);
        assertEq(amount, 0.001 ether);
        assertEq(supplyAmount, 1);
        assertEq(royaltyRecipient, royaltyPayout);

        (address royaltyRecipientSecond, uint256 amountSecond) = target.royaltyInfo(tokenIdSecond, 1 ether);
        (, uint256 supplyAmountSecond) = supplyRoyaltyInfo(tokenIdSecond, 0, 100);
        assertEq(amountSecond, 0.01 ether);
        assertEq(supplyAmountSecond, 11);
        assertEq(royaltyRecipientSecond, address(0x992));
    }
}
