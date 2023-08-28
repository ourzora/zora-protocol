// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "forge-std/Script.sol";
import "forge-std/console2.sol";

import {ZoraDeployerBase} from "./ZoraDeployerBase.sol";
import {ChainConfig, Deployment} from "../src/deployment/DeploymentConfig.sol";

import {ZoraCreator1155FactoryImpl} from "../src/factory/ZoraCreator1155FactoryImpl.sol";
import {Zora1155Factory} from "../src/proxies/Zora1155Factory.sol";
import {ZoraCreator1155Impl} from "../src/nft/ZoraCreator1155Impl.sol";
import {ICreatorRoyaltiesControl} from "../src/interfaces/ICreatorRoyaltiesControl.sol";
import {IZoraCreator1155Factory} from "../src/interfaces/IZoraCreator1155Factory.sol";
import {IMinter1155} from "../src/interfaces/IMinter1155.sol";
import {IZoraCreator1155} from "../src/interfaces/IZoraCreator1155.sol";
import {ProxyShim} from "../src/utils/ProxyShim.sol";
import {ZoraCreatorFixedPriceSaleStrategy} from "../src/minters/fixed-price/ZoraCreatorFixedPriceSaleStrategy.sol";
import {ZoraCreatorMerkleMinterStrategy} from "../src/minters/merkle/ZoraCreatorMerkleMinterStrategy.sol";
import {ZoraCreatorRedeemMinterFactory} from "../src/minters/redeem/ZoraCreatorRedeemMinterFactory.sol";

contract DeployScript is ZoraDeployerBase {
    address deployer;
    uint256 deployerPK;

    function setUp() public {
        deployer = vm.envAddress("DEPLOYER");
        deployerPK = vm.envUint("DEPLOYER_PK");
    }

    function run() public {
        Deployment memory deployment = getDeployment();
        ChainConfig memory chainConfig = getChainConfig();

        console2.log("~~~ CHAIN CONFIG ~~~");
        console2.log("chainId", chainId());
        console2.log("protocolRewards", chainConfig.protocolRewards);

        console2.log("");

        ZoraCreatorFixedPriceSaleStrategy fixedPricedMinter =
            ZoraCreatorFixedPriceSaleStrategy(deployment.fixedPriceSaleStrategy);
        ZoraCreatorMerkleMinterStrategy merkleMinter =
            ZoraCreatorMerkleMinterStrategy(deployment.merkleMintSaleStrategy);
        ZoraCreatorRedeemMinterFactory redeemMinterFactory =
            ZoraCreatorRedeemMinterFactory(deployment.redeemMinterFactory);

        vm.startBroadcast(deployerPK);

        ZoraCreator1155Impl creatorImpl =
        new ZoraCreator1155Impl(chainConfig.mintFeeAmount, chainConfig.mintFeeRecipient, deployment.factoryProxy, chainConfig.protocolRewards);

        ZoraCreator1155FactoryImpl newFactoryImpl = new ZoraCreator1155FactoryImpl({
            _implementation: creatorImpl,
            _merkleMinter: merkleMinter,
            _redeemMinterFactory: redeemMinterFactory,
            _fixedPriceMinter: fixedPricedMinter
        });

        vm.stopBroadcast();

        console2.log("");
        console2.log("SAFE:", chainConfig.factoryOwner);
        console2.log("PROXY:", deployment.factoryProxy);
        console2.log("NEW FACTORY IMPL:", address(newFactoryImpl));
        console2.log("NEW 1155 IMPL:", address(creatorImpl));
    }
}
