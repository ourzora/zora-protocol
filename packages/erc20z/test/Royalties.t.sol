// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import {Address} from "@openzeppelin/contracts/utils/Address.sol";
import {MockMintableERC721} from "./mock/MockMintableERC721.sol";
import {IRoyalties} from "../src/interfaces/IRoyalties.sol";
import {UniswapV3LiquidityCalculator} from "../src/uniswap/UniswapV3LiquidityCalculator.sol";
import {ReceiveRejector} from "@zoralabs/shared-contracts/mocks/ReceiveRejector.sol";
import {INonfungiblePositionManager} from "@zoralabs/shared-contracts/interfaces/uniswap/INonfungiblePositionManager.sol";

import "./BaseTest.sol";

contract RoyaltiesTest is BaseTest {
    uint24 internal constant CREATOR_ROYALTY = 10000;

    address internal buyer;

    function setUp() public override {
        super.setUp();

        buyer = makeAddr("buyer");
        vm.deal(buyer, 1 ether);

        weth.deposit{value: 1 ether}();
        weth.approve(address(swapRouter), 1 ether);
    }

    function setSaleAndLaunchMarket(uint256 numMints) internal returns (address erc20zAddress, address poolAddress) {
        uint64 saleStart = uint64(block.timestamp);

        IZoraTimedSaleStrategy.SalesConfigV2 memory salesConfig = IZoraTimedSaleStrategy.SalesConfigV2({
            saleStart: saleStart,
            marketCountdown: DEFAULT_MARKET_COUNTDOWN,
            minimumMarketEth: DEFAULT_MINIMUM_MARKET_ETH,
            name: "Test",
            symbol: "TST"
        });
        vm.prank(users.creator);
        collection.callSale(tokenId, saleStrategy, abi.encodeWithSelector(saleStrategy.setSaleV2.selector, tokenId, salesConfig));

        IZoraTimedSaleStrategy.SaleStorage memory saleStorage = saleStrategy.sale(address(collection), tokenId);
        erc20zAddress = saleStorage.erc20zAddress;
        poolAddress = saleStorage.poolAddress;

        vm.label(erc20zAddress, "ERC20Z");
        vm.label(poolAddress, "V3_POOL");

        uint256 totalValue = mintFee * numMints;
        vm.deal(users.collector, totalValue);

        vm.prank(users.collector);
        saleStrategy.mint{value: totalValue}(users.collector, numMints, address(collection), tokenId, users.mintReferral, "");

        vm.warp(block.timestamp + DEFAULT_MARKET_COUNTDOWN + 1);

        saleStrategy.launchMarket(address(collection), tokenId);
    }

    function testRevertsWhenZeroAddresses() public {
        Royalties royalties = new Royalties();
        // Test that weth address cannot be zero
        vm.expectRevert(IRoyalties.AddressZero.selector);
        royalties.initialize(IWETH(address(0)), nonfungiblePositionManager, payable(users.zoraRewardRecipient), 1000);

        // Test that nonfungiblePositionManager address cannot be zero
        vm.expectRevert(IRoyalties.AddressZero.selector);
        royalties.initialize(weth, INonfungiblePositionManager(address(0)), payable(users.zoraRewardRecipient), 1000);

        vm.expectRevert(IRoyalties.AddressZero.selector);
        royalties.initialize(weth, nonfungiblePositionManager, payable(address(0)), 1000);
    }

    function testRevertsWhenAlreadyInitialized() public {
        Royalties royalties = new Royalties();
        royalties.initialize(weth, nonfungiblePositionManager, payable(users.zoraRewardRecipient), 1000);

        vm.expectRevert(IRoyalties.AlreadyInitialized.selector);
        royalties.initialize(weth, nonfungiblePositionManager, payable(users.zoraRewardRecipient), 1000);
    }

    function testClaim() public {
        uint256 numMints = 1000;

        (address erc20zAddress, ) = setSaleAndLaunchMarket(numMints);

        uint256 num1155sToBuy = 1;

        ISwapRouter.ExactOutputSingleParams memory params = ISwapRouter.ExactOutputSingleParams({
            tokenIn: address(weth),
            tokenOut: erc20zAddress,
            fee: CREATOR_ROYALTY,
            recipient: buyer,
            amountOut: num1155sToBuy * 1e18,
            amountInMaximum: 1 ether,
            sqrtPriceLimitX96: 0
        });

        swapRouter.exactOutputSingle(params);

        uint256 expectedTotalEth = 1126846352977;
        uint256 totalEthAccrued = royalties.getUnclaimedFees(erc20zAddress).token1Amount;

        assertEq(totalEthAccrued, expectedTotalEth);

        address payable creator = payable(collection.getCreatorRewardRecipient(0));

        uint256 beforeEthBalance = creator.balance;
        uint256 beforeERC20Balance = IERC20Z(erc20zAddress).balanceOf(creator);

        vm.prank(creator);
        royalties.claim(address(erc20zAddress), creator);

        uint256 afterEthBalance = creator.balance;
        uint256 afterERC20Balance = IERC20Z(erc20zAddress).balanceOf(creator);

        uint256 fee = royalties.getFee(totalEthAccrued);
        uint256 remainingEth = totalEthAccrued - fee;

        assertEq(afterEthBalance - beforeEthBalance, remainingEth);
        assertEq(users.royaltyFeeRecipient.balance, fee);
        assertEq(afterERC20Balance - beforeERC20Balance, 0);
    }

    function testPositionReceivesWrongLiquidityToken() public {
        (address erc20zAddress, ) = setSaleAndLaunchMarket(1000);

        vm.deal(users.collector, 1.2 ether);

        vm.startPrank(users.collector);

        // get ERC20Z to users.collector to get erc20z tokens
        collection.safeTransferFrom(users.collector, erc20zAddress, 0, 10, "");

        bool wethFirst = address(weth) < erc20zAddress;

        uint256 erc20Liquidity = 0.001 ether;
        uint256 ethLiquidity = 1 ether;

        weth.deposit{value: 1 ether}();

        IERC20Z(erc20zAddress).approve(address(nonfungiblePositionManager), 1 ether);
        weth.approve(address(nonfungiblePositionManager), 1 ether);

        (, , /*address token0*/ /*address token1*/ uint256 amount0, uint256 amount1 /*uint128 liquidity*/, ) = UniswapV3LiquidityCalculator
            .calculateLiquidityAmounts(WETH_ADDRESS, ethLiquidity, address(this), erc20Liquidity);

        // Now we have erc20z, create a pair on uniswap
        INonfungiblePositionManager.MintParams memory params = INonfungiblePositionManager.MintParams({
            token0: wethFirst ? address(weth) : erc20zAddress,
            token1: wethFirst ? erc20zAddress : address(weth),
            fee: UniswapV3LiquidityCalculator.FEE,
            tickLower: UniswapV3LiquidityCalculator.TICK_LOWER,
            tickUpper: UniswapV3LiquidityCalculator.TICK_UPPER,
            amount0Desired: amount0,
            amount1Desired: amount1,
            amount0Min: 0,
            amount1Min: 0,
            recipient: users.collector,
            deadline: block.timestamp
        });

        (uint256 positionId /*uint256 lpLiquidity*/ /*uint256 lpAmount0*/ /*uint256 lpAmount1*/, , , ) = nonfungiblePositionManager.mint(params);

        vm.expectRevert(IRoyalties.OnlyErc20z.selector);
        nonfungiblePositionManager.safeTransferFrom(users.collector, address(royalties), positionId, "");
    }

    function testRevertReceivesIncorrectERC721() public {
        MockMintableERC721 mockMintableERC721 = new MockMintableERC721();
        address erc721Sender = makeAddr("erc721-mock-sender");
        vm.startPrank(erc721Sender);
        mockMintableERC721.mint(1);
        vm.expectRevert(IRoyalties.ERC721SenderRoyaltiesNeedsToBePositionManager.selector);
        mockMintableERC721.safeTransferFrom(erc721Sender, address(royalties), 1, "");
    }

    function testRevertRecipientCannotBeAddressZero() public {
        uint256 numMints = 1000;

        (address erc20zAddress, ) = setSaleAndLaunchMarket(numMints);

        uint256 num1155sToBuy = 1;

        ISwapRouter.ExactOutputSingleParams memory params = ISwapRouter.ExactOutputSingleParams({
            tokenIn: WETH_ADDRESS,
            tokenOut: erc20zAddress,
            fee: CREATOR_ROYALTY,
            recipient: buyer,
            amountOut: num1155sToBuy * 1e18,
            amountInMaximum: 1 ether,
            sqrtPriceLimitX96: 0
        });

        swapRouter.exactOutputSingle(params);

        address creator = collection.getCreatorRewardRecipient(0);

        vm.prank(creator);
        vm.expectRevert(abi.encodeWithSignature("AddressZero()"));
        royalties.claim(erc20zAddress, payable(address(0)));
    }

    function testRevertOnlyCreatorCanCall() public {
        uint256 numMints = 1000;

        (address erc20zAddress, ) = setSaleAndLaunchMarket(numMints);

        uint256 num1155sToBuy = 1;

        ISwapRouter.ExactOutputSingleParams memory params = ISwapRouter.ExactOutputSingleParams({
            tokenIn: address(weth),
            tokenOut: erc20zAddress,
            fee: CREATOR_ROYALTY,
            recipient: buyer,
            amountOut: num1155sToBuy * 1e18,
            amountInMaximum: 1 ether,
            sqrtPriceLimitX96: 0
        });

        swapRouter.exactOutputSingle(params);

        vm.expectRevert(abi.encodeWithSignature("OnlyCreatorCanCall()"));
        royalties.claim(erc20zAddress, payable(address(this)));
    }

    function testClaimForBothTokens() public {
        uint256 numMints = 1000;

        (address erc20zAddress, ) = setSaleAndLaunchMarket(numMints);

        uint256 num1155sToBuy = 1;

        ISwapRouter.ExactOutputSingleParams memory params = ISwapRouter.ExactOutputSingleParams({
            tokenIn: address(weth),
            tokenOut: erc20zAddress,
            fee: CREATOR_ROYALTY,
            recipient: buyer,
            amountOut: num1155sToBuy * 2e18,
            amountInMaximum: 1 ether,
            sqrtPriceLimitX96: 0
        });
        swapRouter.exactOutputSingle(params);

        vm.prank(buyer);
        IERC20Z(erc20zAddress).approve(address(swapRouter), type(uint256).max);

        vm.prank(buyer);
        swapRouter.exactInputSingle(
            ISwapRouter.ExactInputSingleParams({
                tokenIn: erc20zAddress,
                tokenOut: address(weth),
                fee: CREATOR_ROYALTY,
                recipient: buyer,
                amountIn: num1155sToBuy * 1e18,
                amountOutMinimum: 0,
                sqrtPriceLimitX96: 0
            })
        );

        uint256 expectedTotalEth = 2265074992347;
        uint256 expectedTotalErc20 = 9999999999999999;

        uint256 totalErc20Accrued = royalties.getUnclaimedFees(erc20zAddress).token0Amount;
        uint256 totalEthAccrued = royalties.getUnclaimedFees(erc20zAddress).token1Amount;

        assertEq(totalErc20Accrued, expectedTotalErc20);
        assertEq(totalEthAccrued, expectedTotalEth);

        address creator = collection.getCreatorRewardRecipient(0);

        uint256 beforeEthBalance = creator.balance;
        uint256 beforeERC20Balance = IERC20Z(erc20zAddress).balanceOf(creator);

        royalties.claimFor(erc20zAddress);

        uint256 afterEthBalance = creator.balance;
        uint256 afterERC20Balance = IERC20Z(erc20zAddress).balanceOf(creator);

        uint256 feeEth = royalties.getFee(expectedTotalEth);
        uint256 feeErc20 = royalties.getFee(expectedTotalErc20);

        assertEq(afterEthBalance - beforeEthBalance, expectedTotalEth - feeEth);
        assertEq(afterERC20Balance - beforeERC20Balance, expectedTotalErc20 - feeErc20);
        assertEq(users.royaltyFeeRecipient.balance, feeEth);
        assertEq(IERC20Z(erc20zAddress).balanceOf(users.royaltyFeeRecipient), feeErc20);
    }

    function testClaimTransfers() public {
        uint256 numMints = 1000;

        (address erc20zAddress, ) = setSaleAndLaunchMarket(numMints);

        uint256 num1155sToBuy = 1;

        ISwapRouter.ExactOutputSingleParams memory params = ISwapRouter.ExactOutputSingleParams({
            tokenIn: WETH_ADDRESS,
            tokenOut: erc20zAddress,
            fee: CREATOR_ROYALTY,
            recipient: buyer,
            amountOut: num1155sToBuy * 2e18,
            amountInMaximum: 1 ether,
            sqrtPriceLimitX96: 0
        });

        swapRouter.exactOutputSingle(params);

        address payable creator = payable(collection.getCreatorRewardRecipient(0));

        vm.etch(creator, address(new ReceiveRejector()).code);

        vm.prank(creator);
        vm.expectRevert(Address.FailedInnerCall.selector);
        royalties.claim(erc20zAddress, creator);

        vm.etch(creator, "");

        vm.prank(creator);
        royalties.claim(erc20zAddress, creator);
    }

    function testRevertCreatorMustBeSet() public {
        uint256 numMints = 1000;

        (address erc20zAddress, ) = setSaleAndLaunchMarket(numMints);

        uint256 num1155sToBuy = 1;

        ISwapRouter.ExactOutputSingleParams memory params = ISwapRouter.ExactOutputSingleParams({
            tokenIn: WETH_ADDRESS,
            tokenOut: erc20zAddress,
            fee: CREATOR_ROYALTY,
            recipient: buyer,
            amountOut: num1155sToBuy * 1e18,
            amountInMaximum: 1 ether,
            sqrtPriceLimitX96: 0
        });

        swapRouter.exactOutputSingle(params);

        collection.setCreator(address(0));

        vm.expectRevert(abi.encodeWithSignature("CreatorMustBeSet()"));
        royalties.claimFor(erc20zAddress);
    }

    function testRevertOnlyReceivableFromWeth() public {
        vm.prank(buyer);
        vm.expectRevert(abi.encodeWithSignature("OnlyWeth()"));
        Address.sendValue(payable(royalties), 1 ether);
    }
}
