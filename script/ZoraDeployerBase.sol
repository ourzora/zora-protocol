// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import "forge-std/Script.sol";
import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";

import {IZoraCreator1155Factory} from "../src/interfaces/IZoraCreator1155Factory.sol";
import {ZoraCreator1155Impl} from "../src/nft/ZoraCreator1155Impl.sol";
import {Zora1155Factory} from "../src/proxies/Zora1155Factory.sol";
import {ICreatorRoyaltiesControl} from "../src/interfaces/ICreatorRoyaltiesControl.sol";
import {ScriptDeploymentConfig, Deployment, ChainConfig} from "../src/deployment/DeploymentConfig.sol";
import {ProxyShim} from "../src/utils/ProxyShim.sol";
import {ZoraCreator1155FactoryImpl} from "../src/factory/ZoraCreator1155FactoryImpl.sol";
import {Zora1155PremintExecutorProxy} from "../src/proxies/Zora1155PremintExecutorProxy.sol";
import {ZoraCreator1155PremintExecutor} from "../src/premint/ZoraCreator1155PremintExecutor.sol";
import {IMinter1155} from "../src/interfaces/IMinter1155.sol";

/// @notice Deployment drops for base where
abstract contract ZoraDeployerBase is ScriptDeploymentConfig, Script {
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
        vm.serializeAddress(deploymentJsonKey, PREMINTER, deployment.preminter);
        deploymentJson = vm.serializeAddress(deploymentJsonKey, FACTORY_PROXY, deployment.factoryProxy);
        console2.log(deploymentJson);
    }

    function deployNew1155AndFactoryImpl(Deployment memory deployment, Zora1155Factory factoryProxy) internal {
        ChainConfig memory chainConfig = getChainConfig();

        ZoraCreator1155Impl creatorImpl = new ZoraCreator1155Impl(
            chainConfig.mintFeeAmount,
            chainConfig.mintFeeRecipient,
            address(factoryProxy),
            chainConfig.protocolRewards
        );

        console2.log("Implementation Address", address(creatorImpl));

        deployment.contract1155Impl = address(creatorImpl);

        ZoraCreator1155FactoryImpl factoryImpl = new ZoraCreator1155FactoryImpl({
            _implementation: creatorImpl,
            _merkleMinter: IMinter1155(deployment.merkleMintSaleStrategy),
            _redeemMinterFactory: IMinter1155(deployment.redeemMinterFactory),
            _fixedPriceMinter: IMinter1155(deployment.fixedPriceSaleStrategy)
        });

        deployment.factoryImpl = address(factoryImpl);
    }

    function deployNew1155AndFactoryProxy(Deployment memory deployment, address deployer) internal {
        address factoryShimAddress = address(new ProxyShim(deployer));
        Zora1155Factory factoryProxy = new Zora1155Factory(factoryShimAddress, "");

        deployment.factoryProxy = address(factoryProxy);

        // deploy new 1155 and factory impl, and udpdate deployment config with it
        deployNew1155AndFactoryImpl(deployment, factoryProxy);

        ZoraCreator1155FactoryImpl(address(factoryProxy)).upgradeTo(deployment.factoryImpl);
        ZoraCreator1155FactoryImpl(address(factoryProxy)).initialize(getChainConfig().factoryOwner);

        console2.log("Factory Proxy", address(factoryProxy));
    }

    function deployNewPreminterImplementation(Deployment memory deployment) internal returns (address) {
        // create preminter implementation
        ZoraCreator1155PremintExecutor preminterImplementation = new ZoraCreator1155PremintExecutor(ZoraCreator1155FactoryImpl(deployment.factoryProxy));

        return address(preminterImplementation);
    }

    function deployNewPreminterProxy(Deployment memory deployment) internal {
        address preminterImplementation = deployNewPreminterImplementation(deployment);

        // build the proxy
        Zora1155PremintExecutorProxy proxy = new Zora1155PremintExecutorProxy(preminterImplementation, "");

        deployment.preminter = address(proxy);

        // access the executor implementation via the proxy, and initialize the admin
        ZoraCreator1155PremintExecutor preminterAtProxy = ZoraCreator1155PremintExecutor(address(proxy));
        preminterAtProxy.initialize(getChainConfig().factoryOwner);
    }

    /// @notice Deploy a test contract for etherscan auto-verification
    /// @param factoryProxy Factory address to use
    /// @param admin Admin owner address to use
    function deployTestContractForVerification(address factoryProxy, address admin) internal {
        bytes[] memory initUpdate = new bytes[](1);
        initUpdate[0] = abi.encodeWithSelector(
            ZoraCreator1155Impl.setupNewToken.selector,
            "ipfs://bafkreigu544g6wjvqcysurpzy5pcskbt45a5f33m6wgythpgb3rfqi3lzi",
            100
        );
        address newContract = address(
            IZoraCreator1155Factory(factoryProxy).createContract(
                "ipfs://bafybeicgolwqpozsc7iwgytavete56a2nnytzix2nb2rxefdvbtwwtnnoe/metadata",
                unicode"🪄",
                ICreatorRoyaltiesControl.RoyaltyConfiguration({royaltyBPS: 0, royaltyRecipient: address(0), royaltyMintSchedule: 0}),
                payable(admin),
                initUpdate
            )
        );
        console2.log("Deployed new contract for verification purposes", newContract);
    }
}
