// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "../BaseTest.sol";
import "./Handler.sol";

import "../../src/ERC20Z.sol";

interface IPool {
    function liquidity() external view returns (uint128);
}

contract InitialLiquidityTest is BaseTest {
    ERC20Z public erc20z;
    IPool public pool;

    uint64 internal saleStart;
    uint64 internal saleEnd;

    Handler internal handler;

    function setUp() public override {
        super.setUp();

        saleStart = uint64(block.timestamp);

        IZoraTimedSaleStrategy.SalesConfigV2 memory salesConfig = IZoraTimedSaleStrategy.SalesConfigV2({
            saleStart: saleStart,
            marketCountdown: DEFAULT_MARKET_COUNTDOWN,
            minimumMarketEth: DEFAULT_MINIMUM_MARKET_ETH,
            name: "Test",
            symbol: "TST"
        });
        vm.prank(users.creator);
        collection.callSale(tokenId, saleStrategy, abi.encodeWithSelector(saleStrategy.setSaleV2.selector, tokenId, salesConfig));

        IZoraTimedSaleStrategy.SaleData memory saleStorage = saleStrategy.saleV2(address(collection), tokenId);

        erc20z = ERC20Z(saleStorage.erc20zAddress);
        pool = IPool(saleStorage.poolAddress);

        uint256 numMints = 1000;
        uint256 ethAmount = numMints * mintFee;

        vm.deal(users.collector, ethAmount);

        vm.prank(users.collector);
        saleStrategy.mint{value: ethAmount}(users.collector, numMints, address(collection), tokenId, users.mintReferral, "");

        vm.warp(block.timestamp + DEFAULT_MARKET_COUNTDOWN + 1);

        handler = new Handler(saleStrategy, address(collection), tokenId);

        targetContract(address(handler));
    }

    function invariant_noLiquidityBeforeActivate() public view {
        IZoraTimedSaleStrategy.SaleData memory sale = saleStrategy.saleV2(address(collection), tokenId);

        if (!sale.secondaryActivated) {
            uint128 liquidity = pool.liquidity();
            assertEq(liquidity, 0, "Liquidity added to Uniswap V3 pool before market activation");
        }
    }
}
