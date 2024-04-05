// spdx-license-identifier: mit
pragma solidity ^0.8.20;

import "forge-std/Script.sol";

import {DeterministicUUPSProxyDeployer} from "../src/DeterministicUUPSProxyDeployer.sol";
import {LibString} from "solady/utils/LibString.sol";
import {ProxyDeployerUtils} from "../src/ProxyDeployerUtils.sol";
import {ProxyDeployerConfig} from "../src/Config.sol";
import {ProxyDeployerScript} from "../src/ProxyDeployerScript.sol";
import {ZoraMintsManager} from "@zoralabs/mints-contracts/src/ZoraMintsManager.sol";
import {ZoraMintsManagerImpl} from "@zoralabs/mints-contracts/src/ZoraMintsManagerImpl.sol";
import {ImmutableCreate2FactoryUtils} from "@zoralabs/shared-contracts/utils/ImmutableCreate2FactoryUtils.sol";
import {ZoraMints1155} from "@zoralabs/mints-contracts/src/ZoraMints1155.sol";
import {DeterminsticContractConfig, MintsDeterministicConfig} from "../src/Config.sol";

/// @dev This script saves the current bytecode, and initialization parameters for the Mints proxy,
/// which then need to be populated with a salt and expected address, which can be achieved by
/// running the printed create2crunch command.  The resulting config only needs to be generated once
/// and is reusable for all chains.
contract GenerateDeterminsticDeployment is ProxyDeployerScript {
    // copied from: https://github.com/karmacoma-eth/foundry-playground/blob/main/script/MineSaltScript.sol#L17C1-L36C9
    function mineSalt(
        address deployer,
        bytes32 initCodeHash,
        string memory startsWith,
        address caller
    ) internal returns (bytes32 salt, address expectedAddress) {
        string[] memory args;

        // if there is no caller, we dont need to add the caller to the args
        if (caller == address(0)) args = new string[](8);
        else {
            args = new string[](10);
        }
        args[0] = "cast";
        args[1] = "create2";
        args[2] = "--starts-with";
        args[3] = startsWith;
        args[4] = "--deployer";
        args[5] = LibString.toHexString(deployer);
        args[6] = "--init-code-hash";
        args[7] = LibString.toHexStringNoPrefix(uint256(initCodeHash), 32);
        // if there is a caller, add the caller to the args, enforcing the first 20 bytes will match.
        if (caller != address(0)) {
            args[8] = "--caller";
            args[9] = LibString.toHexString(caller);
        }
        string memory result = string(vm.ffi(args));

        console2.log(result);

        uint256 addressIndex = LibString.indexOf(result, "Address: ");
        string memory addressStr = LibString.slice(result, addressIndex + 9, addressIndex + 9 + 42);
        expectedAddress = vm.parseAddress(addressStr);

        uint256 saltIndex = LibString.indexOf(result, "Salt: ");
        // bytes lengh is 32, + 0x
        // slice is start to end exclusive
        // if start is saltIndex + 6, end should be startIndex + 6 + 64 + 0x (2)
        uint256 startBytes32 = saltIndex + 6;
        string memory saltStr = LibString.slice(result, startBytes32, startBytes32 + 66);

        salt = vm.parseBytes32(saltStr);
    }

    function mineForProxyAddress(DeterministicUUPSProxyDeployer proxyDeployer, address caller) private returns (DeterminsticContractConfig memory config) {
        // get proxy creation code
        bytes memory creationCode = type(ZoraMintsManager).creationCode;
        // get the expected init code for the proxy from the proxyDeployer
        bytes memory initCode = proxyDeployer.proxyCreationCode(creationCode);
        bytes32 initCodeHash = keccak256(initCode);

        // proxyDeployer is deployer
        address deployer = address(proxyDeployer);

        (bytes32 salt, address expectedAddress) = mineSalt(deployer, initCodeHash, "7777777", caller);

        console2.log("salt");
        console2.log(vm.toString(salt));

        config.salt = salt;
        config.deployedAddress = expectedAddress;
        config.creationCode = creationCode;
        config.constructorArgs = proxyDeployer.proxyConstructorArgs();
        config.contractName = "ZoraMintsManager";
    }

    function mineForMints1155Address(address mintsManagerAddress) private returns (DeterminsticContractConfig memory config) {
        // mints 1155 is created from the zora mints manager impl, without any arguments
        bytes memory creationCode = type(ZoraMints1155).creationCode;
        bytes32 initCodeHash = keccak256(creationCode);
        // mints manager is deployer
        (bytes32 salt, address expectedAddress) = mineSalt(mintsManagerAddress, initCodeHash, "7777777", address(0));

        config.salt = salt;
        config.deployedAddress = expectedAddress;
        config.creationCode = creationCode;
        // no constructor args for mints 1155
        config.contractName = "ZoraMints1155";
    }

    function run() public {
        address deployer = vm.envAddress("DEPLOYER");

        vm.startBroadcast();

        // create a proxy deployer, which we can use to generated determistic addresses and corresponding params.
        // proxy deployer code is based on code saved to file from running the script SaveProxyDeployerConfig.s.sol
        DeterministicUUPSProxyDeployer proxyDeployer = createOrGetDeterministicProxyDeployer();

        vm.stopBroadcast();

        MintsDeterministicConfig memory config;

        config.manager = mineForProxyAddress(proxyDeployer, deployer);
        config.mints1155 = mineForMints1155Address(config.manager.deployedAddress);

        config.deploymentCaller = deployer;

        writeMintsMintsDeterministicConfig(config, "mintsProxy");
    }
}
