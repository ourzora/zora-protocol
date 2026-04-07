// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "forge-std/Script.sol";

import {ImmutableCreate2FactoryUtils} from "@zoralabs/shared-contracts/utils/ImmutableCreate2FactoryUtils.sol";
import {ProxyDeployerScript, DeterministicDeployerAndCaller, DeterministicContractConfig} from "@zoralabs/shared-contracts/deployment/ProxyDeployerScript.sol";
import {CointagFactory} from "../src/proxy/CointagFactory.sol";
import {UpgradeGate} from "../src/upgrades/UpgradeGate.sol";

/// @dev This script saves the current bytecode and initialization parameters for the Cointags proxy,
/// which then need to be populated with a salt and expected address, which can be achieved by
/// running the printed create2crunch command. The resulting config only needs to be generated once
/// and is reusable for all chains.
contract GenerateDeterministicParams is ProxyDeployerScript {
    function mineForCointagAddress(DeterministicDeployerAndCaller deployer, address caller) private returns (DeterministicContractConfig memory config) {
        // get proxy creation code
        bytes memory initCode = deployer.proxyCreationCode(type(CointagFactory).creationCode);
        bytes32 initCodeHash = keccak256(initCode);

        // uupsProxyDeployer is deployer
        (bytes32 salt, address expectedAddress) = mineSalt(address(deployer), initCodeHash, "7777777", caller);

        console2.log("salt");
        console2.log(vm.toString(salt));

        config.salt = salt;
        config.deployedAddress = expectedAddress;
        config.creationCode = initCode;
        config.constructorArgs = deployer.proxyConstructorArgs();
        config.contractName = "Cointag";
        config.deploymentCaller = caller;
    }

    function run() public {
        address caller = vm.envAddress("DEPLOYER");

        vm.startBroadcast();

        // create a proxy deployer, which we can use to generate deterministic addresses and corresponding params
        DeterministicDeployerAndCaller deployer = createOrGetDeployerAndCaller();

        vm.stopBroadcast();

        DeterministicContractConfig memory cointagsConfig = mineForCointagAddress(deployer, caller);
        saveDeterministicContractConfig(cointagsConfig, "cointagFactory");
    }
}
