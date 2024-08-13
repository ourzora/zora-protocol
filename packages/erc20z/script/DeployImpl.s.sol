// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Script.sol";

import {IProtocolRewards} from "@zoralabs/protocol-rewards/src/interfaces/IProtocolRewards.sol";
import {IWETH} from "../src/interfaces/IWETH.sol";
import {INonfungiblePositionManager} from "../src/interfaces/uniswap/INonfungiblePositionManager.sol";
import {IZoraTimedSaleStrategy} from "../src/interfaces/IZoraTimedSaleStrategy.sol";

import {ERC20Z} from "../src/ERC20Z.sol";
import {ZoraTimedSaleStrategyImpl} from "../src/minter/ZoraTimedSaleStrategyImpl.sol";
import {ZoraTimedSaleStrategy} from "../src/minter/ZoraTimedSaleStrategy.sol";
import {Royalties} from "../src/royalties/Royalties.sol";
import {ProxyDeployerScript, DeterministicDeployerAndCaller, DeterministicContractConfig} from "@zoralabs/shared-contracts/deployment/ProxyDeployerScript.sol";
import {ImmutableCreate2FactoryUtils} from "@zoralabs/shared-contracts/utils/ImmutableCreate2FactoryUtils.sol";
import {ProxyShim} from "@zoralabs/shared-contracts/deployment/DeterministicDeployerAndCaller.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {LibString} from "solady/utils/LibString.sol";

// Temp script
contract DeployScript is ProxyDeployerScript {
    bytes32 constant IMMUTABLE_CREATE_2_FRIENDLY_SALT = bytes32(0x0000000000000000000000000000000000000000000000000000000000000000);

    function run() public {
        vm.startBroadcast();

        address result = ImmutableCreate2FactoryUtils.safeCreate2OrGetExistingWithFriendlySalt(type(ZoraTimedSaleStrategyImpl).creationCode);
        console2.log("Deployed to ", result);

        vm.stopBroadcast();
    }
}
