// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

import "../BaseTest.sol";

import {SecondarySwap} from "../../src/helper/SecondarySwap.sol";

contract SecondarySwapTest is BaseTest {
    SecondarySwap internal secondarySwap;

    uint256 internal maxEthToSpend;
    uint256 internal minEthToAcquire;
    uint24 internal defaultUniswapFee = 10_000;
    uint160 internal sqrtPriceLimitX96;

    function setUp() public override {
        super.setUp();

        secondarySwap = new SecondarySwap(weth, swapRouter, defaultUniswapFee);
        vm.label(address(secondarySwap), "SECONDARY_SWAP");
    }

    function setSaleAndLaunchMarket(uint256 numMints) internal returns (address erc20zAddress, address poolAddress) {
        uint64 saleStart = uint64(block.timestamp);
        uint64 saleEnd = uint64(block.timestamp + 24 hours);

        IZoraTimedSaleStrategy.SalesConfig memory salesConfig = IZoraTimedSaleStrategy.SalesConfig({
            saleStart: saleStart,
            saleEnd: saleEnd,
            name: "Test",
            symbol: "TST"
        });
        vm.prank(users.creator);
        collection.callSale(tokenId, saleStrategy, abi.encodeWithSelector(saleStrategy.setSale.selector, tokenId, salesConfig));

        IZoraTimedSaleStrategy.SaleStorage memory saleStorage = saleStrategy.sale(address(collection), tokenId);
        erc20zAddress = saleStorage.erc20zAddress;
        poolAddress = saleStorage.poolAddress;

        vm.label(erc20zAddress, "ERC20Z");
        vm.label(poolAddress, "V3_POOL");

        uint256 totalValue = mintFee * numMints;
        vm.deal(users.collector, totalValue);

        vm.prank(users.collector);
        saleStrategy.mint{value: totalValue}(users.collector, numMints, address(collection), tokenId, users.mintReferral, "");

        vm.warp(saleEnd + 1);
        saleStrategy.launchMarket(address(collection), tokenId);
    }

    function testBuy() public {
        uint256 numMints = 111;

        (address erc20z, ) = setSaleAndLaunchMarket(numMints);

        address payable mockBuyer = payable(makeAddr("mockBuyer"));

        vm.deal(mockBuyer, 1 ether);

        uint256 num1155ToReceive = 1;

        uint256 before1155Balance = collection.balanceOf(mockBuyer, 0);

        maxEthToSpend = 1 ether;
        sqrtPriceLimitX96 = 0;

        vm.prank(mockBuyer);
        secondarySwap.buy1155{value: 1 ether}(erc20z, num1155ToReceive, mockBuyer, mockBuyer, maxEthToSpend, sqrtPriceLimitX96);

        uint256 after1155Balance = collection.balanceOf(mockBuyer, 0);

        assertEq(after1155Balance, before1155Balance + num1155ToReceive);
    }

    function testSell() public {
        uint256 numMints = 111;

        (address erc20z, ) = setSaleAndLaunchMarket(numMints);

        address payable mockBuyer = payable(makeAddr("mockBuyer"));
        vm.deal(mockBuyer, 1 ether);

        uint256 num1155ToReceive = 1;

        maxEthToSpend = 1 ether;
        sqrtPriceLimitX96 = 0;

        vm.prank(mockBuyer);
        secondarySwap.buy1155{value: 1 ether}(erc20z, num1155ToReceive, mockBuyer, mockBuyer, maxEthToSpend, sqrtPriceLimitX96);

        assertEq(collection.balanceOf(mockBuyer, 0), num1155ToReceive);

        uint256 num1155ToTransfer = 1;

        uint256 beforeEthBalance = address(mockBuyer).balance;

        minEthToAcquire = 0;

        vm.startPrank(mockBuyer);

        collection.setApprovalForAll(address(secondarySwap), true);
        secondarySwap.sell1155(erc20z, num1155ToTransfer, mockBuyer, minEthToAcquire, sqrtPriceLimitX96);

        vm.stopPrank();

        uint256 afterEthBalance = address(mockBuyer).balance;

        assertEq(collection.balanceOf(mockBuyer, 0), 0);
        assertTrue(afterEthBalance > beforeEthBalance);
    }
}
