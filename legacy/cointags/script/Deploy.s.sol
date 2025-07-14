// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {ProxyDeployerScript, DeterministicDeployerAndCaller, DeterministicContractConfig} from "@zoralabs/shared-contracts/deployment/ProxyDeployerScript.sol";
import {CointagsDeployerBase} from "./CointagsDeployerBase.sol";

contract DeployScript is CointagsDeployerBase {
    function run() public {
        CointagsDeployment memory deployment = readDeployment();

        vm.startBroadcast();

        // get deployer contract
        DeterministicDeployerAndCaller deployer = createOrGetDeployerAndCaller();

        deployUpgradeGate(deployment);
        deployCointagsDeterministic(deployment, deployer);

        vm.stopBroadcast();

        // save the deployment json
        saveDeployment(deployment);
    }
}
