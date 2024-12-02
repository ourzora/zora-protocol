// spdx-license-identifier: mit
pragma solidity ^0.8.20;

import "forge-std/Script.sol";

import {ImmutableCreate2FactoryUtils} from "@zoralabs/shared-contracts/utils/ImmutableCreate2FactoryUtils.sol";
import {ProxyDeployerScript, DeterministicDeployerAndCaller, DeterministicContractConfig} from "@zoralabs/shared-contracts/deployment/ProxyDeployerScript.sol";
import {Comments} from "../src/proxy/Comments.sol";
import {CallerAndCommenter} from "../src/proxy/CallerAndCommenter.sol";

/// @dev This script saves the current bytecode, and initialization parameters for the Sparks proxy,
/// which then need to be populated with a salt and expected address, which can be achieved by
/// running the printed create2crunch command.  The resulting config only needs to be generated once
/// and is reusable for all chains.
contract GenerateDeterministicParams is ProxyDeployerScript {
    function mineForCommentsAddress(DeterministicDeployerAndCaller deployer, address caller) private returns (DeterministicContractConfig memory config) {
        // get proxy creation code
        // get the expected init code for the proxy from the uupsProxyDeployer
        bytes memory initCode = deployer.proxyCreationCode(type(Comments).creationCode);
        bytes32 initCodeHash = keccak256(initCode);

        // uupsProxyDeployer is deployer
        (bytes32 salt, address expectedAddress) = mineSalt(address(deployer), initCodeHash, "7777777", caller);

        // test deployment
        // Create2.deploy(0, salt, initCode);

        console2.log("salt");
        console2.log(vm.toString(salt));

        config.salt = salt;
        config.deployedAddress = expectedAddress;
        config.creationCode = initCode;
        config.constructorArgs = deployer.proxyConstructorArgs();
        config.contractName = "Comments";
        config.deploymentCaller = caller;
    }

    function mineForCallerAndCommenterAddress(
        DeterministicDeployerAndCaller deployer,
        address caller
    ) private returns (DeterministicContractConfig memory config) {
        // get proxy creation code
        // get the expected init code for the proxy from the uupsProxyDeployer
        bytes memory initCode = deployer.proxyCreationCode(type(CallerAndCommenter).creationCode);
        bytes32 initCodeHash = keccak256(initCode);

        // uupsProxyDeployer is deployer
        (bytes32 salt, address expectedAddress) = mineSalt(address(deployer), initCodeHash, "7777777", caller);

        // test deployment
        // Create2.deploy(0, salt, initCode);

        console2.log("salt");
        console2.log(vm.toString(salt));

        config.salt = salt;
        config.deployedAddress = expectedAddress;
        config.creationCode = initCode;
        config.constructorArgs = deployer.proxyConstructorArgs();
        config.contractName = "CallerAndCommenter";
        config.deploymentCaller = caller;
    }

    function run() public {
        address caller = vm.envAddress("DEPLOYER");

        vm.startBroadcast();

        // create a proxy deployer, which we can use to generated determistic addresses and corresponding params.
        // proxy deployer code is based on code saved to file from running the script SaveProxyDeployerConfig.s.sol
        DeterministicDeployerAndCaller deployer = createOrGetDeployerAndCaller();

        vm.stopBroadcast();

        // DeterministicContractConfig memory commentsConfig = mineForCommentsAddress(deployer, caller);

        DeterministicContractConfig memory callerAndCommenterConfig = mineForCallerAndCommenterAddress(deployer, caller);

        // saveDeterministicContractConfig(commentsConfig, "comments");
        saveDeterministicContractConfig(callerAndCommenterConfig, "callerAndCommenter");
    }
}
