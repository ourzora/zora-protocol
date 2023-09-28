// spdx-license-identifier: mit
pragma solidity ^0.8.17;

import "forge-std/Script.sol";
import "forge-std/console2.sol";

import {ZoraDeployerBase} from "./ZoraDeployerBase.sol";
import {Zora1155PremintExecutor} from "../src/proxies/Zora1155PremintExecutor.sol";
import {ProxyShim} from "../src/utils/ProxyShim.sol";
import {LibString} from "solady/utils/LibString.sol";
import {Create2} from "@openzeppelin/contracts/utils/Create2.sol";
import {ZoraDeployerUtils} from "../src/deployment/ZoraDeployerUtils.sol";
import {DeterministicDeployerScript, DeterministicParams} from "../src/deployment/DeterministicDeployerScript.sol";
import {DeterministicProxyDeployer} from "../src/deployment/DeterministicProxyDeployer.sol";
import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";

/// @title Gets parameters for determinstically deploying a new 1155 factory proxy at an address starting with 0x777777, regardless of the chain.
/// Example usage: DEPLOYER=0xf69fEc6d858c77e969509843852178bd24CAd2B6 forge script script/GetDeterminsticParam.s.sol --rpc-url https://testnet.rpc.zora.energy --ffi
/// @author
/// @notice
contract PremintProxyDeterminsticParams is ZoraDeployerBase, DeterministicDeployerScript {
    function run() public returns (DeterministicParams memory determinsticParams) {
        address deployerAddress = 0x4F9991C82C76aE04CC39f23aB909AA919886ba12;

        bytes memory proxyCreationCode = type(Zora1155PremintExecutor).creationCode;

        determinsticParams = getDeterministicDeploymentParams(deployerAddress, proxyCreationCode, 200);

        serializeAndSaveOutput(determinsticParams, "premintExecutorProxy");
    }
}
