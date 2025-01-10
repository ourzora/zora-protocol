// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "forge-std/console2.sol";

import {CointagsDeployerBase} from "./CointagsDeployerBase.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {IVersionedContract} from "@zoralabs/shared-contracts/interfaces/IVersionedContract.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

contract DeployImpl is CointagsDeployerBase {
    function run() public {
        CointagsDeployment memory deployment = readDeployment();
        vm.startBroadcast();

        deployment.cointagImpl = address(deployCointagsImpl(deployment.upgradeGate));
        deployment.cointagFactoryImpl = address(deployCointagFactoryImpl(deployment.cointagImpl));
        deployment.cointagVersion = IVersionedContract(deployment.cointagImpl).contractVersion();

        vm.stopBroadcast();

        console2.log("CointagFactoryImpl deployed, to upgrade:");
        console2.log("target:", deployment.cointagFactory);
        console2.log("calldata:");
        console2.logBytes(abi.encodeWithSelector(UUPSUpgradeable.upgradeToAndCall.selector, deployment.cointagFactoryImpl, ""));
        console2.log("multisig:", Ownable(deployment.cointagFactory).owner());

        saveDeployment(deployment);
    }
}
