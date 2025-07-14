// spdx-license-identifier: mit
pragma solidity ^0.8.20;

import "forge-std/Script.sol";

import {LibString} from "solady/utils/LibString.sol";
import {ImmutableCreate2FactoryUtils} from "@zoralabs/shared-contracts/utils/ImmutableCreate2FactoryUtils.sol";
import {ProxyDeployerScript, DeterministicDeployerAndCaller, DeterministicContractConfig} from "@zoralabs/shared-contracts/deployment/ProxyDeployerScript.sol";
import {SecondarySwap} from "../src/helper/SecondarySwap.sol";
import {Create2} from "@openzeppelin/contracts/utils/Create2.sol";

/// @dev This script saves the current bytecode and deterministic config for the SwapRouter
contract GenerateSecondarySwapParams is ProxyDeployerScript {
    function mineForSwapRouterAddress(DeterministicDeployerAndCaller deployer, address caller) private returns (DeterministicContractConfig memory config) {
        // sparks 1155 is created from the zora sparks manager impl, without any arguments
        bytes memory creationCode = type(SecondarySwap).creationCode;
        bytes32 initCodeHash = keccak256(creationCode);
        // sparks manager is deployer
        (bytes32 salt, address expectedAddress) = mineSalt(address(deployer), initCodeHash, "7777777", caller);

        config.salt = salt;
        config.deployedAddress = expectedAddress;
        config.creationCode = creationCode;
        // no constructor args for royalties - it is initialized
        config.contractName = "SecondarySwap";
    }

    function run() public {
        address caller = vm.envAddress("DEPLOYER");

        generateAndSaveDeployerAndCallerConfig();

        vm.startBroadcast();

        // create a proxy deployer, which we can use to generated deterministic addresses and corresponding params.
        // proxy deployer code is based on code saved to file from running the script SaveProxyDeployerConfig.s.sol
        DeterministicDeployerAndCaller deployer = createOrGetDeployerAndCaller();

        vm.stopBroadcast();

        DeterministicContractConfig memory secondarySwap = mineForSwapRouterAddress(deployer, caller);

        saveDeterministicContractConfig(secondarySwap, "secondarySwap");
    }
}
