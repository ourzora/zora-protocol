// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "forge-std/Script.sol";
import "forge-std/console2.sol";

import {ZoraDeployerBase, ChainConfig, Deployment} from "./ZoraDeployerBase.sol";

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
    function run() public returns (string memory) {
        Deployment memory deployment;
        ChainConfig memory chainConfig = getChainConfig();

        console2.log("zoraFeeAmount", chainConfig.mintFeeAmount);
        console2.log("zoraFeeRecipient", chainConfig.mintFeeRecipient);

        address deployer = vm.envAddress("DEPLOYER");

        vm.startBroadcast(deployer);

        ZoraCreatorFixedPriceSaleStrategy fixedPricedMinter = new ZoraCreatorFixedPriceSaleStrategy();
        ZoraCreatorMerkleMinterStrategy merkleMinter = new ZoraCreatorMerkleMinterStrategy();
        ZoraCreatorRedeemMinterFactory redeemMinterFactory = new ZoraCreatorRedeemMinterFactory();

        deployment.fixedPriceSaleStrategy = address(fixedPricedMinter);
        deployment.merkleMintSaleStrategy = address(merkleMinter);
        deployment.redeemMinterFactory = address(redeemMinterFactory);

        address factoryShimAddress = address(new ProxyShim(deployer));
        Zora1155Factory factoryProxy = new Zora1155Factory(factoryShimAddress, "");

        deployment.factoryProxy = address(factoryProxy);

        ZoraCreator1155Impl creatorImpl = new ZoraCreator1155Impl(chainConfig.mintFeeAmount, chainConfig.mintFeeRecipient, address(factoryProxy));

        deployment.contract1155Impl = address(creatorImpl);

        ZoraCreator1155FactoryImpl factoryImpl = new ZoraCreator1155FactoryImpl({
            _implementation: creatorImpl,
            _merkleMinter: merkleMinter,
            _redeemMinterFactory: redeemMinterFactory,
            _fixedPriceMinter: fixedPricedMinter
        });

        deployment.factoryImpl = address(factoryImpl);

        // Upgrade to "real" factory address
        ZoraCreator1155FactoryImpl(address(factoryProxy)).upgradeTo(address(factoryImpl));
        ZoraCreator1155FactoryImpl(address(factoryProxy)).initialize(chainConfig.factoryOwner);

        console2.log("Factory Proxy", address(factoryProxy));
        console2.log("Implementation Address", address(creatorImpl));

        deployTestContractForVerification(address(factoryProxy), chainConfig.factoryOwner);

        return getDeploymentJSON(deployment);
    }
}
