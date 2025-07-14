// spdx-license-identifier: mit
pragma solidity ^0.8.20;

import "forge-std/Script.sol";

// import {DeterministicUUPSProxyDeployer} from "../src/DeterministicUUPSProxyDeployer.sol";
import {LibString} from "solady/utils/LibString.sol";
// import {ProxyDeployerUtils} from "../src/ProxyDeployerUtils.sol";
// import {ProxyDeployerConfig} from "../src/Config.sol";
// import {ProxyDeployerScript} from "../src/ProxyDeployerScript.sol";
import {ImmutableCreate2FactoryUtils} from "@zoralabs/shared-contracts/utils/ImmutableCreate2FactoryUtils.sol";
import {ProxyDeployerScript, DeterministicDeployerAndCaller, DeterministicContractConfig} from "@zoralabs/shared-contracts/deployment/ProxyDeployerScript.sol";
import {ZoraTimedSaleStrategy} from "../src/minter/ZoraTimedSaleStrategy.sol";
import {Royalties} from "../src/royalties/Royalties.sol";
import {Create2} from "@openzeppelin/contracts/utils/Create2.sol";

/// @dev This script saves the current bytecode, and initialization parameters for the Sparks proxy,
/// which then need to be populated with a salt and expected address, which can be achieved by
/// running the printed create2crunch command.  The resulting config only needs to be generated once
/// and is reusable for all chains.
contract GenerateDeterministicParams is ProxyDeployerScript {
    function mineForMinterProxyAddress(DeterministicDeployerAndCaller deployer, address caller) private returns (DeterministicContractConfig memory config) {
        // get proxy creation code
        // get the expected init code for the proxy from the uupsProxyDeployer
        bytes memory initCode = deployer.proxyCreationCode(type(ZoraTimedSaleStrategy).creationCode);
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
        config.contractName = "ZoraTimedSaleStrategy";
        config.deploymentCaller = caller;
    }

    function mineForRoyaltiesAddress(DeterministicDeployerAndCaller deployer, address caller) private returns (DeterministicContractConfig memory config) {
        // sparks 1155 is created from the zora sparks manager impl, without any arguments
        bytes memory creationCode = type(Royalties).creationCode;
        bytes32 initCodeHash = keccak256(creationCode);
        // sparks manager is deployer
        (bytes32 salt, address expectedAddress) = mineSalt(address(deployer), initCodeHash, "7777777", caller);

        config.salt = salt;
        config.deployedAddress = expectedAddress;
        config.creationCode = creationCode;
        // no constructor args for royalties - it is initialized
        config.contractName = "Royalties";
    }

    function run() public {
        address caller = vm.envAddress("DEPLOYER");

        generateAndSaveDeployerAndCallerConfig();

        vm.startBroadcast();

        // create a proxy deployer, which we can use to generated deterministic addresses and corresponding params.
        // proxy deployer code is based on code saved to file from running the script SaveProxyDeployerConfig.s.sol
        DeterministicDeployerAndCaller deployer = createOrGetDeployerAndCaller();

        vm.stopBroadcast();

        DeterministicContractConfig memory zoraTimedSaleStrategyConfig = mineForMinterProxyAddress(deployer, caller);
        DeterministicContractConfig memory royaltiesConfig = mineForRoyaltiesAddress(deployer, caller);

        saveDeterministicContractConfig(zoraTimedSaleStrategyConfig, "zoraTimedSaleStrategy");
        saveDeterministicContractConfig(royaltiesConfig, "royalties");
    }
}
