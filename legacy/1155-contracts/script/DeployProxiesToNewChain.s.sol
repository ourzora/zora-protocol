// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "forge-std/Script.sol";
import "forge-std/console2.sol";

import {ZoraDeployerBase} from "../src/deployment/ZoraDeployerBase.sol";
import {Deployment} from "../src/deployment/DeploymentConfig.sol";
import {ZoraDeployerUtils} from "../src/deployment/ZoraDeployerUtils.sol";
import {DeploymentTestingUtils} from "../src/deployment/DeploymentTestingUtils.sol";
import {MintArguments} from "@zoralabs/shared-contracts/entities/Premint.sol";
import {IZoraCreator1155PremintExecutor} from "../src/interfaces/IZoraCreator1155PremintExecutor.sol";

contract DeployProxiesToNewChain is ZoraDeployerBase {
    function run() public returns (string memory) {
        Deployment memory deployment = getDeployment();

        vm.startBroadcast();

        console.log("deploy factory proxy");

        deployFactoryProxyDeterminstic(deployment);

        console2.log("factory proxy address:", deployment.factoryProxy);

        console2.log("create test contract for verification");

        ZoraDeployerUtils.deployTestContractForVerification(deployment.factoryProxy, makeAddr("admin"));

        deployPreminterProxyDeterminstic(deployment);

        console2.log("preminter proxy", deployment.preminterProxy);

        console2.log("testing premint");

        address fundsRecipient = vm.envAddress("TEST_PREMINT_FUNDS_RECIPIENT");
        MintArguments memory mintArguments = MintArguments({mintRecipient: fundsRecipient, mintComment: "", mintRewardsRecipients: new address[](0)});

        signAndExecutePremintV2(deployment.preminterProxy, vm.envAddress("TEST_PREMINT_FUNDS_RECIPIENT"), mintArguments);

        vm.stopBroadcast();

        // now test signing and executing premint

        return getDeploymentJSON(deployment);
    }
}
