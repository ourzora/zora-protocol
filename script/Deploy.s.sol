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
import {IZoraCreator1155} from "../src/interfaces/IZoraCreator1155.sol";
import {ZoraCreatorFixedPriceSaleStrategy} from "../src/minters/fixed-price/ZoraCreatorFixedPriceSaleStrategy.sol";
import {ZoraCreatorMerkleMinterStrategy} from "../src/minters/merkle/ZoraCreatorMerkleMinterStrategy.sol";
import {ZoraCreatorRedeemMinterFactory} from "../src/minters/redeem/ZoraCreatorRedeemMinterFactory.sol";

contract DeployScript is ZoraDeployerBase {
    function run() public returns (string memory) {
        Deployment memory deployment;
        ChainConfig memory chainConfig = getChainConfig();

        console2.log("zoraFeeAmount", chainConfig.mintFeeAmount);
        console2.log("zoraFeeRecipient", chainConfig.mintFeeRecipient);
        console2.log("factoryOwner", chainConfig.factoryOwner);
        console2.log("protocolRewards", chainConfig.protocolRewards);

        address deployer = vm.envAddress("DEPLOYER");

        vm.startBroadcast(deployer);

        ZoraCreatorFixedPriceSaleStrategy fixedPricedMinter = new ZoraCreatorFixedPriceSaleStrategy();
        ZoraCreatorMerkleMinterStrategy merkleMinter = new ZoraCreatorMerkleMinterStrategy();
        ZoraCreatorRedeemMinterFactory redeemMinterFactory = new ZoraCreatorRedeemMinterFactory();

        deployment.fixedPriceSaleStrategy = address(fixedPricedMinter);
        deployment.merkleMintSaleStrategy = address(merkleMinter);
        deployment.redeemMinterFactory = address(redeemMinterFactory);

        // deployNew1155AndFactoryProxy(deployment, deployer);

        // deployTestContractForVerification(deployment.factoryProxy, chainConfig.factoryOwner);

        return getDeploymentJSON(deployment);
    }
}
