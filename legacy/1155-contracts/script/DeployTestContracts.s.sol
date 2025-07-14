// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "forge-std/Script.sol";
import "forge-std/console2.sol";

import {ZoraDeployerBase} from "../src/deployment/ZoraDeployerBase.sol";
import {Deployment} from "../src/deployment/DeploymentConfig.sol";
import {ZoraDeployerUtils} from "../src/deployment/ZoraDeployerUtils.sol";
import {MintArguments} from "@zoralabs/shared-contracts/entities/Premint.sol";
import {ZoraCreator1155Impl} from "../src/nft/ZoraCreator1155Impl.sol";
import {IZoraCreator1155PremintExecutor} from "../src/interfaces/IZoraCreator1155PremintExecutor.sol";

contract DeployTestContracts is ZoraDeployerBase {
    function run() public returns (string memory) {
        Deployment memory deployment = getDeployment();

        vm.startBroadcast();

        address deployedAddress = ZoraDeployerUtils.deployTestContractForVerification(deployment.factoryProxy, makeAddr("admin"));

        address implAddress = ZoraCreator1155Impl(payable(deployedAddress)).implementation();

        // forge verify-contract {deployedAddress} Zora1155 $(chains {chainName} --verify) --constructor-args $(cast abi-encode "constructor(address)" {implAddress})
        bytes memory constructorArgs = abi.encode(implAddress);
        console2.log("to verify:");
        console2.log(
            string.concat(
                "forge verify-contract ",
                vm.toString(deployedAddress),
                " Zora1155 ",
                " --constructor-args ",
                vm.toString(constructorArgs),
                " $(chains {chainName} --verify)"
            )
        );

        vm.stopBroadcast();

        // now test signing and executing premint

        return getDeploymentJSON(deployment);
    }
}
