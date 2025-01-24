// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import "./utils/BaseTest.sol";

contract CoinTest is BaseTest {
    function setUp() public override {
        super.setUp();

        _deployCoin();
    }

    function test_supply_constants() public view {
        assertEq(MAX_TOTAL_SUPPLY, POOL_LAUNCH_SUPPLY + CREATOR_LAUNCH_REWARD + PLATFORM_REFERRER_LAUNCH_REWARD + PROTOCOL_LAUNCH_REWARD);

        assertEq(MAX_TOTAL_SUPPLY, 1_000_000_000e18);
        assertEq(POOL_LAUNCH_SUPPLY, 980_000_000e18);
        assertEq(CREATOR_LAUNCH_REWARD, 10_000_000e18);
        assertEq(PLATFORM_REFERRER_LAUNCH_REWARD, 5_000_000e18);
        assertEq(PROTOCOL_LAUNCH_REWARD, 5_000_000e18);

        assertEq(coin.totalSupply(), MAX_TOTAL_SUPPLY);
        assertEq(coin.balanceOf(coin.payoutRecipient()), CREATOR_LAUNCH_REWARD);
        assertEq(coin.balanceOf(coin.platformReferrer()), PLATFORM_REFERRER_LAUNCH_REWARD);
        assertEq(coin.balanceOf(coin.protocolRewardRecipient()), PROTOCOL_LAUNCH_REWARD);
        assertApproxEqAbs(coin.balanceOf(address(pool)), POOL_LAUNCH_SUPPLY, 1e18);
    }

    function test_constructor_validation() public {
        vm.expectRevert(abi.encodeWithSelector(ICoin.AddressZero.selector));
        new Coin(address(0), address(protocolRewards), WETH_ADDRESS, NONFUNGIBLE_POSITION_MANAGER, SWAP_ROUTER);

        vm.expectRevert(abi.encodeWithSelector(ICoin.AddressZero.selector));
        new Coin(users.feeRecipient, address(0), WETH_ADDRESS, NONFUNGIBLE_POSITION_MANAGER, SWAP_ROUTER);

        vm.expectRevert(abi.encodeWithSelector(ICoin.AddressZero.selector));
        new Coin(users.feeRecipient, address(protocolRewards), address(0), NONFUNGIBLE_POSITION_MANAGER, SWAP_ROUTER);

        vm.expectRevert(abi.encodeWithSelector(ICoin.AddressZero.selector));
        new Coin(users.feeRecipient, address(protocolRewards), WETH_ADDRESS, address(0), SWAP_ROUTER);

        vm.expectRevert(abi.encodeWithSelector(ICoin.AddressZero.selector));
        new Coin(users.feeRecipient, address(protocolRewards), WETH_ADDRESS, NONFUNGIBLE_POSITION_MANAGER, address(0));

        Coin newToken = new Coin(users.feeRecipient, address(protocolRewards), WETH_ADDRESS, NONFUNGIBLE_POSITION_MANAGER, SWAP_ROUTER);
        assertEq(address(newToken.protocolRewardRecipient()), users.feeRecipient);
        assertEq(address(newToken.protocolRewards()), address(protocolRewards));
        assertEq(address(newToken.WETH()), WETH_ADDRESS);
        assertEq(address(newToken.nonfungiblePositionManager()), NONFUNGIBLE_POSITION_MANAGER);
        assertEq(address(newToken.swapRouter()), SWAP_ROUTER);
    }

    function test_initialize_validation() public {
        vm.expectRevert(abi.encodeWithSelector(ICoin.AddressZero.selector));
        coin = Coin(payable(factory.deploy(address(0), users.platformReferrer, "https://init.com", "Init Token", "INIT")));

        coin = Coin(payable(factory.deploy(users.creator, address(0), "https://init.com", "Init Token", "INIT")));

        assertEq(coin.tokenCreator(), users.creator);
        assertEq(coin.payoutRecipient(), users.creator);
        assertEq(coin.platformReferrer(), users.feeRecipient);
        assertEq(coin.tokenURI(), "https://init.com");
        assertEq(coin.name(), "Init Token");
        assertEq(coin.symbol(), "INIT");
        assertEq(uint8(coin.marketType()), uint8(ICoin.MarketType.UNISWAP_POOL));
    }

    function test_revert_already_initialized() public {
        coin = Coin(payable(factory.deploy(users.creator, users.platformReferrer, "https://init.com", "Init Token", "INIT")));

        vm.expectRevert(abi.encodeWithSignature("InvalidInitialization()"));
        coin.initialize(users.creator, new address[](0), "https://init.com", "Init Token", "INIT", users.platformReferrer, address(0), 0);
    }

    function test_erc165_interface_support() public view {
        assertEq(coin.supportsInterface(type(IERC165).interfaceId), true);
        assertEq(coin.supportsInterface(type(IERC7572).interfaceId), true);
    }

    function test_buy_with_eth() public {
        vm.deal(users.buyer, 1 ether);
        vm.prank(users.buyer);
        coin.buy{value: 1 ether}(users.coinRecipient, users.buyer, users.tradeReferrer, "", ICoin.MarketType.UNISWAP_POOL, 0, 0);

        assertGt(coin.balanceOf(users.coinRecipient), 0);
        assertEq(users.seller.balance, 0);
    }

    function test_buy_with_eth_fuzz(uint256 ethOrderSize) public {
        vm.assume(ethOrderSize >= MIN_ORDER_SIZE);
        vm.assume(ethOrderSize < 10 ether);

        uint256 platformReferrerBalanceBeforeSale = users.platformReferrer.balance;
        uint256 orderReferrerBalanceBeforeSale = users.tradeReferrer.balance;
        uint256 tokenCreatorBalanceBeforeSale = users.creator.balance;
        uint256 feeRecipientBalanceBeforeSale = users.feeRecipient.balance;

        vm.deal(users.buyer, ethOrderSize);
        vm.prank(users.buyer);
        coin.buy{value: ethOrderSize}(users.coinRecipient, users.buyer, users.tradeReferrer, "", ICoin.MarketType.UNISWAP_POOL, 0, 0);

        assertGt(coin.balanceOf(users.coinRecipient), 0, "coinRecipient coin balance");
        assertGt(protocolRewards.balanceOf(users.feeRecipient), feeRecipientBalanceBeforeSale, "feeRecipient eth balance");
        assertGt(protocolRewards.balanceOf(users.platformReferrer), platformReferrerBalanceBeforeSale, "platformReferrer eth balance");
        assertGt(protocolRewards.balanceOf(users.tradeReferrer), orderReferrerBalanceBeforeSale, "tradeReferrer eth balance");
        assertGt(protocolRewards.balanceOf(users.creator), tokenCreatorBalanceBeforeSale, "creator eth balance");
    }

    function test_buy_with_eth_too_small() public {
        vm.expectRevert(abi.encodeWithSelector(ICoin.EthAmountTooSmall.selector));
        coin.buy{value: MIN_ORDER_SIZE - 1}(users.coinRecipient, users.buyer, users.tradeReferrer, "", ICoin.MarketType.UNISWAP_POOL, 0, 0);
    }

    function test_buy_with_minimum_eth() public {
        uint256 minEth = 0.000001 ether;
        vm.deal(users.buyer, minEth);
        vm.prank(users.buyer);
        coin.buy{value: minEth}(users.coinRecipient, users.buyer, users.tradeReferrer, "", ICoin.MarketType.UNISWAP_POOL, 0, 0);

        assertGt(coin.balanceOf(users.coinRecipient), 0, "coinRecipient coin balance");
    }

    function test_revert_buy_zero_address_recipient_legacy() public {
        vm.deal(users.buyer, 1 ether);

        vm.expectRevert(abi.encodeWithSelector(ICoin.AddressZero.selector));
        vm.prank(users.buyer);
        coin.buy{value: 1 ether}(address(0), users.buyer, users.tradeReferrer, "", ICoin.MarketType.UNISWAP_POOL, 0, 0);
    }

    function test_revert_buy_zero_address_recipient() public {
        vm.deal(users.buyer, 1 ether);

        vm.expectRevert(abi.encodeWithSelector(ICoin.AddressZero.selector));
        vm.prank(users.buyer);
        coin.buy(address(0), 1 ether, 0, 0, users.tradeReferrer);
    }

    function test_buy_with_usdc() public {
        _deployCoinUSDCPair();

        deal(address(usdc), users.buyer, 100e6);

        vm.prank(users.buyer);
        usdc.approve(address(coin), 10e6);

        vm.prank(users.buyer);
        coin.buy(users.coinRecipient, 10e6, 0, 0, users.tradeReferrer);

        assertGt(coin.balanceOf(users.coinRecipient), 0, "coinRecipient coin balance");
    }

    function test_buy_with_usdc_revert_no_approval() public {
        _deployCoinUSDCPair();

        deal(address(usdc), users.buyer, 100e6);

        vm.prank(users.buyer);
        vm.expectRevert("ERC20: transfer amount exceeds allowance");
        coin.buy(users.coinRecipient, 100e6, 0, 0, users.tradeReferrer);
    }

    function test_sell_for_eth() public {
        vm.deal(users.buyer, 1 ether);
        vm.prank(users.buyer);
        coin.buy{value: 1 ether}(users.seller, users.buyer, users.tradeReferrer, "", ICoin.MarketType.UNISWAP_POOL, 0, 0);

        uint256 tokensToSell = coin.balanceOf(users.seller);
        vm.prank(users.seller);
        coin.sell(tokensToSell, users.seller, users.tradeReferrer, "", ICoin.MarketType.UNISWAP_POOL, 0, 0);

        assertEq(coin.balanceOf(users.seller), 0, "seller coin balance");
        assertGt(users.seller.balance, 0, "seller eth balance");
    }

    function test_sell_for_eth_fuzz(uint256 ethOrderSize) public {
        vm.assume(ethOrderSize < 10 ether);
        vm.assume(ethOrderSize >= MIN_ORDER_SIZE);

        vm.deal(users.buyer, ethOrderSize);
        vm.prank(users.buyer);
        coin.buy{value: ethOrderSize}(users.seller, users.buyer, users.tradeReferrer, "", ICoin.MarketType.UNISWAP_POOL, 0, 0);

        uint256 platformReferrerBalanceBeforeSale = users.platformReferrer.balance;
        uint256 orderReferrerBalanceBeforeSale = users.tradeReferrer.balance;
        uint256 tokenCreatorBalanceBeforeSale = users.creator.balance;
        uint256 feeRecipientBalanceBeforeSale = users.feeRecipient.balance;

        uint256 tokensToSell = coin.balanceOf(users.seller);
        vm.prank(users.seller);
        coin.sell(tokensToSell, users.coinRecipient, users.tradeReferrer, "", ICoin.MarketType.UNISWAP_POOL, 0, 0);

        assertEq(coin.balanceOf(users.seller), 0, "seller coin balance");
        assertEq(coin.balanceOf(users.coinRecipient), 0, "coinRecipient coin balance");

        assertEq(users.seller.balance, 0, "seller eth balance");
        assertGt(protocolRewards.balanceOf(users.feeRecipient), feeRecipientBalanceBeforeSale, "feeRecipient eth balance");
        assertGt(protocolRewards.balanceOf(users.platformReferrer), platformReferrerBalanceBeforeSale, "platformReferrer eth balance");
        assertGt(protocolRewards.balanceOf(users.tradeReferrer), orderReferrerBalanceBeforeSale, "tradeReferrer eth balance");
        assertGt(protocolRewards.balanceOf(users.creator), tokenCreatorBalanceBeforeSale, "creator eth balance");
    }

    function test_sell_for_usdc() public {
        _deployCoinUSDCPair();

        deal(address(usdc), users.buyer, 10e6);

        vm.prank(users.buyer);
        usdc.approve(address(coin), 10e6);

        vm.prank(users.buyer);
        coin.buy(users.coinRecipient, 10e6, 0, 0, users.tradeReferrer);

        uint256 coinBalance = coin.balanceOf(users.coinRecipient);

        vm.prank(users.coinRecipient);
        coin.sell(users.seller, coinBalance, 0, 0, users.tradeReferrer);
    }

    function test_revert_sell_zero_address_recipient() public {
        vm.deal(users.buyer, 1 ether);
        vm.prank(users.buyer);
        coin.buy{value: 1 ether}(users.seller, users.buyer, users.tradeReferrer, "", ICoin.MarketType.UNISWAP_POOL, 0, 0);

        uint256 tokensToSell = coin.balanceOf(users.seller);
        vm.prank(users.seller);
        vm.expectRevert(abi.encodeWithSelector(ICoin.AddressZero.selector));
        coin.sell(tokensToSell, address(0), users.tradeReferrer, "", ICoin.MarketType.UNISWAP_POOL, 0, 0);
    }

    function test_revert_sell_insufficient_liquidity() public {
        vm.deal(users.buyer, 1 ether);
        vm.prank(users.buyer);
        coin.buy{value: 1 ether}(users.seller, users.buyer, users.tradeReferrer, "", ICoin.MarketType.UNISWAP_POOL, 0, 0);

        uint256 balance = coin.balanceOf(users.seller);
        vm.prank(users.seller);
        vm.expectRevert(abi.encodeWithSignature("ERC20InsufficientBalance(address,uint256,uint256)", users.seller, balance, balance + 1));
        coin.sell(balance + 1, users.coinRecipient, users.tradeReferrer, "", ICoin.MarketType.UNISWAP_POOL, 0, 0);
    }

    function test_burn() public {
        vm.deal(users.buyer, 1 ether);
        vm.prank(users.buyer);
        coin.buy{value: 1 ether}(users.coinRecipient, users.buyer, address(0), "", ICoin.MarketType.UNISWAP_POOL, 0, 0);

        uint256 beforeBalance = coin.balanceOf(users.coinRecipient);
        uint256 beforeTotalSupply = coin.totalSupply();

        vm.prank(users.coinRecipient);
        coin.burn(1e18);

        uint256 afterBalance = coin.balanceOf(users.coinRecipient);
        uint256 afterTotalSupply = coin.totalSupply();

        assertEq(beforeBalance - afterBalance, 1e18, "coinRecipient coin balance");
        assertEq(beforeTotalSupply - afterTotalSupply, 1e18, "coin total supply");
    }

    function test_receive_from_weth() public {
        uint256 orderSize = 1 ether;
        vm.deal(users.buyer, orderSize);
        vm.prank(users.buyer);
        coin.buy{value: orderSize}(users.coinRecipient, users.buyer, users.tradeReferrer, "", ICoin.MarketType.UNISWAP_POOL, 0, 0);

        vm.deal(WETH_ADDRESS, 1 ether);
        vm.prank(WETH_ADDRESS);
        (bool success, ) = address(coin).call{value: 1 ether}("");
        assertTrue(success);
    }

    function test_only_pool_callback() public {
        vm.expectRevert(abi.encodeWithSelector(ICoin.OnlyPool.selector));
        coin.onERC721Received(address(0), address(0), 0, "");
    }

    function test_default_platform_referrer() public {
        Coin newCoin = Coin(payable(factory.deploy(users.creator, address(0), "https://test.com", "Test Token", "TEST")));

        vm.deal(users.buyer, 1 ether);
        vm.prank(users.buyer);
        newCoin.buy{value: 1 ether}(users.coinRecipient, users.buyer, users.tradeReferrer, "", ICoin.MarketType.UNISWAP_POOL, 0, 0);

        uint256 fee = _calculateExpectedFee(1 ether);
        TradeRewards memory expectedFees = _calculateTradeRewards(fee);

        assertGt(protocolRewards.balanceOf(users.feeRecipient), expectedFees.platformReferrer, "feeRecipient eth balance");
    }

    function test_default_order_referrer() public {
        vm.deal(users.buyer, 1 ether);
        vm.prank(users.buyer);
        coin.buy{value: 1 ether}(users.coinRecipient, users.buyer, address(0), "", ICoin.MarketType.UNISWAP_POOL, 0, 0);

        uint256 fee = _calculateExpectedFee(1 ether);
        TradeRewards memory expectedFees = _calculateTradeRewards(fee);

        assertGt(protocolRewards.balanceOf(users.feeRecipient), expectedFees.tradeReferrer, "feeRecipient eth balance");
    }

    function test_market_slippage() public {
        vm.deal(users.buyer, 1 ether);
        vm.prank(users.buyer);
        coin.buy{value: 1 ether}(users.coinRecipient, users.buyer, users.tradeReferrer, "", ICoin.MarketType.UNISWAP_POOL, 0, 0);

        vm.deal(users.buyer, 1 ether);
        vm.prank(users.buyer);
        vm.expectRevert("Too little received"); // Uniswap V3 revert
        coin.buy{value: 1 ether}(
            users.coinRecipient,
            users.buyer,
            users.tradeReferrer,
            "",
            ICoin.MarketType.UNISWAP_POOL,
            type(uint256).max, // Unreasonably high minOrderSize
            0
        );

        vm.prank(users.coinRecipient);
        vm.expectRevert("Too little received"); // Uniswap V3 revert
        coin.sell(
            1e18,
            users.coinRecipient,
            users.tradeReferrer,
            "",
            ICoin.MarketType.UNISWAP_POOL,
            type(uint256).max, // Unreasonably high minPayoutSize
            0
        );
    }

    function test_uniswap_swap_callback() public {
        // Test swap callback
        vm.prank(address(pool));
        coin.uniswapV3SwapCallback(100, -100, "");
    }

    function test_eth_transfer_fail() public {
        vm.deal(users.buyer, 1 ether);
        vm.prank(users.buyer);
        coin.buy{value: 1 ether}(users.coinRecipient, users.buyer, users.tradeReferrer, "", ICoin.MarketType.UNISWAP_POOL, 0, 0);

        // Recipient reverts on ETH receive
        address payable badRecipient = payable(makeAddr("badRecipient"));
        vm.etch(badRecipient, hex"fe");

        vm.prank(users.coinRecipient);
        vm.expectRevert(abi.encodeWithSelector(Address.FailedInnerCall.selector));
        coin.sell(1e18, badRecipient, users.tradeReferrer, "", ICoin.MarketType.UNISWAP_POOL, 0, 0);
    }

    function test_revert_receive_only_weth() public {
        vm.deal(users.buyer, 1 ether);
        vm.prank(users.buyer);
        vm.expectRevert(abi.encodeWithSelector(ICoin.OnlyWeth.selector));
        address(coin).call{value: 1 ether}("");

        assertEq(address(coin).balance, 0, "coin balance");
    }

    function test_rewards() public {
        uint256 initialPlatformReferrerBalance = protocolRewards.balanceOf(users.platformReferrer);
        uint256 initialTokenCreatorBalance = protocolRewards.balanceOf(users.creator);
        uint256 initialOrderReferrerBalance = protocolRewards.balanceOf(users.tradeReferrer);
        uint256 initialFeeRecipientBalance = protocolRewards.balanceOf(users.feeRecipient);

        uint256 buyAmount = 1 ether;
        vm.deal(users.buyer, buyAmount);
        vm.prank(users.buyer);
        coin.buy{value: buyAmount}(users.coinRecipient, users.buyer, users.tradeReferrer, "", ICoin.MarketType.UNISWAP_POOL, 0, 0);

        uint256 orderFee = _calculateExpectedFee(buyAmount); // 1 ETH * 1% --> 0.01 ETH
        TradeRewards memory orderFees = _calculateTradeRewards(orderFee);

        uint256 expectedLpFee = 9900000000000000; // 0.99 ETH * 1% --> ~0.00989 ETH
        MarketRewards memory marketRewards = _calculateMarketRewards(expectedLpFee);

        assertEq(marketRewards.creator + marketRewards.platformReferrer + marketRewards.protocol, expectedLpFee, "Secondary rewards incorrect");
        assertEq(
            protocolRewards.balanceOf(users.creator),
            initialTokenCreatorBalance + orderFees.creator + marketRewards.creator,
            "Token creator rewards incorrect"
        );
        assertEq(
            protocolRewards.balanceOf(users.platformReferrer),
            initialPlatformReferrerBalance + orderFees.platformReferrer + marketRewards.platformReferrer,
            "Platform referrer rewards incorrect"
        );
        assertEq(
            protocolRewards.balanceOf(users.feeRecipient),
            initialFeeRecipientBalance + orderFees.protocol + marketRewards.protocol,
            "Protocol rewards incorrect"
        );
        assertEq(protocolRewards.balanceOf(users.tradeReferrer), initialOrderReferrerBalance + orderFees.tradeReferrer, "Order referrer rewards incorrect");
    }

    function test_contract_uri() public view {
        assertEq(coin.contractURI(), "https://test.com");
    }

    function test_set_contract_uri() public {
        string memory newURI = "https://new.com";

        vm.prank(users.creator);
        coin.setContractURI(newURI);
        assertEq(coin.contractURI(), newURI);
    }

    function test_set_contract_uri_reverts_if_not_owner() public {
        string memory newURI = "https://new.com";

        vm.expectRevert(abi.encodeWithSelector(MultiOwnable.OnlyOwner.selector));
        coin.setContractURI(newURI);
    }

    function test_set_payout_recipient() public {
        address newPayoutRecipient = makeAddr("NewPayoutRecipient");

        vm.prank(users.creator);
        coin.setPayoutRecipient(newPayoutRecipient);
        assertEq(coin.payoutRecipient(), newPayoutRecipient);
    }

    function test_revert_set_payout_recipient_address_zero() public {
        address newPayoutRecipient = address(0);

        vm.expectRevert(abi.encodeWithSelector(ICoin.AddressZero.selector));
        vm.prank(users.creator);
        coin.setPayoutRecipient(newPayoutRecipient);
    }

    function test_revert_set_payout_recipient_only_owner() public {
        address newPayoutRecipient = makeAddr("NewPayoutRecipient");

        vm.expectRevert(abi.encodeWithSelector(MultiOwnable.OnlyOwner.selector));
        coin.setPayoutRecipient(newPayoutRecipient);
    }

    function test_contract_version() public view {
        assertEq(coin.contractVersion(), "0.0.0");
    }
}
