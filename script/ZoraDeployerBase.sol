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
import {DeterministicDeployerScript} from "../src/deployment/DeterministicDeployerScript.sol";
import {ZoraCreator1155FactoryImpl} from "../src/factory/ZoraCreator1155FactoryImpl.sol";

/// @notice Deployment drops for base where
abstract contract ZoraDeployerBase is ScriptDeploymentConfig, DeterministicDeployerScript {
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

    function deployMinters(Deployment memory deployment) internal {
        (address fixedPriceMinter, address merkleMinter, address redeemMinterFactory) = ZoraDeployerUtils.deployMinters();
        deployment.fixedPriceSaleStrategy = address(fixedPriceMinter);
        deployment.merkleMintSaleStrategy = address(merkleMinter);
        deployment.redeemMinterFactory = address(redeemMinterFactory);
    }

    function deployNew1155AndFactoryImpl(Deployment memory deployment) internal {
        ChainConfig memory chainConfig = getChainConfig();

        ensureCanOwn(chainConfig.factoryOwner);

        (address factoryImplDeployment, address contract1155ImplDeployment, string memory contract1155ImplVersion) = ZoraDeployerUtils
            .deployNew1155AndFactoryImpl({
                upgradeGateAddress: determinsticUpgradeGateAddress(),
                mintFeeRecipient: chainConfig.mintFeeRecipient,
                protocolRewards: chainConfig.protocolRewards,
                merkleMinter: IMinter1155(deployment.merkleMintSaleStrategy),
                redeemMinterFactory: IMinter1155(deployment.redeemMinterFactory),
                fixedPriceMinter: IMinter1155(deployment.fixedPriceSaleStrategy)
            });

        deployment.factoryImpl = factoryImplDeployment;
        deployment.contract1155Impl = contract1155ImplDeployment;
        deployment.contract1155ImplVersion = contract1155ImplVersion;
    }

    function deployNewPreminterImplementationDeterminstic(Deployment memory deployment) internal {
        address factoryProxyAddress = determinticFactoryProxyAddress();
        deployment.preminterImpl = ZoraDeployerUtils.deployNewPreminterImplementationDeterminstic(factoryProxyAddress);
    }

    function determinticFactoryProxyAddress() internal view returns (address) {
        return readFactoryProxyDeterminsticParams().deterministicProxyAddress;
    }

    function determinsticPreminterProxyAddress() internal view returns (address) {
        return readPreminterProxyDeterminsticParams().deterministicProxyAddress;
    }

    function deployFactoryProxyDeterminstic(Deployment memory deployment) internal {
        ChainConfig memory chainConfig = getChainConfig();

        ensureCanOwn(chainConfig.factoryOwner);

        address factoryProxyAddress = deployDeterministicProxy({
            proxyName: "factoryProxy",
            implementation: deployment.factoryImpl,
            owner: chainConfig.factoryOwner,
            chain: chainId()
        });

        require(factoryProxyAddress == determinticFactoryProxyAddress(), "address not expected deterministic address");

        require(
            keccak256(abi.encodePacked(ZoraCreator1155FactoryImpl(factoryProxyAddress).contractName())) ==
                keccak256(abi.encodePacked("ZORA 1155 Contract Factory"))
        );

        deployment.factoryProxy = factoryProxyAddress;
    }

    function deployPreminterProxyDeterminstic(Deployment memory deployment) internal {
        ChainConfig memory chainConfig = getChainConfig();

        ensureCanOwn(chainConfig.factoryOwner);

        address preminterProxyAddress = deployDeterministicProxy({
            proxyName: "premintExecutorProxy",
            implementation: deployment.preminterImpl,
            owner: chainConfig.factoryOwner,
            chain: chainId()
        });

        require(preminterProxyAddress == determinsticPreminterProxyAddress(), "address not expected deterministic address");

        deployment.preminterProxy = preminterProxyAddress;
    }

    function deployUpgradeGateDeterminstic(Deployment memory deployment) internal {
        ChainConfig memory chainConfig = getChainConfig();

        ensureCanOwn(chainConfig.factoryOwner);

        address upgradeGateAddress = deployUpgradeGate({chain: chainId(), upgradeGateOwner: chainConfig.factoryOwner});

        require(upgradeGateAddress == determinsticUpgradeGateAddress(), "address not expected deterministic address");

        deployment.upgradeGate = upgradeGateAddress;
    }

    function ensureCanOwn(address account) internal view {
        // Sanity check to make sure that the factory owner is a smart contract.
        // This may catch cross-chain data copy mistakes where there is no safe at the desired admin address.
        if (account.code.length == 0) {
            revert("FactoryOwner should be a contract. See DeployNewProxies:31.");
        }
    }

    function determinsticUpgradeGateAddress() internal view returns (address) {
        return vm.parseJsonAddress(vm.readFile("./deterministicConfig/upgradeGate/params.json"), ".upgradeGateAddress");
    }
}
