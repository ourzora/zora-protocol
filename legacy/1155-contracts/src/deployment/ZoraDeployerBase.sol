// SPDX-License-Identifier: MIT
pragma solidity >=0.8.13;

import "forge-std/Script.sol";
import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";

import {IZoraCreator1155Factory} from "../interfaces/IZoraCreator1155Factory.sol";
import {ZoraCreator1155Impl} from "../nft/ZoraCreator1155Impl.sol";
import {Zora1155Factory} from "../proxies/Zora1155Factory.sol";
import {ICreatorRoyaltiesControl} from "../interfaces/ICreatorRoyaltiesControl.sol";
import {DeploymentConfig, Deployment, ChainConfig} from "./DeploymentConfig.sol";
import {ZoraDeployerUtils} from "./ZoraDeployerUtils.sol";
import {IMinter1155} from "../interfaces/IMinter1155.sol";
import {DeterministicDeployerScript} from "./DeterministicDeployerScript.sol";
import {ZoraCreator1155FactoryImpl} from "../factory/ZoraCreator1155FactoryImpl.sol";
import {DeploymentTestingUtils} from "./DeploymentTestingUtils.sol";

/// @notice Deployment drops for base where
abstract contract ZoraDeployerBase is DeploymentTestingUtils, DeploymentConfig, DeterministicDeployerScript {
    using stdJson for string;

    /// @notice File used for demo metadata on verification test mint
    string constant DEMO_IPFS_METADATA_FILE = "ipfs://bafkreigu544g6wjvqcysurpzy5pcskbt45a5f33m6wgythpgb3rfqi3lzi";

    /// @notice Get deployment configuration struct as JSON
    /// @param deployment deployment struct
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
        vm.serializeAddress(deploymentJsonKey, UPGRADE_GATE, deployment.upgradeGate);
        vm.serializeAddress(deploymentJsonKey, ERC20_MINTER, deployment.erc20Minter);
        vm.serializeUint(deploymentJsonKey, "timestamp", block.timestamp);
        deploymentJson = vm.serializeAddress(deploymentJsonKey, FACTORY_PROXY, deployment.factoryProxy);

        string memory configPath = string.concat("./addresses/", vm.toString(block.chainid), ".json");
        console2.log("Writing updated deployment file to ", configPath);
        vm.writeJson(deploymentJson, configPath);
    }

    function deployMinters(Deployment memory deployment, ChainConfig memory chainConfig) internal {
        (address fixedPriceMinter, address merkleMinter, address redeemMinterFactory, address erc20Minter) = ZoraDeployerUtils.deployMinters(chainConfig);
        deployment.fixedPriceSaleStrategy = fixedPriceMinter;
        deployment.merkleMintSaleStrategy = merkleMinter;
        deployment.redeemMinterFactory = redeemMinterFactory;
        deployment.erc20Minter = erc20Minter;
    }

    function deployNew1155AndFactoryImpl(Deployment memory deployment) internal {
        ChainConfig memory chainConfig = getChainConfig();

        (address factoryImplDeployment, address contract1155ImplDeployment, string memory contract1155ImplVersion) = ZoraDeployerUtils
            .deployNew1155AndFactoryImpl({
                upgradeGateAddress: determinsticUpgradeGateAddress(),
                mintFeeRecipient: chainConfig.mintFeeRecipient,
                protocolRewards: chainConfig.protocolRewards,
                merkleMinter: IMinter1155(deployment.merkleMintSaleStrategy),
                redeemMinterFactory: IMinter1155(deployment.redeemMinterFactory),
                fixedPriceMinter: IMinter1155(deployment.fixedPriceSaleStrategy),
                timedSaleStrategy: getTimedSaleStrategyDeployment()
            });

        deployment.factoryImpl = factoryImplDeployment;
        deployment.contract1155Impl = contract1155ImplDeployment;
        deployment.contract1155ImplVersion = contract1155ImplVersion;
    }

    function deployNewFactoryImpl(Deployment memory deployment) internal {
        ChainConfig memory chainConfig = getChainConfig();

        ensureCanOwn(chainConfig.factoryOwner);

        deployment.factoryImpl = address(
            new ZoraCreator1155FactoryImpl({
                _zora1155Impl: ZoraCreator1155Impl(payable(deployment.contract1155Impl)),
                _merkleMinter: IMinter1155(deployment.merkleMintSaleStrategy),
                _redeemMinterFactory: IMinter1155(deployment.redeemMinterFactory),
                _fixedPriceMinter: IMinter1155(deployment.fixedPriceSaleStrategy)
            })
        );
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
            chain: block.chainid
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
            chain: block.chainid
        });

        require(preminterProxyAddress == determinsticPreminterProxyAddress(), "address not expected deterministic address");

        deployment.preminterProxy = preminterProxyAddress;
    }

    function deployUpgradeGateDeterminstic(Deployment memory deployment) internal {
        ChainConfig memory chainConfig = getChainConfig();

        ensureCanOwn(chainConfig.factoryOwner);

        address upgradeGateAddress = deployUpgradeGate({chain: block.chainid, upgradeGateOwner: chainConfig.factoryOwner});

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
        return vm.parseJsonAddress(vm.readFile("./deterministicConfig/upgradeGate.json"), ".upgradeGateAddress");
    }
}
