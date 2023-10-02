// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import "forge-std/Script.sol";
import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";

import {IZoraCreator1155Factory} from "../src/interfaces/IZoraCreator1155Factory.sol";
import {ZoraCreator1155Impl} from "../src/nft/ZoraCreator1155Impl.sol";
import {Zora1155Factory} from "../src/proxies/Zora1155Factory.sol";
import {ICreatorRoyaltiesControl} from "../src/interfaces/ICreatorRoyaltiesControl.sol";
import {ScriptDeploymentConfig, Deployment, ChainConfig} from "../src/deployment/DeploymentConfig.sol";
import {ZoraDeployerUtils} from "../src/deployment/ZoraDeployerUtils.sol";
import {IMinter1155} from "../src/interfaces/IMinter1155.sol";

/// @notice Deployment drops for base where
abstract contract ZoraDeployerBase is ScriptDeploymentConfig {
    using stdJson for string;

    /// @notice File used for demo metadata on verification test mint
    string constant DEMO_IPFS_METADATA_FILE = "ipfs://bafkreigu544g6wjvqcysurpzy5pcskbt45a5f33m6wgythpgb3rfqi3lzi";

    /// @notice Get deployment configuration struct as JSON
    /// @param deployment deploymet struct
    /// @return deploymentJson string JSON of the deployment info
    function getDeploymentJSON(Deployment memory deployment) internal returns (string memory deploymentJson) {
        string memory deploymentJsonKey = "deployment_json_file_key";
        vm.serializeAddress(deploymentJsonKey, FIXED_PRICE_SALE_STRATEGY, deployment.fixedPriceSaleStrategy);
        vm.serializeAddress(deploymentJsonKey, MERKLE_MINT_SALE_STRATEGY, deployment.merkleMintSaleStrategy);
        vm.serializeAddress(deploymentJsonKey, REDEEM_MINTER_FACTORY, deployment.redeemMinterFactory);
        vm.serializeString(deploymentJsonKey, CONTRACT_1155_IMPL_VERSION, deployment.contract1155ImplVersion);
        vm.serializeAddress(deploymentJsonKey, CONTRACT_1155_IMPL, deployment.contract1155Impl);
        vm.serializeAddress(deploymentJsonKey, FACTORY_IMPL, deployment.factoryImpl);
        vm.serializeAddress(deploymentJsonKey, PREMINTER_PROXY, deployment.preminterProxy);
        vm.serializeAddress(deploymentJsonKey, PREMINTER_IMPL, deployment.preminterImpl);
        deploymentJson = vm.serializeAddress(deploymentJsonKey, FACTORY_PROXY, deployment.factoryProxy);
        console2.log(deploymentJson);
    }

    function deployNew1155AndFactoryImpl(Deployment memory deployment, Zora1155Factory factoryProxy) internal {
        ChainConfig memory chainConfig = getChainConfig();

        (address factoryImplAddress, address contract1155ImplAddress) = ZoraDeployerUtils.deployNew1155AndFactoryImplDeterminstic({
            factoryProxyAddress: address(factoryProxy),
            mintFeeRecipient: chainConfig.mintFeeRecipient,
            protocolRewards: chainConfig.protocolRewards,
            merkleMinter: IMinter1155(deployment.merkleMintSaleStrategy),
            redeemMinterFactory: IMinter1155(deployment.redeemMinterFactory),
            fixedPriceMinter: IMinter1155(deployment.fixedPriceSaleStrategy)
        });

        deployment.contract1155Impl = contract1155ImplAddress;
        deployment.factoryImpl = factoryImplAddress;
    }

    function determinsticUpgradeGateAddress() internal view returns (address) {
        return vm.parseJsonAddress(vm.readFile("./deterministicConfig/upgradeGate/params.json"), ".upgradeGateAddress");
    }

    // function deployNewPreminterProxy(Deployment memory deployment) internal {
    //     address proxyOwner = getChainConfig().factoryOwner;

    //     deployment.preminter = ZoraDeployerUtils.deployNewPreminterProxy(deployment.factoryProxy, proxyOwner);
    // }
}
