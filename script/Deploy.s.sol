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
        uint256 zoraFeeAmount = vm.envUint("ZORA_FEE_AMOUNT");
        address payable zoraFeeRecipient = payable(vm.envAddress("ZORA_FEE_RECIPIENT"));
        address factoryAdmin = payable(vm.envAddress("FACTORY_ADMIN"));
        vm.startBroadcast(deployer);

        ZoraCreatorFixedPriceSaleStrategy fixedPricedMinter = new ZoraCreatorFixedPriceSaleStrategy();
        ZoraCreatorMerkleMinterStrategy merkleMinter = new ZoraCreatorMerkleMinterStrategy();

        ZoraCreator1155Impl creatorImpl = new ZoraCreator1155Impl(zoraFeeAmount, zoraFeeRecipient);

        ZoraCreator1155FactoryImpl factoryImpl = new ZoraCreator1155FactoryImpl({
            _implementation: creatorImpl,
            _merkleMinter: merkleMinter,
            _fixedPriceMinter: fixedPricedMinter
        });

        Zora1155Factory factoryProxy = new Zora1155Factory(
            address(factoryImpl),
            abi.encodeWithSelector(ZoraCreator1155FactoryImpl.initialize.selector, factoryAdmin)
        );

        console2.log("Factory Proxy", address(factoryProxy));
        console2.log("Implementation Address", address(creatorImpl));

        bytes[] memory initUpdate = new bytes[](2);
        initUpdate[0] = abi.encodeWithSelector(
            ZoraCreator1155Impl.setupNewToken.selector,
            "ipfs://bafkreigu544g6wjvqcysurpzy5pcskbt45a5f33m6wgythpgb3rfqi3lzi",
            100
        );
        initUpdate[1] = abi.encodeWithSelector(
            ZoraCreator1155Impl.adminMint.selector,
            factoryAdmin,
            1,
            100,
            "ipfs://bafkreihjgdf6njqjchxbwwbwzvetrnlvsuyqllanc7g2azhy4hvaqhuqd4"
        );
        address newContract = address(
            IZoraCreator1155Factory(address(factoryProxy)).createContract(
                "ipfs://bafybeicgolwqpozsc7iwgytavete56a2nnytzix2nb2rxefdvbtwwtnnoe/metadata",
                unicode"🪄",
                ICreatorRoyaltiesControl.RoyaltyConfiguration({royaltyBPS: 0, royaltyRecipient: address(0), royaltyMintSchedule: 0}),
                payable(factoryAdmin),
                initUpdate
            )
        );

        console2.log("New 1155 contract address", newContract);
    }
}
