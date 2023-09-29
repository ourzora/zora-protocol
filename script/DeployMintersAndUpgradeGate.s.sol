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
import {DeterministicDeployerScript} from "../src/deployment/DeterministicDeployerScript.sol";

contract DeployerMintersAndUpgradeGate is ZoraDeployerBase, DeterministicDeployerScript {
    function run() public returns (string memory) {
        Deployment memory deployment = getDeployment();
        ChainConfig memory chainConfig = getChainConfig();

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

        address upgradeGateAddress = deployUpgradeGate({chain: chainId(), upgradeGateOwner: chainConfig.factoryOwner});

        deployment.fixedPriceSaleStrategy = address(fixedPriceMinter);
        deployment.merkleMintSaleStrategy = address(merkleMinter);
        deployment.redeemMinterFactory = address(redeemMinterFactory);
        deployment.upgradeGate = upgradeGateAddress;

        return getDeploymentJSON(deployment);
    }
}
