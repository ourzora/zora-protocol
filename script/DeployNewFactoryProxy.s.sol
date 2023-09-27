// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "forge-std/Script.sol";
import "forge-std/console2.sol";

import {ZoraDeployerBase} from "./ZoraDeployerBase.sol";
import {ChainConfig, Deployment} from "../src/deployment/DeploymentConfig.sol";
import {ZoraDeployer} from "../src/deployment/ZoraDeployer.sol";
import {NewFactoryProxyDeployer} from "../src/deployment/NewFactoryProxyDeployer.sol";

contract DeployNewFactoryProxy is ZoraDeployerBase {
    using stdJson for string;

    error MismatchedAddress(address expected, address actual);

    function run() public returns (string memory) {
        uint256 deployerPrivateKey = vm.envUint("DEPLOYER_PRIVATE_KEY");
        // address deployer = vm.envAddress("DEPLOYER");

        uint256 chain = chainId();

        ChainConfig memory chainConfig = getChainConfig();
        Deployment memory deployment = getDeployment();

        // get signing instructions

        string memory root = vm.projectRoot();
        string memory deployConfig = vm.readFile(string.concat(root, "/determinsticConfig/deployConfig.json"));
        string memory signatures = vm.readFile(string.concat(root, "/determinsticConfig/factoryDeploySignatures.json"));

        address expectedFactoryDeployerAddress = deployConfig.readAddress(".determinsticDeployerAddress");
        bytes32 proxyShimSalt = deployConfig.readBytes32(".proxyShimSalt");
        bytes32 factoryProxySalt = deployConfig.readBytes32(".factoryProxySalt");
        address expectedFactoryProxyAddress = deployConfig.readAddress(".factoryProxyAddress");
        address factoryImplAddress = deployment.factoryImpl;
        address owner = chainConfig.factoryOwner;

        bytes memory signature = signatures.readBytes(string.concat(".", string.concat(vm.toString(chain), ".signature")));

        console2.log(vm.toString(signature));
        // console2.log(vm.toString(proxyShimSalt));

        vm.startBroadcast(deployerPrivateKey);

        NewFactoryProxyDeployer factoryDeployer = ZoraDeployer.createDeterminsticFactoryProxyDeployer();

        console2.log(address(factoryDeployer));
        console2.log(expectedFactoryDeployerAddress);

        if (address(factoryDeployer) != expectedFactoryDeployerAddress) revert MismatchedAddress(expectedFactoryDeployerAddress, address(factoryDeployer));

        address factoryProxyAddress = factoryDeployer.createFactoryProxyDeterminstic(
            proxyShimSalt,
            factoryProxySalt,
            expectedFactoryProxyAddress,
            factoryImplAddress,
            owner,
            signature
        );

        vm.stopBroadcast();

        deployment.factoryProxy = factoryProxyAddress;

        return getDeploymentJSON(deployment);
    }
}
