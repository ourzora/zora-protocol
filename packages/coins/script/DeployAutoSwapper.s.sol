// SPDX-License-Identifier: MIT

pragma solidity ^0.8.28;

import {CoinsDeployerBase} from "../src/deployment/CoinsDeployerBase.sol";
import {AutoSwapper} from "../src/utils/AutoSwapper.sol";
import {ISwapRouter} from "@zoralabs/shared-contracts/interfaces/uniswap/ISwapRouter.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import "forge-std/console.sol";

contract Deploy is CoinsDeployerBase {
    function run() public {
        address swapper = vm.envAddress("SWAPPER");

        vm.startBroadcast();

        AutoSwapper autoSwapper = new AutoSwapper(ISwapRouter(getUniswapSwapRouter()), getZoraRecipient(), swapper);

        vm.stopBroadcast();

        console.log("multisig:", autoSwapper.swapRecipient());

        console.log("target:", address(autoSwapper));

        console.log("approval call:");
        bytes memory call = abi.encodeWithSelector(IERC20.approve.selector, address(autoSwapper), type(uint256).max);
        console.logBytes(call);
    }
}
