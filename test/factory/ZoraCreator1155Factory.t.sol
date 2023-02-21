// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import "forge-std/Test.sol";
import {ZoraCreator1155FactoryImpl} from "../../src/factory/ZoraCreator1155FactoryImpl.sol";
import {ZoraCreator1155Impl} from "../../src/nft/ZoraCreator1155Impl.sol";
import {ZoraCreator1155FactoryProxy} from "../../src/proxies/ZoraCreator1155FactoryProxy.sol";
import {IZoraCreator1155Factory} from "../../src/interfaces/IZoraCreator1155Factory.sol";
import {IZoraCreator1155} from "../../src/interfaces/IZoraCreator1155.sol";
import {IMinter1155} from "../../src/interfaces/IMinter1155.sol";
import {ICreatorRoyaltiesControl} from "../../src/interfaces/ICreatorRoyaltiesControl.sol";

contract ZoraCreator1155FactoryTest is Test {
    ZoraCreator1155FactoryImpl internal factory;

    function setUp() external {
        ZoraCreator1155Impl zoraCreator1155Impl = new ZoraCreator1155Impl(0, address(0));
        factory = new ZoraCreator1155FactoryImpl(zoraCreator1155Impl, IMinter1155(address(0)), IMinter1155(address(0)));
    }

    function test_initialize(address initialOwner) external {
        vm.assume(initialOwner != address(0));
        address payable proxyAddress = payable(address(new ZoraCreator1155FactoryProxy(address(factory))));
        ZoraCreator1155FactoryImpl proxy = ZoraCreator1155FactoryImpl(proxyAddress);
        proxy.initialize(initialOwner);
        assertEq(proxy.owner(), initialOwner);
    }

    function test_createContract(
        string memory contractURI,
        uint32 royaltyBPS,
        address royaltyRecipient,
        address admin
    ) external {
        address deployedAddress = factory.createContract(
            contractURI,
            ICreatorRoyaltiesControl.RoyaltyConfiguration(royaltyBPS, royaltyRecipient),
            admin,
            new bytes[](0)
        );
        ZoraCreator1155Impl target = ZoraCreator1155Impl(deployedAddress);
        // TODO: test URI when metadata functions are complete
        // assertEq(zoraCreator1155.uri(0), contractURI);
        ICreatorRoyaltiesControl.RoyaltyConfiguration memory config = target.getRoyalties(0);
        assertEq(config.royaltyBPS, royaltyBPS);
        assertEq(config.royaltyRecipient, royaltyRecipient);
        assertEq(target.getPermissions(0, admin), target.PERMISSION_BIT_ADMIN());
    }
}
