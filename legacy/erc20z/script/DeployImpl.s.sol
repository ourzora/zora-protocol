// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import "forge-std/console2.sol";

import {DeployerBase} from "./DeployerBase.sol";
import {ZoraTimedSaleStrategyImpl} from "../src/minter/ZoraTimedSaleStrategyImpl.sol";
import {ZoraTimedSaleStrategy} from "../src/minter/ZoraTimedSaleStrategy.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";

/// @notice Deploy Implementation of TimedSaleStrategy only
contract DeployImpl is DeployerBase {
    function run() public {
        DeploymentConfig memory config = readDeployment();
        vm.startBroadcast();

        ZoraTimedSaleStrategyImpl impl = new ZoraTimedSaleStrategyImpl();
        config.saleStrategyImpl = address(impl);
        config.saleStrategyImplVersion = impl.contractVersion();

        vm.stopBroadcast();

        console2.log("Sales StrategyImpl deployed, to upgrade:");
        console2.log("target:", config.saleStrategy);
        console2.log("calldata:");
        console2.logBytes(abi.encodeWithSelector(UUPSUpgradeable.upgradeToAndCall.selector, config.saleStrategyImpl, ""));
        console2.log("multisig:", getProxyAdmin());

        saveDeployment(config);
    }
}
