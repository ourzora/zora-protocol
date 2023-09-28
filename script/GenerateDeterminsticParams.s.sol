// spdx-license-identifier: mit
pragma solidity ^0.8.17;

import "forge-std/Script.sol";
import "forge-std/console2.sol";

import {ZoraDeployerBase} from "./ZoraDeployerBase.sol";
import {Zora1155Factory} from "../src/proxies/Zora1155Factory.sol";
import {ProxyShim} from "../src/utils/ProxyShim.sol";
import {LibString} from "solady/utils/LibString.sol";
import {Create2} from "@openzeppelin/contracts/utils/Create2.sol";
import {ZoraDeployer} from "../src/deployment/ZoraDeployer.sol";
import {DeterminsticDeployer, DeterminsticParams} from "../src/deployment/DeterminsticDeployer.sol";
import {NewFactoryProxyDeployer} from "../src/deployment/NewFactoryProxyDeployer.sol";
import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";

/// @title Gets parameters for determinstically deploying a new factory proxy at an address starting with 0x777777, regardless of the chain.
/// Example usage: DEPLOYER=0xf69fEc6d858c77e969509843852178bd24CAd2B6 forge script script/GetDeterminsticParam.s.sol --rpc-url https://testnet.rpc.zora.energy --ffi
/// @author
/// @notice
contract GetDeterminsticParam is ZoraDeployerBase, DeterminsticDeployer {
    function run() public {
        deployerAddress = 0x4F9991C82C76aE04CC39f23aB909AA919886ba12;

        proxyCreationCode = type(Zora1155Factory).creationCode;

        (
            bytes32 proxyDeployerSalt,
            bytes memory newFactoryDeployerCreationCode,
            address proxyDeployerAddress,
            bytes32 proxyShimSalt,
            bytes32 proxySalt,
            address determinsticProxyAddress
        ) = getDeterminsticDeploymentParams(deployerAddress, proxyCreationCode);

        DeterminsticParams memory result = DeterminsticParams({
            proxyDeployerCreationCode: newFactoryDeployerCreationCode,
            proxyCreationCode: proxyCreationCode,
            deployerAddress: deployerAddress,
            proxyDeployerAddress: proxyDeployerAddress,
            proxyDeployerSalt: proxyDeployerSalt,
            proxyShimSalt: proxyShimSalt,
            proxySalt: proxySalt,
            determinsticProxyAddress: determinsticProxyAddress
        });

        serializeAndSaveOutput(result);

        // extract results
        console2.log("deployer address: ", deployerAddress);
        // only used for test purposes
        // console2.log("deployer pivate key", deployerPrivateKey);
        console2.log("new factory proxy deployer salt:", vm.toString(proxyDeployerSalt));
        console2.log("proxy shim bytes32 salt:", vm.toString(proxyShimSalt));
        console2.log("factory proxy bytes32 salt: ", vm.toString(proxySalt));
        console2.log("expected address: ", determinsticProxyAddress);
    }
}
