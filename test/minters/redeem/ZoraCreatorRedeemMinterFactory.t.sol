// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import "forge-std/Test.sol";
import {ERC20PresetMinterPauser} from "@openzeppelin/contracts/token/ERC20/presets/ERC20PresetMinterPauser.sol";
import {ERC721PresetMinterPauserAutoId} from "@openzeppelin/contracts/token/ERC721/presets/ERC721PresetMinterPauserAutoId.sol";
import {ERC1155PresetMinterPauser} from "@openzeppelin/contracts/token/ERC1155/presets/ERC1155PresetMinterPauser.sol";

import {ZoraCreator1155Impl} from "../../../src/nft/ZoraCreator1155Impl.sol";
import {Zora1155} from "../../../src/proxies/Zora1155.sol";
import {IZoraCreator1155} from "../../../src/interfaces/IZoraCreator1155.sol";
import {IRenderer1155} from "../../../src/interfaces/IRenderer1155.sol";
import {ICreatorRoyaltiesControl} from "../../../src/interfaces/ICreatorRoyaltiesControl.sol";
import {IZoraCreator1155Factory} from "../../../src/interfaces/IZoraCreator1155Factory.sol";
import {ZoraCreatorRedeemMinterStrategy} from "../../../src/minters/redeem/ZoraCreatorRedeemMinterStrategy.sol";
import {ZoraCreatorRedeemMinterFactory} from "../../../src/minters/redeem/ZoraCreatorRedeemMinterFactory.sol";

contract ZoraCreatorRedeemMinterFactoryTest is Test {
    ZoraCreator1155Impl internal target;
    ZoraCreatorRedeemMinterFactory internal minterFactory;
    address payable internal tokenAdmin = payable(address(0x999));
    address payable internal factoryAdmin = payable(address(0x888));

    event RedeemMinterDeployed(address indexed creatorContract, address indexed minterContract);

    function setUp() public {
        bytes[] memory emptyData = new bytes[](0);
        ZoraCreator1155Impl targetImpl = new ZoraCreator1155Impl(0, address(0), address(0));
        Zora1155 proxy = new Zora1155(address(targetImpl));
        target = ZoraCreator1155Impl(address(proxy));
        target.initialize("test", "test", ICreatorRoyaltiesControl.RoyaltyConfiguration(0, 0, address(0)), tokenAdmin, emptyData);

        vm.startPrank(factoryAdmin);
        minterFactory = new ZoraCreatorRedeemMinterFactory();
        vm.stopPrank();
    }

    function test_contractVersion() public {
        assertEq(minterFactory.contractVersion(), "0.0.1");
    }

    function test_createMinter() public {
        vm.startPrank(tokenAdmin);
        target.addPermission(0, address(minterFactory), target.PERMISSION_BIT_MINTER());
        address predictedAddress = minterFactory.predictMinterAddress(address(target));
        vm.expectEmit(false, false, false, false);
        emit RedeemMinterDeployed(address(target), predictedAddress);
        target.callSale(0, minterFactory, abi.encodeWithSelector(ZoraCreatorRedeemMinterFactory.createMinter.selector));
        vm.stopPrank();

        ZoraCreatorRedeemMinterStrategy minter = ZoraCreatorRedeemMinterStrategy(predictedAddress);
        assertEq(minter.contractVersion(), "0.0.1");
    }

    function test_createMinterRequiresIZoraCreator1155Caller() public {
        ERC1155PresetMinterPauser randomToken = new ERC1155PresetMinterPauser("https://uri.com");

        vm.expectRevert(abi.encodeWithSignature("CallerNotZoraCreator1155()"));
        vm.prank(address(randomToken));
        minterFactory.createMinter();
    }

    function test_createMinterCannotBeCalledTwice() public {
        vm.startPrank(address(target));
        minterFactory.createMinter();
        vm.expectRevert(abi.encodeWithSignature("MinterContractAlreadyExists()"));
        minterFactory.createMinter();
        vm.stopPrank();
    }

    function test_getDeployedMinterForCreatorContract() public {
        vm.prank(address(target));
        minterFactory.createMinter();
        address minterAddress = minterFactory.predictMinterAddress(address(target));

        assertEq(minterAddress, minterFactory.getDeployedRedeemMinterForCreatorContract(address(target)));
    }
}
