// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "forge-std/Script.sol";
import "forge-std/console2.sol";

import {ZoraCreator1155FactoryImpl} from "../src/factory/ZoraCreator1155FactoryImpl.sol";
import {ZoraCreator1155FactoryProxy} from "../src/proxies/ZoraCreator1155FactoryProxy.sol";
import {ZoraCreator1155Impl} from "../src/nft/ZoraCreator1155Impl.sol";
import {ICreatorRoyaltiesControl} from "../src/interfaces/ICreatorRoyaltiesControl.sol";
import {IZoraCreator1155Factory} from "../src/interfaces/IZoraCreator1155Factory.sol";
import {IZoraCreator1155} from "../src/interfaces/IZoraCreator1155.sol";

contract DeployScript is Script {
    function setUp() public {}

    function run() public {
        address deployer = vm.envAddress("DEPLOYER");
        vm.startBroadcast(deployer);
        ZoraCreator1155Impl creatorImpl = new ZoraCreator1155Impl(100, deployer);
        ZoraCreator1155FactoryImpl factoryImpl = new ZoraCreator1155FactoryImpl(creatorImpl);
        ZoraCreator1155FactoryProxy factoryProxy = new ZoraCreator1155FactoryProxy(
            address(factoryImpl),
            abi.encodeWithSelector(ZoraCreator1155FactoryImpl.initialize.selector, deployer)
        );

        console2.log("Factory Proxy", address(factoryProxy));
        console2.log("Implementation Address", address(creatorImpl));

        bytes[] memory initUpdate = new bytes[](4);
        initUpdate[0] = abi.encodeWithSelector(ZoraCreator1155Impl.setupNewToken.selector, "https://", 100);
        initUpdate[1] = abi.encodeWithSelector(ZoraCreator1155Impl.adminMint.selector, deployer, 1, 100, "");
        initUpdate[2] = abi.encodeWithSelector(ZoraCreator1155Impl.setupNewToken.selector, "https://", 100);
        initUpdate[3] = abi.encodeWithSelector(ZoraCreator1155Impl.adminMint.selector, deployer, 2, 10, "");
        address newContract = address(
            IZoraCreator1155Factory(address(factoryProxy)).createContract(
                "",
                ICreatorRoyaltiesControl.RoyaltyConfiguration({royaltyBPS: 0, royaltyRecipient: address(0)}),
                deployer,
                initUpdate
            )
        );

        console2.log("New 1155 contract address", newContract);
    }
}
