// SPDX-License-Identifier: ZORA-DELAYED-OSL-v1
// This software is licensed under the Zora Delayed Open Source License.
// Under this license, you may use, copy, modify, and distribute this software for
// non-commercial purposes only. Commercial use and competitive products are prohibited
// until the "Open Date" (3 years from first public distribution or earlier at Zora's discretion),
// at which point this software automatically becomes available under the MIT License.
// Full license terms available at: https://docs.zora.co/coins/license
pragma solidity ^0.8.23;

import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {Commands} from "@uniswap/universal-router/contracts/libraries/Commands.sol";
import {Actions} from "@uniswap/v4-periphery/src/libraries/Actions.sol";
import {IV4Router} from "@uniswap/v4-periphery/src/interfaces/IV4Router.sol";
import {CoinCommon} from "./CoinCommon.sol";
import {IPermit2} from "permit2/src/interfaces/IPermit2.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Currency} from "@uniswap/v4-core/src/types/Currency.sol";
import {ISwapPathRouter} from "../interfaces/ISwapPathRouter.sol";
import {IHasPoolKey} from "../interfaces/ICoin.sol";
import {IERC165} from "@openzeppelin/contracts/utils/introspection/IERC165.sol";
import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {PathKey} from "@uniswap/v4-periphery/src/libraries/PathKey.sol";

library UniV4SwapHelper {
    function buildExactInputMultiSwapCommand(
        address currencyIn,
        uint128 amountIn,
        PoolKey[] memory keys,
        uint128 minAmountOut,
        bytes[] memory hopHookData
    ) internal pure returns (bytes memory commands, bytes[] memory inputs) {
        require(keys.length > 0 && hopHookData.length == keys.length, "invalid lengths");

        PathKey[] memory path = new PathKey[](keys.length);

        Currency currency = Currency.wrap(currencyIn);
        Currency finalCurrencyOut;

        for (uint256 i; i < keys.length; ++i) {
            Currency out = currency == keys[i].currency0 ? keys[i].currency1 : keys[i].currency0;
            path[i] = PathKey({intermediateCurrency: out, fee: keys[i].fee, tickSpacing: keys[i].tickSpacing, hooks: keys[i].hooks, hookData: hopHookData[i]});
            currency = out;
            finalCurrencyOut = out;
        }

        bytes memory actions = abi.encodePacked(uint8(Actions.SWAP_EXACT_IN), uint8(Actions.SETTLE), uint8(Actions.TAKE_ALL));
        bytes[] memory params = new bytes[](3);
        params[0] = abi.encode( // 1) SWAP_EXACT_IN({ currencyIn, path, amountIn, amountOutMinimum })
                IV4Router.ExactInputParams({currencyIn: Currency.wrap(currencyIn), path: path, amountIn: amountIn, amountOutMinimum: minAmountOut})
            );
        params[1] = abi.encode(currencyIn, amountIn, true); // 2) SETTLE(tokenIn, amountIn, payerIsUser=true) — pulls from user via Permit2
        params[2] = abi.encode(Currency.unwrap(finalCurrencyOut), minAmountOut); // 3) TAKE_ALL(finalCurrencyOut, minOut)

        commands = abi.encodePacked(uint8(Commands.V4_SWAP));

        inputs = new bytes[](1);
        inputs[0] = abi.encode(actions, params);
    }

    function buildExactInputSingleSwapCommand(
        address currencyIn,
        uint128 amountIn,
        address currencyOut,
        uint128 minAmountOut,
        PoolKey memory key,
        bytes memory hookData
    ) internal pure returns (bytes memory commands, bytes[] memory inputs) {
        bool zeroForOne = Currency.unwrap(key.currency0) == currencyIn;

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
