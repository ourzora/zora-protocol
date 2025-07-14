// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {ProxyDeployerScript, DeterministicDeployerAndCaller, DeterministicContractConfig} from "@zoralabs/shared-contracts/deployment/ProxyDeployerScript.sol";
import {CointagsDeployerBase} from "./CointagsDeployerBase.sol";
import {ICointag} from "../src/interfaces/ICointag.sol";
import {console} from "forge-std/console.sol";

contract DeployScript is CointagsDeployerBase {
    function run() public {
        CointagsDeployment memory deployment = readDeployment();

        vm.startBroadcast();

        ICointag cointag = createTestCointag(deployment);

        bytes memory constructorArgs = abi.encode(deployment.cointagImpl, bytes(""));

        // console.log the verification command
        console.log("Verification command:");
        // forge verify-contract $(address(cointag)) Cointag $(chains chain_id --verify)
        console.log(
            string.concat(
                "forge verify-contract ",
                vm.toString(address(cointag)),
                " Cointag --constructor-args ",
                vm.toString(constructorArgs),
                " $(chains {chainName} --verify)"
            )
        );
        vm.stopBroadcast();
    }
}
