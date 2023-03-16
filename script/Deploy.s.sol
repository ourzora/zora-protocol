// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "forge-std/Script.sol";
import "forge-std/console2.sol";

import {ZoraCreator1155FactoryImpl} from "../src/factory/ZoraCreator1155FactoryImpl.sol";
import {Zora1155Factory} from "../src/proxies/Zora1155Factory.sol";
import {ZoraCreator1155Impl} from "../src/nft/ZoraCreator1155Impl.sol";
import {ICreatorRoyaltiesControl} from "../src/interfaces/ICreatorRoyaltiesControl.sol";
import {IZoraCreator1155Factory} from "../src/interfaces/IZoraCreator1155Factory.sol";
import {IMinter1155} from "../src/interfaces/IMinter1155.sol";
import {IZoraCreator1155} from "../src/interfaces/IZoraCreator1155.sol";
import {ZoraCreatorFixedPriceSaleStrategy} from "../src/minters/fixed-price/ZoraCreatorFixedPriceSaleStrategy.sol";
import {ZoraCreatorMerkleMinterStrategy} from "../src/minters/merkle/ZoraCreatorMerkleMinterStrategy.sol";


contract DeployScript is Script {
    function setUp() public {}

    function run() public {
        address payable deployer = payable(vm.envAddress("DEPLOYER"));
        vm.startBroadcast(deployer);

        ZoraCreatorFixedPriceSaleStrategy fixedPricedMinter = new ZoraCreatorFixedPriceSaleStrategy();
        ZoraCreatorMerkleMinterStrategy merkleMinter = new ZoraCreatorMerkleMinterStrategy();

        ZoraCreator1155Impl creatorImpl = new ZoraCreator1155Impl(100, deployer);

        ZoraCreator1155FactoryImpl factoryImpl = new ZoraCreator1155FactoryImpl({
            _implementation: creatorImpl,
            _merkleMinter: merkleMinter,
            _fixedPriceMinter: fixedPricedMinter
        });

        Zora1155Factory factoryProxy = new Zora1155Factory(
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
                "ipfs://bafybeicgolwqpozsc7iwgytavete56a2nnytzix2nb2rxefdvbtwwtnnoe/metadata",
                "testing contract",
                ICreatorRoyaltiesControl.RoyaltyConfiguration({royaltyBPS: 0, royaltyRecipient: address(0), royaltyMintSchedule: 0}),
                deployer,
                initUpdate
            )
        );

        console2.log("New 1155 contract address", newContract);
    }
}
