// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Script.sol";

import {IWETH} from "@zoralabs/shared-contracts/interfaces/IWETH.sol";
import {stdJson} from "forge-std/StdJson.sol";
import {SecondarySwap} from "../src/helper/SecondarySwap.sol";
import {ProxyDeployerScript, DeterministicDeployerAndCaller, DeterministicContractConfig} from "@zoralabs/shared-contracts/deployment/ProxyDeployerScript.sol";
import {IZoraTimedSaleStrategy} from "../src/interfaces/IZoraTimedSaleStrategy.sol";
import {ISwapRouter} from "@zoralabs/shared-contracts/interfaces/uniswap/ISwapRouter.sol";
import {DeployerBase} from "./DeployerBase.sol";

contract DeploySwapHelper is DeployerBase {
    function getConfigAddressPath() internal view returns (string memory) {
        return string.concat("./addresses/", vm.toString(block.chainid), ".json");
    }

    function run() public {
        DeterministicContractConfig memory minterConfig = readDeterministicContractConfig("zoraTimedSaleStrategy");
        DeterministicContractConfig memory secondarySwap = readDeterministicContractConfig("secondarySwap");

        DeploymentConfig memory config = readDeployment();

        vm.startBroadcast();

        // get deployer contract
        DeterministicDeployerAndCaller deployer = createOrGetDeployerAndCaller();

        IWETH weth = IWETH(getWeth());
        ISwapRouter swapRouter = ISwapRouter(getUniswapSwapRouter());

        uint24 uniswapPoolFee = 10_000;

        // build init call
        bytes memory init = abi.encodeWithSelector(
            SecondarySwap.initialize.selector,
            weth,
            swapRouter,
            uniswapPoolFee,
            IZoraTimedSaleStrategy(minterConfig.deployedAddress)
        );

        // sign deployment with turnkey account
        bytes memory signature = signDeploymentWithTurnkey(secondarySwap, init, deployer);

        // deterministically deploy contract using the signature
        config.swapHelper = deployer.permitSafeCreate2AndCall(signature, secondarySwap.salt, secondarySwap.creationCode, init, secondarySwap.deployedAddress);

        console2.log("deployed to ", vm.toString(block.chainid), config.swapHelper);

        vm.stopBroadcast();

        saveDeployment(config);
    }
}
