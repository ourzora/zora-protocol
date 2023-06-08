// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import "forge-std/Test.sol";
import {ZoraCreator1155FactoryImpl} from "../../src/factory/ZoraCreator1155FactoryImpl.sol";
import {ZoraCreator1155Impl} from "../../src/nft/ZoraCreator1155Impl.sol";
import {Zora1155Factory} from "../../src/proxies/Zora1155Factory.sol";
import {IZoraCreator1155Factory} from "../../src/interfaces/IZoraCreator1155Factory.sol";
import {IZoraCreator1155} from "../../src/interfaces/IZoraCreator1155.sol";
import {IMinter1155} from "../../src/interfaces/IMinter1155.sol";
import {ICreatorRoyaltiesControl} from "../../src/interfaces/ICreatorRoyaltiesControl.sol";
import {MockContractMetadata} from "../mock/MockContractMetadata.sol";

contract ZoraCreator1155FactoryTest is Test {
    ZoraCreator1155FactoryImpl internal factory;

    function setUp() external {
        ZoraCreator1155Impl zoraCreator1155Impl = new ZoraCreator1155Impl(0, address(0), address(0));
        factory = new ZoraCreator1155FactoryImpl(zoraCreator1155Impl, IMinter1155(address(1)), IMinter1155(address(2)), IMinter1155(address(3)));
    }

    function test_contractVersion() external {
        assertEq(factory.contractVersion(), "1.3.1");
    }

    function test_contractName() external {
        assertEq(factory.contractName(), "ZORA 1155 Contract Factory");
    }

    function test_contractURI() external {
        assertEq(factory.contractURI(), "https://github.com/ourzora/zora-1155-contracts/");
    }

    function test_initialize(address initialOwner) external {
        vm.assume(initialOwner != address(0));
        address payable proxyAddress = payable(
            address(new Zora1155Factory(address(factory), abi.encodeWithSelector(ZoraCreator1155FactoryImpl.initialize.selector, initialOwner)))
        );
        ZoraCreator1155FactoryImpl proxy = ZoraCreator1155FactoryImpl(proxyAddress);
        assertEq(proxy.owner(), initialOwner);
    }

    function test_defaultMinters() external {
        IMinter1155[] memory minters = factory.defaultMinters();
        assertEq(minters.length, 3);
        assertEq(address(minters[0]), address(2));
        assertEq(address(minters[1]), address(1));
        assertEq(address(minters[2]), address(3));
    }

    function test_createContract(
        string memory contractURI,
        string memory name,
        uint32 royaltyBPS,
        uint32 royaltyMintSchedule,
        address royaltyRecipient,
        address payable admin
    ) external {
        // If the factory is the admin, the admin flag is cleared
        // during multicall breaking a further test assumption.
        // Additionally, this case makes no sense from a user perspective.
        vm.assume(admin != payable(address(factory)));
        vm.assume(royaltyMintSchedule != 1);
        // Assume royalty recipient is not 0
        vm.assume(royaltyRecipient != payable(address(0)));
        bytes[] memory initSetup = new bytes[](1);
        initSetup[0] = abi.encodeWithSelector(IZoraCreator1155.setupNewToken.selector, "ipfs://asdfadsf", 100);
        address deployedAddress = factory.createContract(
            contractURI,
            name,
            ICreatorRoyaltiesControl.RoyaltyConfiguration({
                royaltyBPS: royaltyBPS,
                royaltyRecipient: royaltyRecipient,
                royaltyMintSchedule: royaltyMintSchedule
            }),
            admin,
            initSetup
        );
        ZoraCreator1155Impl target = ZoraCreator1155Impl(deployedAddress);

        ICreatorRoyaltiesControl.RoyaltyConfiguration memory config = target.getRoyalties(0);
        assertEq(config.royaltyMintSchedule, royaltyMintSchedule);
        assertEq(config.royaltyBPS, royaltyBPS);
        assertEq(config.royaltyRecipient, royaltyRecipient);
        assertEq(target.getPermissions(0, admin), target.PERMISSION_BIT_ADMIN());
        assertEq(target.uri(1), "ipfs://asdfadsf");
    }

    function test_upgrade(address initialOwner) external {
        vm.assume(initialOwner != address(0));

        IZoraCreator1155 mockNewContract = IZoraCreator1155(address(0x999));

        ZoraCreator1155FactoryImpl newFactoryImpl = new ZoraCreator1155FactoryImpl(
            mockNewContract,
            IMinter1155(address(0)),
            IMinter1155(address(0)),
            IMinter1155(address(0))
        );

        address payable proxyAddress = payable(
            address(new Zora1155Factory(address(factory), abi.encodeWithSelector(ZoraCreator1155FactoryImpl.initialize.selector, initialOwner)))
        );
        ZoraCreator1155FactoryImpl proxy = ZoraCreator1155FactoryImpl(proxyAddress);
        vm.prank(initialOwner);
        proxy.upgradeTo(address(newFactoryImpl));
        assertEq(address(proxy.implementation()), address(mockNewContract));
    }

    function test_upgradeFailsWithDifferentContractName(address initialOwner) external {
        vm.assume(initialOwner != address(0));

        MockContractMetadata mockContractMetadata = new MockContractMetadata("ipfs://asdfadsf", "name");

        address payable proxyAddress = payable(
            address(new Zora1155Factory(address(factory), abi.encodeWithSelector(ZoraCreator1155FactoryImpl.initialize.selector, initialOwner)))
        );
        ZoraCreator1155FactoryImpl proxy = ZoraCreator1155FactoryImpl(proxyAddress);
        vm.prank(initialOwner);
        vm.expectRevert(abi.encodeWithSignature("UpgradeToMismatchedContractName(string,string)", "ZORA 1155 Contract Factory", "name"));
        proxy.upgradeTo(address(mockContractMetadata));
    }
}
