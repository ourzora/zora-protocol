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
import {ZoraCreatorBurnToRedeemMinterStrategy} from "../../../src/minters/burn-to-redeem/ZoraCreatorBurnToRedeemMinterStrategy.sol";
import {ZoraCreatorBurnToRedeemMinterFactoryImpl} from "../../../src/minters/burn-to-redeem/ZoraCreatorBurnToRedeemMinterFactoryImpl.sol";
import {ZoraBurnToRedeemMinterFactory} from "../../../src/proxies/ZoraBurnToRedeemMinterFactory.sol";

contract ZoraCreatorBurnToRedeemMinterFactoryTest is Test {
    ZoraCreator1155Impl internal target;
    ZoraCreatorBurnToRedeemMinterFactoryImpl internal minterFactory;
    address internal tokenAdmin = address(0x999);
    address internal factoryAdmin = address(0x888);

    event MinterCreated(address minter);

    function setUp() public {
        bytes[] memory emptyData = new bytes[](0);
        ZoraCreator1155Impl targetImpl = new ZoraCreator1155Impl(0, address(0));
        Zora1155 proxy = new Zora1155(address(targetImpl));
        target = ZoraCreator1155Impl(address(proxy));
        target.initialize("test", ICreatorRoyaltiesControl.RoyaltyConfiguration(0, 0, address(0)), tokenAdmin, emptyData);

        vm.startPrank(factoryAdmin);
        ZoraCreatorBurnToRedeemMinterFactoryImpl minterFactoryImpl = new ZoraCreatorBurnToRedeemMinterFactoryImpl();
        ZoraBurnToRedeemMinterFactory factoryProxy = new ZoraBurnToRedeemMinterFactory(address(minterFactoryImpl), "");
        minterFactory = ZoraCreatorBurnToRedeemMinterFactoryImpl(address(factoryProxy));
        minterFactory.initialize(factoryAdmin);
        vm.stopPrank();
    }

    function test_contractVersion() public {
        assertEq(minterFactory.contractVersion(), "0.0.1");
    }

    function test_createMinter() public {
        vm.startPrank(tokenAdmin);
        bytes32 salt = keccak256(abi.encodePacked("test"));
        vm.expectEmit(false, false, false, false);
        emit MinterCreated(minterFactory.predictMinterAddress(address(target), salt));
        ZoraCreatorBurnToRedeemMinterStrategy minter = ZoraCreatorBurnToRedeemMinterStrategy(minterFactory.createMinter(address(target), salt));
        vm.stopPrank();

        assertEq(minter.contractVersion(), "0.0.1");
    }

    function test_createMinterRequiresIZoraCreator1155Support() public {
        ERC1155PresetMinterPauser randomToken = new ERC1155PresetMinterPauser("https://uri.com");

        vm.startPrank(tokenAdmin);
        bytes32 salt = keccak256(abi.encodePacked("test"));
        vm.expectRevert(abi.encodeWithSignature("ContractNotZoraCreator1155()"));
        ZoraCreatorBurnToRedeemMinterStrategy minter = ZoraCreatorBurnToRedeemMinterStrategy(minterFactory.createMinter(address(randomToken), salt));
        vm.stopPrank();
    }

    function test_createMinterRequiresAdminCaller() public {
        bytes32 salt = keccak256(abi.encodePacked("test"));
        vm.expectRevert(abi.encodeWithSignature("CallerNotAdmin()"));
        ZoraCreatorBurnToRedeemMinterStrategy minter = ZoraCreatorBurnToRedeemMinterStrategy(minterFactory.createMinter(address(target), salt));
    }

    function test_createMinterCannotBeCalledTwice() public {
        vm.startPrank(tokenAdmin);
        bytes32 salt = keccak256(abi.encodePacked("test"));
        ZoraCreatorBurnToRedeemMinterStrategy minter = ZoraCreatorBurnToRedeemMinterStrategy(minterFactory.createMinter(address(target), salt));
        vm.expectRevert(abi.encodeWithSignature("MinterContractAlreadyExists()"));
        minter = ZoraCreatorBurnToRedeemMinterStrategy(minterFactory.createMinter(address(target), salt));
        vm.stopPrank();
    }

    function test_predictMinterAddress() public {
        vm.startPrank(tokenAdmin);
        bytes32 salt = keccak256(abi.encodePacked("test"));
        ZoraCreatorBurnToRedeemMinterStrategy minter = ZoraCreatorBurnToRedeemMinterStrategy(minterFactory.createMinter(address(target), salt));
        vm.stopPrank();

        assertEq(address(minter), minterFactory.predictMinterAddress(address(target), salt));
    }

    function test_getDeployedMinterForCreatorContract() public {
        vm.startPrank(tokenAdmin);
        bytes32 salt = keccak256(abi.encodePacked("test"));
        ZoraCreatorBurnToRedeemMinterStrategy minter = ZoraCreatorBurnToRedeemMinterStrategy(minterFactory.createMinter(address(target), salt));
        vm.stopPrank();

        assertEq(address(minter), minterFactory.getDeployedMinterForCreatorContract(address(target)));
    }
}
