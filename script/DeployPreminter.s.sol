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
import {ZoraCreator1155PremintExecutor} from "../src/premint/ZoraCreator1155PremintExecutor.sol";

contract DeployPreminter is ZoraDeployerBase {
    function run() public returns (string memory) {
        Deployment memory deployment = getDeployment();

        uint256 deployerPrivateKey = vm.envUint("DEPLOYER_PRIVATE_KEY");

        // bool deployFactory = vm.envBool("DEPLOY_FACTORY");
        bool deployFactory = vm.envBool("DEPLOY_FACTORY");

        IZoraCreator1155Factory factoryProxy;
        vm.startBroadcast(deployerPrivateKey);

        if (deployFactory) {
            address deployer = vm.envAddress("DEPLOYER");
            address factoryShimAddress = address(new ProxyShim(deployer));
            ChainConfig memory chainConfig = getChainConfig();

            factoryProxy = IZoraCreator1155Factory(address(new Zora1155Factory(factoryShimAddress, "")));

            deployment.factoryProxy = address(factoryProxy);

            ZoraCreator1155Impl creatorImpl = new ZoraCreator1155Impl(
                chainConfig.mintFeeAmount,
                chainConfig.mintFeeRecipient,
                address(factoryProxy),
                chainConfig.protocolRewards
            );

            deployment.contract1155Impl = address(creatorImpl);

            ZoraCreator1155FactoryImpl factoryImpl = new ZoraCreator1155FactoryImpl({
                _implementation: creatorImpl,
                _merkleMinter: IMinter1155(deployment.merkleMintSaleStrategy),
                _redeemMinterFactory: IMinter1155(deployment.redeemMinterFactory),
                _fixedPriceMinter: IMinter1155(deployment.fixedPriceSaleStrategy)
            });

            deployment.factoryImpl = address(factoryImpl);
        } else {
            factoryProxy = ZoraCreator1155FactoryImpl(deployment.factoryProxy);
        }

        console.log("!!!factory proxy!!!");
        // console.log(factoryProxy);

        ZoraCreator1155PremintExecutor preminter = new ZoraCreator1155PremintExecutor(factoryProxy);

        vm.stopBroadcast();

        deployment.preminter = address(preminter);

        return getDeploymentJSON(deployment);
    }
}
