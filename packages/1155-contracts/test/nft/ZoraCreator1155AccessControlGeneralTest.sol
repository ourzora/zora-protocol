// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import "forge-std/Test.sol";
import {ProtocolRewards} from "@zoralabs/protocol-rewards/src/ProtocolRewards.sol";
import {ZoraCreator1155Impl} from "../../src/nft/ZoraCreator1155Impl.sol";
import {Zora1155} from "../../src/proxies/Zora1155.sol";
import {IZoraCreator1155Errors} from "../../src/interfaces/IZoraCreator1155Errors.sol";
import {IRenderer1155} from "../../src/interfaces/IRenderer1155.sol";
import {IMinter1155} from "../../src/interfaces/IMinter1155.sol";
import {IZoraCreator1155TypesV1} from "../../src/nft/IZoraCreator1155TypesV1.sol";
import {ICreatorRoyaltiesControl} from "../../src/interfaces/ICreatorRoyaltiesControl.sol";
import {IZoraCreator1155Factory} from "../../src/interfaces/IZoraCreator1155Factory.sol";
import {ICreatorRendererControl} from "../../src/interfaces/ICreatorRendererControl.sol";
import {SimpleMinter} from "../mock/SimpleMinter.sol";
import {SimpleRenderer} from "../mock/SimpleRenderer.sol";

contract ZoraCreator1155AccessControlGeneralTest is Test {
    ProtocolRewards internal protocolRewards;
    ZoraCreator1155Impl internal zoraCreator1155Impl;
    ZoraCreator1155Impl internal target;
    address payable admin;
    address internal zora;
    uint256 initialTokenId = 777;
    uint256 initialTokenPrice = 0.000777 ether;

    function setUp() external {
        zora = makeAddr("zora");
        protocolRewards = new ProtocolRewards();
        zoraCreator1155Impl = new ZoraCreator1155Impl(zora, address(0x1234), address(protocolRewards), makeAddr("timedSaleStrategy"));
        target = ZoraCreator1155Impl(payable(address(new Zora1155(address(zoraCreator1155Impl)))));
        admin = payable(address(0x9));
        target.initialize("", "test", ICreatorRoyaltiesControl.RoyaltyConfiguration(0, 0, address(0)), admin, _emptyInitData());
        vm.prank(admin);
        target.setupNewToken("test_uri", 100);
    }

    function _emptyInitData() internal pure returns (bytes[] memory response) {
        response = new bytes[](0);
    }

    function test_openAccessFails_initialize() public {
        vm.expectRevert();
        target.initialize("", "test", ICreatorRoyaltiesControl.RoyaltyConfiguration(0, 0, address(0)), admin, _emptyInitData());
    }

    function test_openAccessFails_updateRoyaltiesForToken() public {
        vm.expectRevert();
        target.updateRoyaltiesForToken(0, ICreatorRoyaltiesControl.RoyaltyConfiguration(0, 0, address(0)));
    }

    function test_openAccessFails_assumeLastTokenIdMatches() public {
        vm.expectRevert();
        target.assumeLastTokenIdMatches(999);
    }

    function test_openAccessFails_reduceSupply() public {
        vm.expectRevert();
        target.reduceSupply(1, 100);
    }

    function test_openAccessFails_isAdminOrRole() public {
        assertFalse(target.isAdminOrRole(address(0), 0, 1));
    }

    function test_openAccessFails_setupNewToken() public {
        vm.expectRevert();
        target.setupNewToken("", 100);
    }

    function test_openAccessFails_updateTokenURI() public {
        vm.expectRevert();
        target.updateTokenURI(1, "newuri");
    }

    function test_openAccessFails_updateContractMetadata() public {
        vm.expectRevert();
        target.updateContractMetadata("asdf", "new");
    }

    function test_openAccessFails_addPermission() public {
        vm.expectRevert();
        target.addPermission(0, address(0x100), 1);
    }

    function test_openAccessFails_removePermission() public {
        vm.expectRevert();
        target.removePermission(0, address(0x100), 1);
    }

    function test_openAccessFails_setOwner() public {
        vm.expectRevert();
        target.setOwner(address(0x123));
    }

    function test_openAccessFails_adminMint() public {
        vm.expectRevert();
        target.adminMint(address(0x012), 1, 10, "");
    }

    function test_openAccessFails_mint() public {
        SimpleMinter minter = new SimpleMinter();
        vm.expectRevert();
        target.mint(IMinter1155(address(minter)), 1, 1, new address[](1), "");
    }

    function test_openAccessFails_setTokenMetadataRenderer() public {
        SimpleRenderer renderer = new SimpleRenderer();
        vm.expectRevert();
        target.setTokenMetadataRenderer(0, renderer);
    }

    // Get token info is a public getter. Skipping here.

    function test_openAccessFails_callSale() public {
        SimpleMinter minter = new SimpleMinter();

        vm.expectRevert();
        target.callSale(10, minter, "");
    }

    function test_openAccessFails_callRenderer() public {
        SimpleRenderer renderer = new SimpleRenderer();
        vm.prank(admin);
        target.setTokenMetadataRenderer(1, renderer);

        vm.expectRevert();
        target.callRenderer(10, abi.encodeWithSelector(SimpleRenderer.setup.selector, "hello"));
    }

    // Supports interface is a public getter. Skipping here.

    function test_openAccessFails_burnBatch() public {
        vm.prank(admin);
        target.adminMint(address(0x123), 1, 10, "");

        uint256[] memory tokenIds = new uint256[](1);
        uint256[] memory quantities = new uint256[](1);
        tokenIds[0] = 1;
        quantities[0] = 1;

        vm.expectRevert();
        target.burnBatch(address(0), tokenIds, quantities);
    }

    // contract URI is a public getter

    function test_openAccessFails_withdrawCustom() public {
        vm.deal(address(target), 1 ether);

        vm.expectRevert();
        target.withdraw();
    }
}
