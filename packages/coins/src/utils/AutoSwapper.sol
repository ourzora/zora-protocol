// SPDX-License-Identifier: ZORA-DELAYED-OSL-v1
// This software is licensed under the Zora Delayed Open Source License.
// Under this license, you may use, copy, modify, and distribute this software for
// non-commercial purposes only. Commercial use and competitive products are prohibited
// until the "Open Date" (3 years from first public distribution or earlier at Zora's discretion),
// at which point this software automatically becomes available under the MIT License.
// Full license terms available at: https://docs.zora.co/coins/license
pragma solidity ^0.8.28;

import {ISwapRouter} from "@zoralabs/shared-contracts/interfaces/uniswap/ISwapRouter.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Path} from "./uniswap/Path.sol";

/// @title AutoSwapper
/// @notice A contract that allows for swapping of tokens via a uniswap v3 swap router. Only works with Uniswap V3 swaps.
/// @dev Requires that the currency to swap has been approved to this contract to spend.
contract AutoSwapper {
    ISwapRouter public immutable router;

    error NotSwapper();
    error InvalidSelector();
    error InvalidRecipient();

    address public immutable swapper;

    address public immutable swapRecipient;

    modifier onlySwapper() {
        require(msg.sender == swapper, NotSwapper());
        _;
    }

    // copy of ExactInputSingleParams from uniswap v3 ISwapRouter, but without the recipient,
    // since it gets set by this contract
    struct ExactInputSingleParams {
        address tokenIn;
        address tokenOut;
        uint24 fee;
        uint256 amountIn;
        uint256 amountOutMinimum;
        uint160 sqrtPriceLimitX96;
    }

    // copy of ExactInputParams from uniswap v3 ISwapRouter, but without the recipient,
    // since it gets set by this contract
    struct ExactInputParams {
        bytes path;
        uint256 amountIn;
        uint256 amountOutMinimum;
    }

    constructor(ISwapRouter _router, address _swapRecipient, address _swapper) {
        router = _router;
        swapRecipient = _swapRecipient;
        swapper = _swapper;
    }

    function swapExactInputSingle(ExactInputSingleParams memory params) external onlySwapper returns (uint256 amountOut) {
        // approve the currency to the swap router
        _approveCurrencyToSwapRouter(params.tokenIn, params.amountIn);

        // swap the currency
        return
            router.exactInputSingle(
                ISwapRouter.ExactInputSingleParams({
                    tokenIn: params.tokenIn,
                    tokenOut: params.tokenOut,
                    fee: params.fee,
                    // set the recipient to the swap recipient
                    recipient: swapRecipient,
                    amountIn: params.amountIn,
                    amountOutMinimum: params.amountOutMinimum,
                    sqrtPriceLimitX96: params.sqrtPriceLimitX96
                })
            );
    }

    function swapExactInput(ExactInputParams memory params) external onlySwapper returns (uint256 amountOut) {
        // parse the token in from the path, and approve the currency to the swap router
        address tokenIn = _getTokenInFromPath(params.path);
        _approveCurrencyToSwapRouter(tokenIn, params.amountIn);

        // swap the currency
        return
            router.exactInput(
                ISwapRouter.ExactInputParams({
                    path: params.path,
                    // set the recipient to the swap recipient
                    recipient: swapRecipient,
                    amountIn: params.amountIn,
                    amountOutMinimum: params.amountOutMinimum
                })
            );
    }

    // requires the currency has been approved to spend the amount from the swap recipient
    function _approveCurrencyToSwapRouter(address currency, uint256 amount) internal {
        IERC20(currency).transferFrom(swapRecipient, address(this), amount);
        IERC20(currency).approve(address(router), amount);
    }

    function _getTokenInFromPath(bytes memory path) internal pure returns (address tokenIn) {
        (tokenIn, , ) = Path.decodeFirstPool(path);
    }
}
