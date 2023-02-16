// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import "forge-std/Test.sol";
import {ZoraCreator1155Factory} from "../../src/factory/ZoraCreator1155Factory.sol";
import {ZoraCreator1155Impl} from "../../src/nft/ZoraCreator1155Impl.sol";
import {ZoraCreator1155FactoryProxy} from "../../src/proxies/ZoraCreator1155FactoryProxy.sol";
import {IZoraCreator1155Factory} from "../../src/interfaces/IZoraCreator1155Factory.sol";
import {IZoraCreator1155} from "../../src/interfaces/IZoraCreator1155.sol";
import {ICreatorRoyaltiesControl} from "../../src/interfaces/ICreatorRoyaltiesControl.sol";

contract ZoraCreator1155FactoryTest is Test {
    ZoraCreator1155Factory internal factory;

    function setUp() external {
        ZoraCreator1155Impl zoraCreator1155Impl = new ZoraCreator1155Impl(0, address(0));
        factory = new ZoraCreator1155Factory(zoraCreator1155Impl);
    }

    function test_initialize(address initialOwner) external {
        vm.assume(initialOwner != address(0));
        address payable proxyAddress = payable(address(new ZoraCreator1155FactoryProxy(address(factory))));
        ZoraCreator1155Factory proxy = ZoraCreator1155Factory(proxyAddress);
        proxy.initialize(initialOwner);
        assertEq(proxy.owner(), initialOwner);
    }

    function test_createContract(string memory contractURI, uint32 royaltySchedule, address royaltyRecipient, address admin) external {
        address deployedAddress = factory.createContract(
            contractURI,
            ICreatorRoyaltiesControl.RoyaltyConfiguration(royaltySchedule, royaltyRecipient),
            admin,
            new bytes[](0)
        );
        ZoraCreator1155Impl target = ZoraCreator1155Impl(deployedAddress);
        // TODO: test URI when metadata functions are complete
        // assertEq(zoraCreator1155.uri(0), contractURI);
        ICreatorRoyaltiesControl.RoyaltyConfiguration memory config = target.getRoyalties(0);
        assertEq(config.royaltyMintSchedule, royaltySchedule);
        assertEq(config.royaltyRecipient, royaltyRecipient);
        assertEq(target.getPermissions(0, admin), target.PERMISSION_BIT_ADMIN());
    }
}
