// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "./BaseTest.sol";
import {UniswapV3LiquidityCalculator} from "../src/uniswap/UniswapV3LiquidityCalculator.sol";
import {IERC20} from "@openzeppelin/contracts/interfaces/IERC20.sol";
import {IERC165} from "@openzeppelin/contracts/utils/introspection/IERC165.sol";
import {IMinter1155} from "../src/interfaces/IMinter1155.sol";

contract ZoraTimedSaleStrategyTest is BaseTest {
    function setUp() public override {
        super.setUp();
    }

    event SaleSet(
        address indexed collection,
        uint256 indexed tokenId,
        IZoraTimedSaleStrategy.SalesConfig salesConfig,
        address erc20zAddress,
        address poolAddress
    );

    event ZoraTimedSaleStrategyRewards(
        address indexed collection,
        uint256 indexed tokenId,
        address creator,
        uint256 creatorReward,
        address createReferral,
        uint256 createReferralReward,
        address mintReferral,
        uint256 mintReferralReward,
        address market,
        uint256 marketReward,
        address zoraRecipient,
        uint256 zoraReward
    );

    event RewardsDeposit(
        address indexed creator,
        address indexed createReferral,
        address indexed mintReferral,
        address firstMinter,
        address zora,
        address from,
        uint256 creatorReward,
        uint256 createReferralReward,
        uint256 mintReferralReward,
        uint256 firstMinterReward,
        uint256 zoraReward
    );

    event ZoraRewardRecipientUpdated(address indexed prevRecipient, address indexed newRecipient);

    event MintComment(address indexed sender, address indexed collection, uint256 indexed tokenId, uint256 quantity, string comment);

    function setUpSale(uint64 saleStart, uint64 saleEnd) public {
        IZoraTimedSaleStrategy.SalesConfig memory salesConfig = IZoraTimedSaleStrategy.SalesConfig({
            saleStart: saleStart,
            saleEnd: saleEnd,
            name: "Test",
            symbol: "TST"
        });
        vm.prank(users.creator);
        collection.callSale(tokenId, saleStrategy, abi.encodeWithSelector(saleStrategy.setSale.selector, tokenId, salesConfig));

        vm.label(saleStrategy.sale(address(collection), tokenId).erc20zAddress, "ERC20Z");
        vm.label(saleStrategy.sale(address(collection), tokenId).poolAddress, "V3_POOL");
    }

    function testZoraTimedContractName() public view {
        assertEq(saleStrategy.contractName(), "Zora Timed Sale Strategy");
    }

    function testZoraTimedContractUri() public view {
        assertEq(saleStrategy.contractURI(), "https://github.com/ourzora/zora-protocol/");
    }

    function testZoraTimedContractVersion() public view {
        assertEq(saleStrategy.contractVersion(), "1.1.0");
    }

    function testZoraTimedRequestMintReverts() public {
        vm.expectRevert(abi.encodeWithSignature("RequestMintInvalidUseMint()"));
        saleStrategy.requestMint(makeAddr("test"), 0, 0, 0, "");
    }

    function testSupportsInterface() public view {
        assertTrue(saleStrategy.supportsInterface(type(IMinter1155).interfaceId));
        assertTrue(saleStrategy.supportsInterface(0x6890e5b3));
        assertTrue(saleStrategy.supportsInterface(type(IERC165).interfaceId));
        assertFalse(saleStrategy.supportsInterface(0x0));
    }

    function testZoraTimedSetSale() public {
        IZoraTimedSaleStrategy.SalesConfig memory salesConfig = IZoraTimedSaleStrategy.SalesConfig({
            saleStart: uint64(block.timestamp) + 0,
            saleEnd: uint64(block.timestamp) + 24 hours,
            name: "Test",
            symbol: "TST"
        });

        vm.prank(users.creator);
        collection.callSale(tokenId, saleStrategy, abi.encodeWithSelector(saleStrategy.setSale.selector, tokenId, salesConfig));

        IZoraTimedSaleStrategy.SaleStorage memory storedSale = saleStrategy.sale(address(collection), tokenId);

        assertEq(storedSale.saleStart, salesConfig.saleStart);
        assertEq(storedSale.saleEnd, salesConfig.saleEnd);
        assertTrue(storedSale.erc20zAddress != address(0));
        assertTrue(storedSale.poolAddress != address(0));
    }

    function testZoraTimedMintWrongValueSent() public {
        setUpSale(uint64(block.timestamp), uint64(block.timestamp + 24 hours));

        vm.deal(users.collector, 1 ether);

        vm.expectRevert(abi.encodeWithSignature("WrongValueSent()"));
        vm.prank(users.collector);
        saleStrategy.mint{value: 1 ether}(users.collector, 1, address(collection), tokenId, address(0), "");
    }

    function testZoraTimedMintWithMintComment() public {
        setUpSale(uint64(block.timestamp), uint64(block.timestamp + 24 hours));

        vm.deal(users.collector, 1 ether);

        vm.expectEmit(true, true, true, true);
        emit MintComment(users.collector, address(collection), tokenId, 1, "mint comment");
        saleStrategy.mint{value: mintFee}(users.collector, 1, address(collection), tokenId, address(0), "mint comment");
    }

    function testZoraTimedSaleHasNotStarted() public {
        setUpSale(uint64(block.timestamp + 8 hours), uint64(block.timestamp + 24 hours));

        vm.deal(users.collector, 1 ether);

        vm.expectRevert(abi.encodeWithSignature("SaleHasNotStarted()"));
        vm.prank(users.collector);
        saleStrategy.mint{value: mintFee}(users.collector, 1, address(collection), tokenId, address(0), "");
    }

    function testZoraTimedSaleHasEnded() public {
        setUpSale(uint64(block.timestamp), uint64(block.timestamp + 24 hours));

        vm.deal(users.collector, 1 ether);

        skip(24 hours + 1);

        vm.expectRevert(abi.encodeWithSignature("SaleEnded()"));
        vm.prank(users.collector);
        saleStrategy.mint{value: mintFee}(users.collector, 1, address(collection), tokenId, address(0), "");
    }

    function testZoraTimedSetSaleValidation() public {
        // Test setSale with invalid end time
        bytes memory errorMessage = abi.encodeWithSelector(IZoraTimedSaleStrategy.EndTimeCannotBeInThePast.selector);
        bytes memory topError = abi.encodeWithSignature("CallFailed(bytes)", errorMessage);
        vm.expectRevert(topError);
        setUpSale(uint64(block.timestamp - 120), uint64(block.timestamp - 100));

        // Test setSale with invalid start time
        errorMessage = abi.encodeWithSelector(IZoraTimedSaleStrategy.StartTimeCannotBeAfterEndTime.selector);
        topError = abi.encodeWithSignature("CallFailed(bytes)", errorMessage);
        vm.expectRevert(topError);
        setUpSale(uint64(block.timestamp + 4), uint64(block.timestamp + 2));

        // Test setSale with invalid start time in the past
        errorMessage = abi.encodeWithSelector(IZoraTimedSaleStrategy.StartTimeCannotBeAfterEndTime.selector);
        topError = abi.encodeWithSignature("CallFailed(bytes)", errorMessage);
        vm.expectRevert(topError);
        setUpSale(uint64(block.timestamp + 1 days), uint64(block.timestamp + 60));
    }

    function testZoraSetSaleAlreadySet() public {
        setUpSale(uint64(block.timestamp), uint64(block.timestamp + 24 hours));

        // Test when sale has already been set
        bytes memory errorMessage = abi.encodeWithSignature("SaleAlreadySet()");
        bytes memory topError = abi.encodeWithSignature("CallFailed(bytes)", errorMessage);
        vm.expectRevert(topError);
        setUpSale(uint64(block.timestamp), uint64(block.timestamp + 24 hours));
    }

    function testZoraTimedSetSaleUpdatingTimeWhileSaleInProgress() public {
        setUpSale(uint64(block.timestamp), uint64(block.timestamp + 24 hours));
        IZoraTimedSaleStrategy.SaleStorage memory sale = saleStrategy.sale(address(collection), tokenId);
        assertEq(sale.saleStart, uint64(block.timestamp));
        assertEq(sale.saleEnd, uint64(block.timestamp + 24 hours));

        bytes memory errorMessage = abi.encodeWithSignature("EndTimeCannotBeInThePast()");
        bytes memory topError = abi.encodeWithSignature("CallFailed(bytes)", errorMessage);

        vm.prank(users.creator);
        vm.expectRevert(topError);
        collection.callSale(
            tokenId,
            saleStrategy,
            abi.encodeWithSelector(saleStrategy.updateSale.selector, tokenId, uint64(block.timestamp), uint64(block.timestamp - 2 days))
        );

        vm.prank(users.creator);
        collection.callSale(
            tokenId,
            saleStrategy,
            abi.encodeWithSelector(saleStrategy.updateSale.selector, tokenId, uint64(block.timestamp), uint64(block.timestamp + 2 hours))
        );

        sale = saleStrategy.sale(address(collection), tokenId);
        assertEq(sale.saleStart, uint64(block.timestamp));
        assertEq(sale.saleEnd, uint64(block.timestamp + 2 hours));
    }

    function testZoraTimedUpdateSaleEnded() public {
        setUpSale(uint64(block.timestamp), uint64(block.timestamp + 1 hours));
        IZoraTimedSaleStrategy.SaleStorage memory sale = saleStrategy.sale(address(collection), tokenId);
        assertEq(sale.saleStart, uint64(block.timestamp));
        assertEq(sale.saleEnd, uint64(block.timestamp + 1 hours));

        vm.warp(block.timestamp + 2 hours);

        bytes memory errorMessage = abi.encodeWithSignature("SaleEnded()");
        bytes memory topError = abi.encodeWithSignature("CallFailed(bytes)", errorMessage);

        vm.expectRevert(topError);

        vm.prank(users.creator);
        collection.callSale(
            tokenId,
            saleStrategy,
            abi.encodeWithSelector(saleStrategy.updateSale.selector, tokenId, uint64(block.timestamp), uint64(block.timestamp + 1 hours))
        );
    }

    function testZoraTimedUpdateSaleNotStarted() public {
        setUpSale(uint64(block.timestamp + 1 days), uint64(block.timestamp + 2 days));
        IZoraTimedSaleStrategy.SaleStorage memory sale = saleStrategy.sale(address(collection), tokenId);
        assertEq(sale.saleStart, uint64(block.timestamp + 1 days));
        assertEq(sale.saleEnd, uint64(block.timestamp + 2 days));

        bytes memory errorMessage = abi.encodeWithSignature("StartTimeCannotBeAfterEndTime()");
        bytes memory topError = abi.encodeWithSignature("CallFailed(bytes)", errorMessage);

        vm.prank(users.creator);
        vm.expectRevert(topError);
        collection.callSale(
            tokenId,
            saleStrategy,
            abi.encodeWithSelector(saleStrategy.updateSale.selector, tokenId, uint64(block.timestamp + 3 days), uint64(block.timestamp + 1 hours))
        );

        vm.prank(users.creator);
        collection.callSale(
            tokenId,
            saleStrategy,
            abi.encodeWithSelector(saleStrategy.updateSale.selector, tokenId, uint64(block.timestamp + 2 days), uint64(block.timestamp + 3 days))
        );

        sale = saleStrategy.sale(address(collection), tokenId);
        assertEq(sale.saleStart, uint64(block.timestamp + 2 days));
        assertEq(sale.saleEnd, uint64(block.timestamp + 3 days));
    }

    function testUpdateSaleWhenSaleNotSet() public {
        bytes memory errorMessage = abi.encodeWithSignature("SaleNotSet()");
        bytes memory topError = abi.encodeWithSignature("CallFailed(bytes)", errorMessage);

        vm.expectRevert(topError);
        collection.callSale(
            tokenId,
            saleStrategy,
            abi.encodeWithSelector(saleStrategy.updateSale.selector, tokenId, uint64(block.timestamp), uint64(block.timestamp + 1 hours))
        );
    }

    function testZoraTimedMintWhenSaleNotSet() public {
        vm.expectRevert(abi.encodeWithSignature("SaleNotSet()"));
        saleStrategy.mint{value: mintFee}(users.collector, 1, address(collection), tokenId, address(0), "");
    }

    function testZoraTimedMintFlow() public {
        setUpSale(uint64(block.timestamp), uint64(block.timestamp + 24 hours));

        vm.deal(users.collector, 1 ether);

        IZoraTimedSaleStrategy.RewardsSettings memory rewards = saleStrategy.computeRewards(1);
        address erc20z = saleStrategy.sale(address(collection), tokenId).erc20zAddress;

        vm.expectEmit(true, true, true, true);
        emit RewardsDeposit(
            users.creator,
            users.createReferral,
            users.mintReferral,
            address(0),
            users.zoraRewardRecipient,
            address(saleStrategy),
            rewards.creatorReward,
            rewards.createReferralReward,
            rewards.mintReferralReward,
            0,
            rewards.zoraReward
        );

        vm.expectEmit(true, true, true, true);
        emit ZoraTimedSaleStrategyRewards(
            address(collection),
            tokenId,
            users.creator,
            rewards.creatorReward,
            users.createReferral,
            rewards.createReferralReward,
            users.mintReferral,
            rewards.mintReferralReward,
            erc20z,
            rewards.marketReward,
            users.zoraRewardRecipient,
            rewards.zoraReward
        );
        vm.prank(users.collector);
        saleStrategy.mint{value: mintFee}(users.collector, 1, address(collection), tokenId, users.mintReferral, "");
    }

    uint256 constant ONE_ERC20 = 1e18;

    function testFuzzCalculateErc20ActivateRatioAlwaysCorrect(uint16 tokensMintedShort, uint16 tokensMintedInOtherMinterShort) public {
        // this test tests: minting using the timed sale minter, and minting outside of the minter.
        // It verifies that the liquidity ratio is always correct, regardless of the number of tokens minted
        uint256 tokensMinted = tokensMintedShort;
        uint256 tokensMintedInOtherMinter = tokensMintedInOtherMinterShort;

        vm.assume(tokensMinted > 0);

        uint64 saleStart = uint64(block.timestamp);
        uint64 saleEnd = uint64(block.timestamp + 4);
        setUpSale(saleStart, saleEnd);

        vm.deal(users.collector, type(uint256).max);

        vm.prank(users.collector);

        // mint the tokens using the timed sale strategy
        saleStrategy.mint{value: mintFee * tokensMinted}(users.collector, tokensMinted, address(collection), tokenId, users.mintReferral, "");

        // now mint some tokens not using the minter
        vm.prank(users.creator);
        collection.adminMint(users.creator, tokensMintedInOtherMinter, tokenId, "");

        // we are testing for these expected liquidity ratios: it should be 0.0000111 eth per 1 erc20
        address tokenAddress = saleStrategy.sale(address(collection), tokenId).erc20zAddress;

        IZoraTimedSaleStrategy.ERC20zActivate memory activationCalculation = saleStrategy.calculateERC20zActivate(address(collection), tokenId, tokenAddress);

        // make sure that the eth deposited into the erc20 z matches the market reward
        assertEq(tokenAddress.balance, tokensMinted * 0.0000111 ether, "eth liquidity");

        // there should be 0.000111 eth for each uint of erc20
        // so ratio looks like:
        // 0.000111 eth / 1 erc20.  so if there is x balance in pool, there should be erc20: x / 0.000111
        assertEq(activationCalculation.erc20Liquidity, (tokenAddress.balance * ONE_ERC20) / 0.000111 ether, "erc20 liquidity");
        // make sure total 1155 supply and erc20 supply match
        assertEq(activationCalculation.finalTotalERC20ZSupply, activationCalculation.final1155Supply * ONE_ERC20, "total supply match");
        // make sure that erc20 liquidity to deposit is one per each 0.0000111 eth
    }

    // fuzz test with uint16 range to limit the number of possible values
    function testFuzzLaunchMarketLiquidityRatioAlwaysCorrect(uint16 tokensMintedShort, uint16 tokensMintedInOtherMinterShort) public {
        // this test tests: minting using the timed sale minter, and minting outside of the minter.
        // It verifies that the liquidity ratio is always correct, regardless of the number of tokens minted
        uint256 tokensMinted = tokensMintedShort;
        uint256 tokensMintedInOtherMinter = tokensMintedInOtherMinterShort;

        vm.assume(tokensMinted > 0);

        uint64 saleStart = uint64(block.timestamp);
        uint64 saleEnd = uint64(block.timestamp + 4);
        setUpSale(saleStart, saleEnd);

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
        vm.expectCall(address(nonfungiblePositionManager), 0, abi.encodeCall(nonfungiblePositionManager.mint, expectedMintParams));
        saleStrategy.launchMarket(address(collection), tokenId);

        // assert that total supply of erc20 and 1155 matches
        assertEq(IERC20(payable(tokenAddress)).totalSupply(), collection.getTokenInfo(tokenId).maxSupply * ONE_ERC20, "total supply");
    }

    // fuzz test with uint16 range to limit the number of possible values
    function testMarketDoesNotLaunchWithZeroLiquidity() public {
        uint64 saleStart = uint64(block.timestamp);
        uint64 saleEnd = uint64(block.timestamp + 4);
        setUpSale(saleStart, saleEnd);

        vm.deal(users.collector, type(uint256).max);

        // now mint some tokens not using the minter
        vm.prank(users.creator);
        collection.adminMint(users.creator, 10, tokenId, "");

        // end the sale
        vm.warp(saleEnd);

        vm.expectRevert(IZoraTimedSaleStrategy.NeedsToBeAtLeastOneSaleToStartMarket.selector);
        saleStrategy.launchMarket(address(collection), tokenId);
    }

    // TODO: Refactor because this test is causing stack too deep
    // function testZoraTimedMintFlowFuzz(uint256 quantity) public {
    //     vm.assume(quantity > 0 && quantity < 100_000_000);

    //     setUpSale(uint64(block.timestamp), type(uint64).max);

    //     uint256 totalCost = quantity * mintFee;
    //     vm.deal(users.collector, totalCost);

    //     IZoraTimedSaleStrategy.RewardsSettings memory rewards = saleStrategy.computeRewards(quantity);
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
    //     saleStrategy.mint{value: totalCost}(users.collector, quantity, address(collection), tokenId, users.mintReferral, "");
    // }

    function testZoraTimedSetRewardRecipient() public {
        address newRecipient = makeAddr("newRecipient");

        vm.expectEmit(true, true, true, true);
        emit ZoraRewardRecipientUpdated(users.zoraRewardRecipient, newRecipient);
        vm.prank(users.owner);
        saleStrategy.setZoraRewardRecipient(newRecipient);
    }

    function testZoraTimedSetRewardRecipientRevert() public {
        address newRecipient = makeAddr("newRecipient");

        vm.expectRevert(abi.encodeWithSignature("OwnableUnauthorizedAccount(address)", newRecipient));
        vm.prank(newRecipient);
        saleStrategy.setZoraRewardRecipient(newRecipient);
    }

    function testZoraTimedSetRewardRecipientRevertZeroAddress() public {
        vm.expectRevert(abi.encodeWithSignature("AddressZero()"));
        vm.prank(users.owner);
        saleStrategy.setZoraRewardRecipient(address(0));
    }

    function testZoraTimedWhenReduceSupplyDoesNotExist() public {
        Zora1155NoReduceSupply collectionNoReduceSupply = new Zora1155NoReduceSupply(users.creator);
        vm.startPrank(users.creator);
        uint256 token = collectionNoReduceSupply.setupNewTokenWithCreateReferral("token.uri", type(uint256).max, users.createReferral);
        collectionNoReduceSupply.addPermission(token, address(saleStrategy), collectionNoReduceSupply.PERMISSION_BIT_MINTER());

        IZoraTimedSaleStrategy.SalesConfig memory salesConfig = IZoraTimedSaleStrategy.SalesConfig({
            saleStart: 0,
            saleEnd: type(uint64).max,
            name: "Test",
            symbol: "TST"
        });

        bytes memory errorMessage = abi.encodeWithSignature("ZoraCreator1155ContractNeedsToSupportReduceSupply()");
        bytes memory topError = abi.encodeWithSignature("CallFailed(bytes)", errorMessage);

        vm.expectRevert(topError);
        collectionNoReduceSupply.callSale(token, saleStrategy, abi.encodeWithSelector(saleStrategy.setSale.selector, token, salesConfig));
        vm.stopPrank();
    }

    function testLaunchMarket() public {
        uint64 saleStart = uint64(block.timestamp);
        uint64 saleEnd = uint64(block.timestamp + 24 hours);
        uint256 numTokens = 11;

        setUpSale(saleStart, saleEnd);

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
        setUpSale(uint64(block.timestamp), uint64(block.timestamp + 24 hours));

        vm.expectRevert(abi.encodeWithSignature("SaleInProgress()"));
        saleStrategy.launchMarket(address(collection), tokenId);
    }

    function testLaunchMarketAlreadyActivated() public {
        // First Launch Market
        uint64 saleStart = uint64(block.timestamp);
        uint64 saleEnd = uint64(block.timestamp + 24 hours);
        uint256 numTokens = 11;

        setUpSale(saleStart, saleEnd);
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
}
