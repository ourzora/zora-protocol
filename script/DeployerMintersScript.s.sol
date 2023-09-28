// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "forge-std/Script.sol";
import "forge-std/console2.sol";

import {ZoraDeployerBase} from "./ZoraDeployerBase.sol";
import {ZoraDeployerUtils} from "../src/deployment/ZoraDeployerUtils.sol";
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

contract DeployerMintersScript is ZoraDeployerBase {
    function run() public returns (string memory) {
        Deployment memory deployment;
        ChainConfig memory chainConfig = getChainConfig();

        console2.log("zoraFeeAmount", chainConfig.mintFeeAmount);
        console2.log("zoraFeeRecipient", chainConfig.mintFeeRecipient);
        console2.log("factoryOwner", chainConfig.factoryOwner);
        console2.log("protocolRewards", chainConfig.protocolRewards);

        address deployer = vm.envAddress("DEPLOYER");

        vm.startBroadcast(deployer);

        address fixedPriceMinter = ZoraDeployerUtils.IMMUTABLE_CREATE2_FACTORY.safeCreate2(
            bytes32(0x0000000000000000000000000000000000000000000000000000000000000000),
            type(ZoraCreatorFixedPriceSaleStrategy).creationCode
        );

        address merkleMinter = ZoraDeployerUtils.IMMUTABLE_CREATE2_FACTORY.safeCreate2(
            bytes32(0x0000000000000000000000000000000000000000000000000000000000000000),
            type(ZoraCreatorMerkleMinterStrategy).creationCode
        );

        address redeemMinterFactory = ZoraDeployerUtils.IMMUTABLE_CREATE2_FACTORY.safeCreate2(
            bytes32(0x0000000000000000000000000000000000000000000000000000000000000000),
            type(ZoraCreatorRedeemMinterFactory).creationCode
        );

        deployment.fixedPriceSaleStrategy = address(fixedPriceMinter);
        deployment.merkleMintSaleStrategy = address(merkleMinter);
        deployment.redeemMinterFactory = address(redeemMinterFactory);

        string memory json = getDeploymentJSON(deployment);

        vm.writeFile(string.concat("addresses/", vm.toString(chainId()), ".json"), json);

        return json;
    }
}
