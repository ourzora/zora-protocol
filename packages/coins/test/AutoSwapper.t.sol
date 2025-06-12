// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "forge-std/Test.sol";
import {ISwapRouter} from "@zoralabs/shared-contracts/interfaces/uniswap/ISwapRouter.sol";
import {AutoSwapper} from "../src/utils/AutoSwapper.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {TickMath} from "../src/utils/uniswap/TickMath.sol";

contract AutoSwapperTest is Test {
    address internal constant SWAP_ROUTER = 0x2626664c2603336E57B271c5C0b26F421741e481;
    address internal constant WETH_ADDRESS = 0x4200000000000000000000000000000000000006;
    address internal constant USDC_ADDRESS = 0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913;
    address internal constant ZORA_ADDRESS = 0x1111111111166b7FE7bd91427724B487980aFc69;

    address internal constant ZORA_RECIPIENT = 0x7bf90111Ad7C22bec9E9dFf8A01A44713CC1b1B6;

    ISwapRouter internal swapRouter;

    address internal swapper = makeAddr("swapper");
    address internal swapRecipient = ZORA_RECIPIENT;

    AutoSwapper public autoSwapper;

    function setUp() public {
        vm.createSelectFork("base", 31216197);
        swapRouter = ISwapRouter(SWAP_ROUTER);

        autoSwapper = new AutoSwapper(swapRouter, swapRecipient, swapper);
    }

    function _getSqrtPriceLimitX96(bool zeroForOne) internal pure returns (uint160) {
        return zeroForOne ? TickMath.MIN_SQRT_PRICE + 1 : TickMath.MAX_SQRT_PRICE - 1;
    }

    function test_swapExactInputSingleWorks() public {
        uint256 amountToSwap = IERC20(ZORA_ADDRESS).balanceOf(swapRecipient) / 2;

        uint256 amountOutMin = 0;

        bool zeroForOne = ZORA_ADDRESS < USDC_ADDRESS;

        AutoSwapper.ExactInputSingleParams memory params = AutoSwapper.ExactInputSingleParams({
            tokenIn: ZORA_ADDRESS,
            tokenOut: USDC_ADDRESS,
            // 0.3% fee
            fee: 3000,
            amountIn: amountToSwap,
            amountOutMinimum: amountOutMin,
            sqrtPriceLimitX96: _getSqrtPriceLimitX96(zeroForOne)
        });

        vm.prank(swapRecipient);
        IERC20(ZORA_ADDRESS).approve(address(autoSwapper), amountToSwap);

        uint256 usdcBalanceBefore = IERC20(USDC_ADDRESS).balanceOf(swapRecipient);

        uint256 zoraBalanceBefore = IERC20(ZORA_ADDRESS).balanceOf(swapRecipient);

        vm.prank(swapper);
        uint256 amountOut = autoSwapper.swapExactInputSingle(params);

        assertEq(amountOut, IERC20(USDC_ADDRESS).balanceOf(swapRecipient) - usdcBalanceBefore);

        assertEq(IERC20(ZORA_ADDRESS).balanceOf(swapRecipient), zoraBalanceBefore - amountToSwap);
    }

    function test_swap_revertsIfNotSwapper() public {
        vm.expectRevert(AutoSwapper.NotSwapper.selector);
        autoSwapper.swapExactInputSingle(
            AutoSwapper.ExactInputSingleParams({
                tokenIn: ZORA_ADDRESS,
                tokenOut: USDC_ADDRESS,
                fee: 3000,
                amountIn: 1000,
                amountOutMinimum: 0,
                sqrtPriceLimitX96: 0
            })
        );
    }

    function test_swapExactInputWorks() public {
        // test zora to weth to usdc
        uint24 poolFee = 3000;
        bytes memory path = abi.encodePacked(ZORA_ADDRESS, poolFee, WETH_ADDRESS, poolFee, USDC_ADDRESS);

        uint256 amountToSwap = IERC20(ZORA_ADDRESS).balanceOf(swapRecipient) / 2;

        AutoSwapper.ExactInputParams memory params = AutoSwapper.ExactInputParams({path: path, amountIn: amountToSwap, amountOutMinimum: 0});

        vm.prank(swapRecipient);
        IERC20(ZORA_ADDRESS).approve(address(autoSwapper), amountToSwap);

        uint256 usdcBalanceBefore = IERC20(USDC_ADDRESS).balanceOf(swapRecipient);

        uint256 zoraBalanceBefore = IERC20(ZORA_ADDRESS).balanceOf(swapRecipient);

        vm.prank(swapper);
        uint256 amountOut = autoSwapper.swapExactInput(params);

        assertEq(amountOut, IERC20(USDC_ADDRESS).balanceOf(swapRecipient) - usdcBalanceBefore);

        assertEq(IERC20(ZORA_ADDRESS).balanceOf(swapRecipient), zoraBalanceBefore - amountToSwap);
    }

    function test_swapExactInput_revertsIfNotSwapper() public {
        vm.expectRevert(AutoSwapper.NotSwapper.selector);
        autoSwapper.swapExactInput(AutoSwapper.ExactInputParams({path: "", amountIn: 1000, amountOutMinimum: 0}));
    }
}
