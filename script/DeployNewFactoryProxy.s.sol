// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "forge-std/Script.sol";
import "forge-std/console2.sol";

import {ZoraDeployerBase} from "./ZoraDeployerBase.sol";
import {ChainConfig, Deployment} from "../src/deployment/DeploymentConfig.sol";
import {ZoraDeployerUtils} from "../src/deployment/ZoraDeployerUtils.sol";
import {NewFactoryProxyDeployer} from "../src/deployment/NewFactoryProxyDeployer.sol";
import {DeterminsticDeployerScript, DeterminsticParams} from "../src/deployment/DeterminsticDeployerScript.sol";

contract DeployNewFactoryProxy is ZoraDeployerBase, DeterminsticDeployerScript {
    using stdJson for string;

    error MismatchedAddress(address expected, address actual);

    function run() public returns (string memory) {
        uint256 deployerPrivateKey = vm.envUint("DEPLOYER_PRIVATE_KEY");
        // address deployer = vm.envAddress("DEPLOYER");

        uint256 chain = chainId();

        ChainConfig memory chainConfig = getChainConfig();
        Deployment memory deployment = getDeployment();

        // get signing instructions

        (DeterminsticParams memory params, bytes memory signature) = readDeterminsticParams("factoryProxy", chain);

        vm.startBroadcast(deployerPrivateKey);

        NewFactoryProxyDeployer factoryDeployer = NewFactoryProxyDeployer(
            ZoraDeployerUtils.IMMUTABLE_CREATE2_FACTORY.safeCreate2(params.proxyDeployerSalt, params.proxyDeployerCreationCode)
        );

        console2.log(address(factoryDeployer));
        console2.log(params.proxyDeployerAddress);

        if (address(factoryDeployer) != params.proxyDeployerAddress) revert MismatchedAddress(params.proxyDeployerAddress, address(factoryDeployer));

        address factoryProxyAddress = factoryDeployer.createFactoryProxyDeterminstic(
            params.proxyShimSalt,
            params.proxySalt,
            params.proxyCreationCode,
            params.determinsticProxyAddress,
            deployment.factoryImpl,
            chainConfig.factoryOwner,
            signature
        );

        vm.stopBroadcast();

        deployment.factoryProxy = factoryProxyAddress;

        return getDeploymentJSON(deployment);
    }
}
