// spdx-license-identifier: mit
pragma solidity ^0.8.17;

import "forge-std/Script.sol";
import "forge-std/console2.sol";

import {ZoraDeployerBase} from "../src/deployment/ZoraDeployerBase.sol";
import {Zora1155Factory} from "../src/proxies/Zora1155Factory.sol";
import {ProxyShim} from "../src/utils/ProxyShim.sol";
import {UpgradeGate} from "../src/upgrades/UpgradeGate.sol";
import {LibString} from "solady/utils/LibString.sol";
import {Create2} from "@openzeppelin/contracts/utils/Create2.sol";
import {ZoraDeployerUtils} from "../src/deployment/ZoraDeployerUtils.sol";
import {Zora1155PremintExecutor} from "../src/proxies/Zora1155PremintExecutor.sol";
import {DeterministicDeployerScript, DeterministicParams} from "../src/deployment/DeterministicDeployerScript.sol";
import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";

/// @title Gets parameters for deterministically deploying a new 1155 factory proxy at an address starting with 0x777777, regardless of the chain.
/// @dev Example usage: DEPLOYER=0xf69fEc6d858c77e969509843852178bd24CAd2B6 forge script script/GetDeterminsticParam.s.sol --rpc-url https://testnet.rpc.zora.energy --ffi
/// @author doved
/// @notice Ensure to set env variable for DEPLOYER
contract FactoryProxyDeterministicParams is ZoraDeployerBase {
    address deployerAddress;
    // Set in step 2
    address proxyDeployerAddress;

    function run() public {
        vm.createSelectFork("zora_sepolia");

        deployerAddress = vm.envAddress("TURNKEY_TARGET_ADDRESS");

        calculateForFactoryProxy();
        calculateForPremintExecutorProxy();

        // Note: relies on proxyDeployerAddress
        calculateUpgradeGateAddress();
    }

    function calculateForFactoryProxy() internal {
        bytes memory proxyCreationCode = type(Zora1155Factory).creationCode;

        DeterministicParams memory deterministicParams = getDeterministicDeploymentParams(deployerAddress, proxyCreationCode, 100);

        proxyDeployerAddress = deterministicParams.proxyDeployerAddress;

        mkdir("deterministicConfig/factoryProxy");
        serializeAndSaveOutput(deterministicParams, "factoryProxy");
    }

    function calculateForPremintExecutorProxy() internal {
        bytes memory proxyCreationCode = type(Zora1155PremintExecutor).creationCode;

        DeterministicParams memory deterministicParams = getDeterministicDeploymentParams(deployerAddress, proxyCreationCode, 200);

        mkdir("deterministicConfig/premintExecutorProxy");
        serializeAndSaveOutput(deterministicParams, "premintExecutorProxy");
    }

    // @notice Since this doesn't
    function calculateUpgradeGateAddress() internal {
        bytes memory creationCodeUpgradeGate = type(UpgradeGate).creationCode;
        bytes32 salt = saltWithAddressInFirst20Bytes(deployerAddress, 20);
        address resultAddress = Create2.computeAddress(salt, keccak256(creationCodeUpgradeGate), proxyDeployerAddress);

        vm.serializeAddress("UPGRADE_GATE_JSON", "deployerAddress", deployerAddress);
        vm.serializeAddress("UPGRADE_GATE_JSON", "upgradeGateAddress", resultAddress);
        vm.serializeAddress("UPGRADE_GATE_JSON", "proxyDeployerAddress", proxyDeployerAddress);
        vm.serializeBytes32("UPGRADE_GATE_JSON", "salt", salt);
        string memory output = vm.serializeBytes("UPGRADE_GATE_JSON", "creationCode", creationCodeUpgradeGate);

        console2.log(output);

        mkdir("deterministicConfig/upgradeGate");
        vm.writeJson(output, paramsFilePath("upgradeGate"));
    }

    function mkdir(string memory path) internal {
        string[] memory commands = new string[](3);
        commands[0] = "mkdir";
        commands[1] = "-p";
        commands[2] = path;
        vm.ffi(commands);
    }
}
