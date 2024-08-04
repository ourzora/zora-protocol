// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Script.sol";

import {IWETH} from "../src/interfaces/IWETH.sol";
import {stdJson} from "forge-std/StdJson.sol";
import {SecondarySwap} from "../src/helper/SecondarySwap.sol";
import {ProxyDeployerScript, DeterministicDeployerAndCaller, DeterministicContractConfig} from "@zoralabs/shared-contracts/deployment/ProxyDeployerScript.sol";
import {ISwapRouter} from "../src/interfaces/uniswap/ISwapRouter.sol";

contract DeploySwapHelper is ProxyDeployerScript {
    function getConfigAddressPath() internal view returns (string memory) {
        return string.concat("./addresses/", vm.toString(block.chainid), ".json");
    }

    function run() public {
        vm.startBroadcast();

        IWETH weth = IWETH(getWeth());
        ISwapRouter swapRouter = ISwapRouter(getUniswapSwapRouter());

        uint24 uniswapPoolFee = 10_000;
        SecondarySwap secondarySwap = new SecondarySwap(weth, swapRouter, uniswapPoolFee);

        // stdJson.write(".SWAP_HELPER", getConfigAddressPath(), address(secondarySwap));
        console2.log("deployed to ", vm.toString(block.chainid), address(secondarySwap));
        console2.log(string.concat('   "SWAP_HELPER": "', vm.toString(address(secondarySwap)), '",'));
    }
}
