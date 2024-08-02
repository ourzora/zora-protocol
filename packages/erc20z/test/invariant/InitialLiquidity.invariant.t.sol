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
        saleEnd = uint64(block.timestamp + 1 hours);

        IZoraTimedSaleStrategy.SalesConfig memory salesConfig = IZoraTimedSaleStrategy.SalesConfig({
            saleStart: saleStart,
            saleEnd: saleEnd,
            name: "Test",
            symbol: "TST"
        });
        vm.prank(users.creator);
        collection.callSale(tokenId, saleStrategy, abi.encodeWithSelector(saleStrategy.setSale.selector, tokenId, salesConfig));

        IZoraTimedSaleStrategy.SaleStorage memory saleStorage = saleStrategy.sale(address(collection), tokenId);

        erc20z = ERC20Z(saleStorage.erc20zAddress);
        pool = IPool(saleStorage.poolAddress);

        uint256 numMints = 111;
        uint256 ethAmount = numMints * mintFee;

        vm.deal(users.collector, ethAmount);

        vm.prank(users.collector);
        saleStrategy.mint{value: ethAmount}(users.collector, numMints, address(collection), tokenId, users.mintReferral, "");

        vm.warp(saleEnd + 1);

        handler = new Handler(saleStrategy, address(collection), tokenId);

        targetContract(address(handler));
    }

    function invariant_noLiquidityBeforeActivate() public view {
        IZoraTimedSaleStrategy.SaleStorage memory sale = saleStrategy.sale(address(collection), tokenId);

        if (!sale.secondaryActivated) {
            uint128 liquidity = pool.liquidity();
            assertEq(liquidity, 0, "Liquidity added to Uniswap V3 pool before market activation");
        }
    }
}
