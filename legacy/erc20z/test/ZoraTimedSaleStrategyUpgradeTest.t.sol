// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "./BaseTest.sol";
import {IERC20Z} from "../src/interfaces/IERC20Z.sol";
import {IZora1155} from "../src/interfaces/IZora1155.sol";
import {IRoyalties} from "../src/interfaces/IRoyalties.sol";
import {Clones} from "@openzeppelin/contracts/proxy/Clones.sol";
import {MockMintableERC721} from "./mock/MockMintableERC721.sol";
import {MockMintableERC1155} from "./mock/MockMintableERC1155.sol";
import {IERC1155} from "@openzeppelin/contracts/token/ERC1155/IERC1155.sol";
import {ERC20Z} from "../src/ERC20Z.sol";
import {IERC20} from "@openzeppelin/contracts/interfaces/IERC20.sol";
import {IZoraTimedSaleStrategyV1} from "./legacy/IZoraTimedSaleStrategyV1.sol";
import {UniswapV3LiquidityCalculator} from "../src/uniswap/UniswapV3LiquidityCalculator.sol";
import {IZoraTimedSaleStrategy} from "../src/interfaces/IZoraTimedSaleStrategy.sol";

// these tests simulate: using the existing strategy deployed on zora mainnet,
// setting up a sale, upgrading the strategy to the latest version, and then testing
// minting/launching a market
contract ZoraTimedSaleStrategyUpgradeTest is BaseTest {
    using stdJson for string;

    function setUpSale(uint64 saleStart, uint64 saleEnd) public {
        IZoraTimedSaleStrategyV1.SalesConfig memory salesConfig = IZoraTimedSaleStrategyV1.SalesConfig({
            saleStart: saleStart,
            saleEnd: saleEnd,
            name: "Test",
            symbol: "TST"
        });
        vm.prank(users.creator);
        collection.callSale(
            tokenId,
            saleStrategy,
            abi.encodeWithSelector(IZoraTimedSaleStrategyV1(address(saleStrategy)).setSale.selector, tokenId, salesConfig)
        );

        vm.label(saleStrategy.sale(address(collection), tokenId).erc20zAddress, "ERC20Z");
        vm.label(saleStrategy.sale(address(collection), tokenId).poolAddress, "V3_POOL");
    }

    function setUpSaleV2(uint64 saleStart) public {
        IZoraTimedSaleStrategy.SalesConfigV2 memory salesConfig = IZoraTimedSaleStrategy.SalesConfigV2({
            saleStart: saleStart,
            marketCountdown: 24 hours,
            minimumMarketEth: 0.0222 ether,
            name: "Test",
            symbol: "TST"
        });

        vm.prank(users.creator);
        collection.callSale(
            tokenId,
            saleStrategy,
            abi.encodeWithSelector(IZoraTimedSaleStrategy(address(saleStrategy)).setSaleV2.selector, tokenId, salesConfig)
        );

        vm.label(saleStrategy.saleV2(address(collection), tokenId).erc20zAddress, "ERC20Z");
        vm.label(saleStrategy.saleV2(address(collection), tokenId).poolAddress, "V3_POOL");
    }

    function setTimedSaleStrategyToCurrentlyDeployed() private {
        vm.rollFork(18704119);
        // change the sale strategy to use the fork deployment
        saleStrategy = ZoraTimedSaleStrategyImpl(0x777777722D078c97c6ad07d9f36801e653E356Ae);
        assertEq(saleStrategy.contractVersion(), "1.1.0");

        vm.startPrank(users.creator);

        collection = new Zora1155(users.creator, address(saleStrategy));
        tokenId = collection.setupNewTokenWithCreateReferral("token.uri", type(uint256).max, users.createReferral);
        collection.addPermission(tokenId, address(saleStrategy), collection.PERMISSION_BIT_MINTER());

        vm.stopPrank();
    }

    function upgradeToCurrentVersion() private {
        vm.startPrank(saleStrategy.owner());
        saleStrategy.upgradeToAndCall(address(new ZoraTimedSaleStrategyImpl()), "");
        vm.stopPrank();

        string memory package = vm.readFile("./package.json");
        assertEq(saleStrategy.contractVersion(), package.readString(".version"));
    }

    function testZoraTimedSetSale() public {
        setTimedSaleStrategyToCurrentlyDeployed();
        IZoraTimedSaleStrategy.SalesConfig memory salesConfig = IZoraTimedSaleStrategy.SalesConfig({
            saleStart: uint64(block.timestamp) + 0,
            saleEnd: uint64(block.timestamp) + 24 hours,
            name: "Test",
            symbol: "TST"
        });

        vm.prank(users.creator);
        collection.callSale(
            tokenId,
            saleStrategy,
            abi.encodeWithSelector(IZoraTimedSaleStrategyV1(address(saleStrategy)).setSale.selector, tokenId, salesConfig)
        );

        upgradeToCurrentVersion();

        IZoraTimedSaleStrategy.SaleStorage memory storedSale = saleStrategy.sale(address(collection), tokenId);

        assertEq(storedSale.saleStart, salesConfig.saleStart);
        assertEq(storedSale.saleEnd, salesConfig.saleEnd);
        assertTrue(storedSale.erc20zAddress != address(0));
        assertTrue(storedSale.poolAddress != address(0));
    }

    function testZoraTimedMintWrongValueSent() public {
        setTimedSaleStrategyToCurrentlyDeployed();
        setUpSale(uint64(block.timestamp), uint64(block.timestamp + 24 hours));

        upgradeToCurrentVersion();

        vm.deal(users.collector, 1 ether);

        vm.expectRevert(abi.encodeWithSignature("WrongValueSent()"));
        vm.prank(users.collector);
        saleStrategy.mint{value: 1 ether}(users.collector, 1, address(collection), tokenId, address(0), "");
    }

    function testZoraTimedSaleHasNotStarted() public {
        setTimedSaleStrategyToCurrentlyDeployed();
        setUpSale(uint64(block.timestamp + 8 hours), uint64(block.timestamp + 24 hours));

        upgradeToCurrentVersion();

        vm.deal(users.collector, 1 ether);

        vm.expectRevert(abi.encodeWithSignature("SaleHasNotStarted()"));
        vm.prank(users.collector);
        saleStrategy.mint{value: mintFee}(users.collector, 1, address(collection), tokenId, address(0), "");
    }

    function testZoraTimedSaleHasEnded() public {
        setTimedSaleStrategyToCurrentlyDeployed();
        setUpSale(uint64(block.timestamp), uint64(block.timestamp + 24 hours));

        upgradeToCurrentVersion();

        vm.deal(users.collector, 1 ether);

        skip(24 hours + 1);

        vm.expectRevert(abi.encodeWithSignature("SaleEnded()"));
        vm.prank(users.collector);
        saleStrategy.mint{value: mintFee}(users.collector, 1, address(collection), tokenId, address(0), "");
    }

    // function testZoraTimedSetSaleUpdatingTimeWhileSaleInProgress() public {
    //     setUpSale(uint64(block.timestamp), uint64(block.timestamp + 24 hours));
    //     IZoraTimedSaleStrategy.SaleStorage memory sale = saleStrategy.sale(address(collection), tokenId);
    //     assertEq(sale.saleStart, uint64(block.timestamp));
    //     assertEq(sale.saleEnd, uint64(block.timestamp + 24 hours));

    //     bytes memory errorMessage = abi.encodeWithSignature("EndTimeCannotBeInThePast()");
    //     bytes memory topError = abi.encodeWithSignature("CallFailed(bytes)", errorMessage);

    //     vm.prank(users.creator);
    //     vm.expectRevert(topError);
    //     collection.callSale(
    //         tokenId,
    //         saleStrategy,
    //         abi.encodeWithSelector(saleStrategy.updateSale.selector, tokenId, uint64(block.timestamp), uint64(block.timestamp - 2 days))
    //     );

    //     vm.prank(users.creator);
    //     collection.callSale(
    //         tokenId,
    //         saleStrategy,
    //         abi.encodeWithSelector(saleStrategy.updateSale.selector, tokenId, uint64(block.timestamp), uint64(block.timestamp + 2 hours))
    //     );

    //     sale = saleStrategy.sale(address(collection), tokenId);
    //     assertEq(sale.saleStart, uint64(block.timestamp));
    //     assertEq(sale.saleEnd, uint64(block.timestamp + 2 hours));
    // }

    // function testZoraTimedUpdateSaleEnded() public {
    //     setUpSale(uint64(block.timestamp), uint64(block.timestamp + 1 hours));
    //     IZoraTimedSaleStrategy.SaleStorage memory sale = saleStrategy.sale(address(collection), tokenId);
    //     assertEq(sale.saleStart, uint64(block.timestamp));
    //     assertEq(sale.saleEnd, uint64(block.timestamp + 1 hours));

    //     vm.warp(block.timestamp + 2 hours);

    //     bytes memory errorMessage = abi.encodeWithSignature("SaleEnded()");
    //     bytes memory topError = abi.encodeWithSignature("CallFailed(bytes)", errorMessage);

    //     vm.expectRevert(topError);

    //     vm.prank(users.creator);
    //     collection.callSale(
    //         tokenId,
    //         saleStrategy,
    //         abi.encodeWithSelector(saleStrategy.updateSale.selector, tokenId, uint64(block.timestamp), uint64(block.timestamp + 1 hours))
    //     );
    // }

    // function testZoraTimedUpdateSaleNotStarted() public {
    //     setUpSale(uint64(block.timestamp + 1 days), uint64(block.timestamp + 2 days));
    //     IZoraTimedSaleStrategy.SaleStorage memory sale = saleStrategy.sale(address(collection), tokenId);
    //     assertEq(sale.saleStart, uint64(block.timestamp + 1 days));
    //     assertEq(sale.saleEnd, uint64(block.timestamp + 2 days));

    //     bytes memory errorMessage = abi.encodeWithSignature("StartTimeCannotBeAfterEndTime()");
    //     bytes memory topError = abi.encodeWithSignature("CallFailed(bytes)", errorMessage);

    //     vm.prank(users.creator);
    //     vm.expectRevert(topError);
    //     collection.callSale(
    //         tokenId,
    //         saleStrategy,
    //         abi.encodeWithSelector(saleStrategy.updateSale.selector, tokenId, uint64(block.timestamp + 3 days), uint64(block.timestamp + 1 hours))
    //     );

    //     vm.prank(users.creator);
    //     collection.callSale(
    //         tokenId,
    //         saleStrategy,
    //         abi.encodeWithSelector(saleStrategy.updateSale.selector, tokenId, uint64(block.timestamp + 2 days), uint64(block.timestamp + 3 days))
    //     );

    //     sale = saleStrategy.sale(address(collection), tokenId);
    //     assertEq(sale.saleStart, uint64(block.timestamp + 2 days));
    //     assertEq(sale.saleEnd, uint64(block.timestamp + 3 days));
    // }

    // function testUpdateSaleWhenSaleNotSet() public {
    //     bytes memory errorMessage = abi.encodeWithSignature("SaleNotSet()");
    //     bytes memory topError = abi.encodeWithSignature("CallFailed(bytes)", errorMessage);

    //     vm.expectRevert(topError);
    //     collection.callSale(
    //         tokenId,
    //         saleStrategy,
    //         abi.encodeWithSelector(saleStrategy.updateSale.selector, tokenId, uint64(block.timestamp), uint64(block.timestamp + 1 hours))
    //     );
    // }

    // function testZoraTimedMintWhenSaleNotSet() public {
    //     vm.expectRevert(abi.encodeWithSignature("SaleNotSet()"));
    //     saleStrategy.mint{value: mintFee}(users.collector, 1, address(collection), tokenId, address(0), "");
    // }

    // function testZoraTimedMintFlow() public {
    //     setTimedSaleStrategyToCurrentlyDeployed();
    //     setUpSale(uint64(block.timestamp), uint64(block.timestamp + 24 hours));
    //     upgradeToCurrentVersion();

    //     vm.deal(users.collector, 1 ether);

    //     IZoraTimedSaleStrategy.RewardsSettings memory rewards = saleStrategy.computeRewards(1);
    //     address erc20z = saleStrategy.sale(address(collection), tokenId).erc20zAddress;

    //     vm.expectEmit(true, true, true, true);
    //     emit RewardsDeposit(
    //         users.creator,
    //         users.createReferral,
    //         users.mintReferral,
    //         address(0),
    //         users.zoraRewardRecipient,
    //         address(saleStrategy),
    //         rewards.creatorReward,
    //         rewards.createReferralReward,
    //         rewards.mintReferralReward,
    //         0,
    //         rewards.zoraReward
    //     );

    //     vm.expectEmit(true, true, true, true);
    //     emit ZoraTimedSaleStrategyRewards(
    //         address(collection),
    //         tokenId,
    //         users.creator,
    //         rewards.creatorReward,
    //         users.createReferral,
    //         rewards.createReferralReward,
    //         users.mintReferral,
    //         rewards.mintReferralReward,
    //         erc20z,
    //         rewards.marketReward,
    //         users.zoraRewardRecipient,
    //         rewards.zoraReward
    //     );
    //     vm.prank(users.collector);
    //     saleStrategy.mint{value: mintFee}(users.collector, 1, address(collection), tokenId, users.mintReferral, "");
    // }

    // uint256 constant ONE_ERC20 = 1e18;

    // fuzz test with uint16 range to limit the number of possible values
    function testFuzzLaunchMarketLiquidityRatioAlwaysCorrect(uint16 tokensMintedShort, uint16 tokensMintedInOtherMinterShort) public {
        // this test tests: minting using the timed sale minter, and minting outside of the minter.
        // It verifies that the liquidity ratio is always correct, regardless of the number of tokens minted
        uint256 tokensMinted = tokensMintedShort;
        uint256 tokensMintedInOtherMinter = tokensMintedInOtherMinterShort;

        vm.assume(tokensMinted > 0);

        setTimedSaleStrategyToCurrentlyDeployed();

        uint64 saleStart = uint64(block.timestamp);
        uint64 saleEnd = uint64(block.timestamp + 4);

        setUpSale(saleStart, saleEnd);

        upgradeToCurrentVersion();

        vm.deal(users.collector, type(uint256).max);

        vm.prank(users.collector);

        // mint the tokens using the timed sale strategy
        saleStrategy.mint{value: mintFee * tokensMinted}(users.collector, tokensMinted, address(collection), tokenId, users.mintReferral, "");

        // now mint some tokens not using the minter
        vm.prank(users.creator);
        collection.adminMint(users.creator, tokensMintedInOtherMinter, tokenId, "");

        // we are testing for these expected liquidity ratios: it should be 0.0000111 eth per 1 erc20
        uint256 expectedEthLiquidity = 0.0000111 ether * tokensMinted;
        // should have one erc20 per 0.000111 eth
        uint256 expectedErc20Liquidity = (expectedEthLiquidity * ONE_ERC20) / 0.000111 ether;

        address tokenAddress = saleStrategy.sale(address(collection), tokenId).erc20zAddress;

        // end the sale
        vm.warp(saleEnd);

        // get expected liquidity call to uniswap
        (address token0, address token1, uint256 amount0, uint256 amount1 /*uint128 liquidity*/, ) = UniswapV3LiquidityCalculator.calculateLiquidityAmounts(
            WETH_ADDRESS,
            expectedEthLiquidity,
            tokenAddress,
            expectedErc20Liquidity
        );

        INonfungiblePositionManager.MintParams memory expectedMintParams = INonfungiblePositionManager.MintParams({
            token0: token0,
            token1: token1,
            fee: 10000,
            tickLower: UniswapV3LiquidityCalculator.TICK_LOWER,
            tickUpper: UniswapV3LiquidityCalculator.TICK_UPPER,
            amount0Desired: amount0,
            amount1Desired: amount1,
            amount0Min: 0,
            amount1Min: 0,
            recipient: tokenAddress,
            deadline: block.timestamp
        });

        // launch market, it should be setup with the expected mint params
        vm.prank(address(saleStrategy));
        vm.expectCall(address(nonfungiblePositionManager), 0, abi.encodeCall(nonfungiblePositionManager.mint, expectedMintParams));
        saleStrategy.launchMarket(address(collection), tokenId);

        // assert that total supply of erc20 and 1155 matches
        assertEq(IERC20(payable(tokenAddress)).totalSupply(), collection.getTokenInfo(tokenId).maxSupply * ONE_ERC20, "total supply");
    }

    // fuzz test with uint16 range to limit the number of possible values
    function testMarketDoesNotLaunchWithZeroLiquidity() public {
        setTimedSaleStrategyToCurrentlyDeployed();
        uint64 saleStart = uint64(block.timestamp);
        uint64 saleEnd = uint64(block.timestamp + 4);
        setUpSale(saleStart, saleEnd);

        upgradeToCurrentVersion();

        vm.deal(users.collector, type(uint256).max);

        // now mint some tokens not using the minter
        vm.prank(users.creator);
        collection.adminMint(users.creator, 10, tokenId, "");

        // end the sale
        vm.warp(saleEnd);

        vm.expectRevert(IZoraTimedSaleStrategy.NeedsToBeAtLeastOneSaleToStartMarket.selector);
        saleStrategy.launchMarket(address(collection), tokenId);
    }

    function testLaunchMarket() public {
        setTimedSaleStrategyToCurrentlyDeployed();
        uint64 saleStart = uint64(block.timestamp);
        uint64 saleEnd = uint64(block.timestamp + 24 hours);
        uint256 numTokens = 11;

        setUpSale(saleStart, saleEnd);

        upgradeToCurrentVersion();

        uint256 totalValue = mintFee * numTokens;

        vm.deal(users.collector, totalValue);

        vm.prank(users.collector);
        saleStrategy.mint{value: totalValue}(users.collector, numTokens, address(collection), tokenId, users.mintReferral, "");

        vm.warp(saleEnd + 1);
        saleStrategy.launchMarket(address(collection), tokenId);

        address erc20zAddress = saleStrategy.sale(address(collection), tokenId).erc20zAddress;

        assertTrue(ERC20Z(payable(erc20zAddress)).totalSupply() >= numTokens);
        assertTrue(collection.getTokenInfo(tokenId).maxSupply >= numTokens);
        assertTrue(saleStrategy.sale(address(collection), tokenId).secondaryActivated == true);
    }

    function testLaunchMarketSaleInProgress() public {
        setTimedSaleStrategyToCurrentlyDeployed();
        setUpSale(uint64(block.timestamp), uint64(block.timestamp + 24 hours));
        upgradeToCurrentVersion();

        vm.deal(users.collector, 10 ether);
        vm.prank(users.collector);
        saleStrategy.mint{value: 0.000111 ether}(users.collector, 1, address(collection), tokenId, users.mintReferral, "");

        vm.expectRevert(abi.encodeWithSignature("SaleInProgress()"));
        saleStrategy.launchMarket(address(collection), tokenId);
    }

    function testLaunchMarketAlreadyActivated() public {
        // First Launch Market
        setTimedSaleStrategyToCurrentlyDeployed();
        uint64 saleStart = uint64(block.timestamp);
        uint64 saleEnd = uint64(block.timestamp + 24 hours);
        uint256 numTokens = 11;

        setUpSale(saleStart, saleEnd);
        upgradeToCurrentVersion();

        uint256 totalValue = mintFee * numTokens;
        vm.deal(users.collector, totalValue);
        vm.prank(users.collector);
        saleStrategy.mint{value: totalValue}(users.collector, numTokens, address(collection), tokenId, users.mintReferral, "");
        vm.warp(saleEnd + 1);
        saleStrategy.launchMarket(address(collection), tokenId);
        assertTrue(saleStrategy.sale(address(collection), tokenId).secondaryActivated == true);

        // Second Launch Market
        vm.expectRevert(abi.encodeWithSignature("MarketAlreadyLaunched()"));
        saleStrategy.launchMarket(address(collection), tokenId);
    }

    function testUpgradeToRewardsV2() public {
        vm.rollFork(23583214);
        saleStrategy = ZoraTimedSaleStrategyImpl(0x777777722D078c97c6ad07d9f36801e653E356Ae);
        assertEq(saleStrategy.contractVersion(), "2.1.1");

        vm.startPrank(users.creator);
        collection = new Zora1155(users.creator, address(saleStrategy));
        tokenId = collection.setupNewTokenWithCreateReferral("token.uri", type(uint256).max, users.createReferral);
        collection.addPermission(tokenId, address(saleStrategy), collection.PERMISSION_BIT_MINTER());
        vm.stopPrank();

        // Create legacy sale pre-upgrade
        setUpSaleV2(uint64(block.timestamp));

        vm.startPrank(saleStrategy.owner());
        saleStrategy.upgradeToAndCall(address(new ZoraTimedSaleStrategyImpl()), "");
        vm.stopPrank();

        // Mint legacy sale post-upgrade
        uint256 numTokens = 1;
        vm.deal(users.collector, 1 ether);
        vm.prank(users.collector);
        saleStrategy.mint{value: 0.000111 ether}(users.collector, numTokens, address(collection), tokenId, users.mintReferral, "");

        // Ensure maintains legacy market reward post-upgrade
        assertEq(saleStrategy.saleV2(address(collection), tokenId).erc20zAddress.balance, 0.0000111 ether);

        // Create new sale post-upgrade
        vm.startPrank(users.creator);
        tokenId = collection.setupNewTokenWithCreateReferral("token.uri", type(uint256).max, users.createReferral);
        collection.addPermission(tokenId, address(saleStrategy), collection.PERMISSION_BIT_MINTER());
        vm.stopPrank();
        setUpSaleV2(uint64(block.timestamp));

        // Mint new sale post-upgrade
        vm.prank(users.collector);
        saleStrategy.mint{value: 0.000111 ether}(users.collector, numTokens, address(collection), tokenId, users.mintReferral, "");

        // Ensure uses new market reward post-upgrade
        assertEq(saleStrategy.saleV2(address(collection), tokenId).erc20zAddress.balance, 0.0000222 ether);
    }
}
