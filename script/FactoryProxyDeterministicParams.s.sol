// spdx-license-identifier: mit
pragma solidity ^0.8.17;

import "forge-std/Script.sol";
import "forge-std/console2.sol";

import {ZoraDeployerBase} from "./ZoraDeployerBase.sol";
import {Zora1155Factory} from "../src/proxies/Zora1155Factory.sol";
import {ProxyShim} from "../src/utils/ProxyShim.sol";
import {LibString} from "solady/utils/LibString.sol";
import {Create2} from "@openzeppelin/contracts/utils/Create2.sol";
import {ZoraDeployerUtils} from "../src/deployment/ZoraDeployerUtils.sol";
import {DeterministicDeployerScript, DeterministicParams} from "../src/deployment/DeterministicDeployerScript.sol";
import {DeterministicProxyDeployer} from "../src/deployment/DeterministicProxyDeployer.sol";
import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";

/// @title Gets parameters for determinstically deploying a new 1155 factory proxy at an address starting with 0x777777, regardless of the chain.
/// Example usage: DEPLOYER=0xf69fEc6d858c77e969509843852178bd24CAd2B6 forge script script/GetDeterminsticParam.s.sol --rpc-url https://testnet.rpc.zora.energy --ffi
/// @author doved
/// @notice Ensure to set env variable for DEPLOYER
contract FactoryProxyDeterministicParams is ZoraDeployerBase, DeterministicDeployerScript {
    function run() public returns (DeterministicParams memory deterministicParams) {
        address deployerAddress = vm.envAddress("DEPLOYER");

        bytes memory proxyCreationCode = type(Zora1155Factory).creationCode;

        deterministicParams = getDeterministicDeploymentParams(deployerAddress, proxyCreationCode, 100);

        serializeAndSaveOutput(deterministicParams, "factoryProxy");
    }
}
