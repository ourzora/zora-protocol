// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {Commands} from "@uniswap/universal-router/contracts/libraries/Commands.sol";
import {Actions} from "@uniswap/v4-periphery/src/libraries/Actions.sol";
import {IV4Router} from "@uniswap/v4-periphery/src/interfaces/IV4Router.sol";
import {CoinCommon} from "./CoinCommon.sol";
import {IPermit2} from "permit2/src/interfaces/IPermit2.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Currency} from "@uniswap/v4-core/src/types/Currency.sol";

library UniV4SwapHelper {
    function buildExactInputSingleSwapCommand(
        address currencyIn,
        uint128 amountIn,
        address currencyOut,
        uint128 minAmountOut,
        PoolKey memory key,
        bytes memory hookData
    ) internal pure returns (bytes memory commands, bytes[] memory inputs) {
        bool zeroForOne = Currency.unwrap(key.currency0) == currencyIn;

        // now buy some coin for usdc
        commands = abi.encodePacked(uint8(Commands.V4_SWAP));

        bytes memory actions = abi.encodePacked(uint8(Actions.SWAP_EXACT_IN_SINGLE), uint8(Actions.SETTLE_ALL), uint8(Actions.TAKE_ALL));

        bytes[] memory params = new bytes[](3);

        // First parameter: swap configuration
        params[0] = abi.encode(
            IV4Router.ExactInputSingleParams({
                poolKey: key,
                zeroForOne: zeroForOne,
                amountIn: amountIn, // amount of tokens we're swapping
                amountOutMinimum: minAmountOut, // minimum amount we expect to receive
                hookData: hookData
            })
        );

        // Second parameter: specify input tokens for the swap
        // encode SETTLE_ALL parameters
        params[1] = abi.encode(currencyIn, amountIn);

        // Third parameter: specify output tokens from the swap
        // encode TAKE_ALL parameters
        params[2] = abi.encode(currencyOut, minAmountOut);

        inputs = new bytes[](1);

        // Combine actions and params into inputs
        inputs[0] = abi.encode(actions, params);
    }

    function approveTokenWithPermit2(IPermit2 permit2, address router, address token, uint160 amount, uint48 expiration) internal {
        IERC20(token).approve(address(permit2), type(uint256).max);
        permit2.approve(token, router, amount, expiration);
    }
}
