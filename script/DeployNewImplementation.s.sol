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
import {IMinter1155} from "../src/interfaces/IMinter1155.sol";
import {ZoraCreatorFixedPriceSaleStrategy} from "../src/minters/fixed-price/ZoraCreatorFixedPriceSaleStrategy.sol";
import {ZoraCreatorMerkleMinterStrategy} from "../src/minters/merkle/ZoraCreatorMerkleMinterStrategy.sol";
import {ZoraCreatorRedeemMinterFactory} from "../src/minters/redeem/ZoraCreatorRedeemMinterFactory.sol";
import {ZoraDeployerUtils} from "../src/deployment/ZoraDeployerUtils.sol";

contract DeployNewImplementations is ZoraDeployerBase {
    function run() public returns (string memory) {
        Deployment memory deployment = getDeployment();
        ChainConfig memory chainConfig = getChainConfig();

        console2.log("zoraFeeAmount", chainConfig.mintFeeAmount);
        console2.log("zoraFeeRecipient", chainConfig.mintFeeRecipient);
        console2.log("factoryOwner", chainConfig.factoryOwner);
        console2.log("protocolRewards", chainConfig.protocolRewards);

        uint256 deployerPrivateKey = vm.envUint("DEPLOYER_PRIVATE_KEY");

        vm.startBroadcast(deployerPrivateKey);

        (address factoryImplAddress, address contract1155ImplAddress) = ZoraDeployerUtils.deployNew1155AndFactoryImpl(
            address(deployment.factoryProxy),
            chainConfig.mintFeeRecipient,
            chainConfig.protocolRewards,
            IMinter1155(deployment.merkleMintSaleStrategy),
            IMinter1155(deployment.redeemMinterFactory),
            IMinter1155(deployment.fixedPriceSaleStrategy)
        );

        deployment.factoryImpl = factoryImplAddress;
        deployment.contract1155Impl = contract1155ImplAddress;

        return getDeploymentJSON(deployment);
    }
}
