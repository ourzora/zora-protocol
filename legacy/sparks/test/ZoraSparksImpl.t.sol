// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "forge-std/Test.sol";

import {IZoraSparks1155, IZoraSparks1155Errors} from "../src/interfaces/IZoraSparks1155.sol";
import {ZoraSparks1155} from "../src/ZoraSparks1155.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {IERC1155Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
import {ReceiveRejector} from "@zoralabs/shared-contracts/mocks/ReceiveRejector.sol";
import {ZoraSparksFixtures} from "./fixtures/ZoraSparksFixtures.sol";
import {TokenConfig, Redemption} from "../src/ZoraSparksTypes.sol";
import {MockERC20} from "./mocks/MockERC20.sol";
import {ZoraSparksManagerImpl} from "../src/ZoraSparksManagerImpl.sol";
import {IERC1155} from "@openzeppelin/contracts/token/ERC1155/IERC1155.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract ZoraSparks1155Test is Test {
    address admin = makeAddr("admin");
    address proxyAdmin = makeAddr("proxyAdmin");

    IZoraSparks1155 sparks;
    ZoraSparksManagerImpl sparksManager;

    uint256 initialTokenId = 995;
    uint256 initialTokenPrice = 4.32 ether;

    MockERC20 erc20a;
    MockERC20 erc20b;

    address minter = makeAddr("minter");
    address mintRecipient = makeAddr("mintRecipient");
    address redeemRecipient = makeAddr("redeemRecipient");

    function setUp() external {
        (sparks, sparksManager) = ZoraSparksFixtures.setupSparksProxyWithMockPreminter(proxyAdmin, admin, initialTokenId, initialTokenPrice);
        erc20a = setupMockERC20();
        erc20b = setupMockERC20();
    }

    event TokenCreated(uint256 indexed tokenId, uint256 indexed price, address indexed tokenAddress);

    function test_defaultTokenSettings() external {
        assertEq(ZoraSparks1155(address(sparks)).name(), "Zora Sparks");
        assertEq(ZoraSparks1155(address(sparks)).symbol(), "SPARK");
        assertEq(sparks.tokenPrice(initialTokenId), initialTokenPrice);
    }

    function test_ERC165() external {
        assertEq(sparks.supportsInterface(0xd9b67a26), true);
        assertEq(sparks.supportsInterface(0x01ffc9a7), true);
        assertEq(sparks.supportsInterface(0), false);
    }

    function test_mintWithEth_sparksWithInitialSettings() external {
        address collector = makeAddr("collector");
        address recipient = makeAddr("recipient");

        uint256 quantity = 3;
        uint256 quantityToSend = quantity * initialTokenPrice;
        vm.deal(collector, quantityToSend);

        vm.prank(collector);
        sparksManager.mintWithEth{value: quantityToSend}(initialTokenId, quantity, recipient);

        assertEq(payable(address(sparks)).balance, quantityToSend);
    }

    function makeEthTokenConfig(uint256 pricePerToken) internal pure returns (TokenConfig memory) {
        return TokenConfig({price: pricePerToken, tokenAddress: address(0), redeemHandler: address(0)});
    }

    function createEthToken(uint256 tokenId, uint256 pricePerToken) internal {
        TokenConfig memory tokenConfig = TokenConfig({price: pricePerToken, tokenAddress: address(0), redeemHandler: address(0)});
        vm.prank(admin);
        sparksManager.createToken(tokenId, tokenConfig);
    }

    function createErc20Token(uint256 tokenId, address tokenAddress, uint256 pricePerToken) internal {
        TokenConfig memory tokenConfig = TokenConfig({price: pricePerToken, tokenAddress: tokenAddress, redeemHandler: address(0)});
        vm.prank(admin);
        sparksManager.createToken(tokenId, tokenConfig);
    }

    function test_createEthToken_whenDefaultMintable_makesTokenMintable() external {
        uint256 tokenId = 6;
        uint256 pricePerToken = 0.3 ether;
        createEthToken(tokenId, uint96(pricePerToken));

        assertEq(sparks.tokenPrice(tokenId), pricePerToken);
    }

    function test_createEthToken_emitsTokenCreated() external {
        uint256 tokenId = 7;
        uint256 pricePerToken = 0.2 ether;

        TokenConfig memory tokenConfig = makeEthTokenConfig(pricePerToken);

        vm.prank(admin);
        vm.expectEmit(true, true, true, true);
        emit TokenCreated(tokenId, tokenConfig.price, tokenConfig.tokenAddress);
        sparksManager.createToken(tokenId, tokenConfig);
    }

    function test_getters_getProperValues() external {
        uint256 tokenId = 5;
        uint256 pricePerToken = 0.5 ether;

        createEthToken(tokenId, uint96(pricePerToken));

        assertEq(sparks.tokenExists(initialTokenId), true);
        assertEq(sparks.tokenExists(tokenId), true);

        assertEq(sparks.tokenPrice(initialTokenId), initialTokenPrice);
        assertEq(sparks.tokenPrice(tokenId), pricePerToken);
    }

    function test_createToken_revertsWhen_tokenAlreadyExists() external {
        uint256 tokenId = 5;
        uint256 pricePerToken = 0.5 ether;
        createEthToken(tokenId, uint96(pricePerToken));

        vm.expectRevert(IZoraSparks1155Errors.TokenAlreadyCreated.selector);
        createEthToken(tokenId, uint96(pricePerToken));

        vm.expectRevert(IZoraSparks1155Errors.TokenAlreadyCreated.selector);
        createEthToken(tokenId, uint96(pricePerToken + 1));
    }

    function test_createToken_revertsWhen_priceIsLessThanMinimum(uint8 priceChange, bool isEth, bool increases) external {
        vm.assume(priceChange < 2);

        uint256 minimumPrice = isEth ? sparks.MINIMUM_ETH_PRICE() : sparks.MINIMUM_ERC20_PRICE();

        uint256 tokenId = 5;
        uint256 pricePerToken = minimumPrice;
        if (increases) {
            pricePerToken += priceChange;
        } else {
            pricePerToken -= priceChange;
        }

        TokenConfig memory tokenConfig = TokenConfig({price: pricePerToken, tokenAddress: isEth ? address(0) : makeAddr("erc20"), redeemHandler: address(0)});
        if (pricePerToken < minimumPrice) {
            vm.expectRevert(IZoraSparks1155Errors.InvalidTokenPrice.selector);
        }
        vm.prank(admin);
        sparksManager.createToken(tokenId, tokenConfig);
    }

    function test_createToken_revertsWhen_notAdmin() external {
        address notAdmin = makeAddr("notAdmin");

        TokenConfig memory tokenConfig = makeEthTokenConfig(0.5 ether);

        vm.startPrank(notAdmin);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, notAdmin));
        sparksManager.createToken(1, tokenConfig);
    }

    function test_mintWithEth_whenCorrectEth_resultsInQuantityMintedToRecipient() external {
        uint256 firstTokenId = 3;
        uint256 firstTokenPrice = 0.5 ether;

        createEthToken(firstTokenId, uint96(firstTokenPrice));

        address collector = makeAddr("collector");
        address recipient = makeAddr("recipient");

        uint256 quantity = 5;
        uint256 quantityToSend = quantity * firstTokenPrice;
        vm.deal(collector, quantityToSend);

        vm.prank(collector);
        sparksManager.mintWithEth{value: quantityToSend}(firstTokenId, quantity, recipient);

        assertEq(sparks.balanceOf(recipient, firstTokenId), quantity, "quantity minted to recipient");
        assertEq(payable(address(sparks)).balance, quantityToSend, "sparks balance");
    }

    function test_mintWithEth_revertsWhen_invalidAmountSent(uint8 offset, bool increase) external {
        vm.assume(offset > 0);
        uint256 firstTokenId = 3;
        uint256 firstTokenPrice = 0.5 ether;

        createEthToken(firstTokenId, uint96(firstTokenPrice));

        address collector = makeAddr("collector");

        uint256 quantity = 5;
        uint256 quantityToSend = quantity * firstTokenPrice;
        if (increase) {
            quantityToSend += offset;
        } else {
            quantityToSend -= offset;
        }
        vm.deal(collector, quantityToSend);

        vm.prank(collector);
        vm.expectRevert(IZoraSparks1155Errors.IncorrectAmountSent.selector);
        sparksManager.mintWithEth{value: quantityToSend}(firstTokenId, quantity, collector);
    }

    function test_mintWithEth_revertsWhen_addressZero() external {
        address collector = makeAddr("collector");
        uint256 quantityToSend = initialTokenPrice * 2;
        vm.deal(collector, quantityToSend);
        vm.prank(collector);

        vm.expectRevert(abi.encodeWithSelector(IERC1155Errors.ERC1155InvalidReceiver.selector, address(0)));
        sparksManager.mintWithEth{value: quantityToSend}(initialTokenId, 2, address(0));
    }

    function test_mintTokenWithEth_revertsWhen_notAnEthToken() external {
        // address collector = makeAddr("collector");

        vm.prank(admin);
        sparksManager.createToken(2, TokenConfig({price: 1 ether, tokenAddress: makeAddr("nonEthToken"), redeemHandler: address(0)}));

        vm.prank(address(sparksManager));
        vm.expectRevert(abi.encodeWithSelector(IZoraSparks1155Errors.TokenMismatch.selector, makeAddr("nonEthToken"), address(0)));
        sparks.mintTokenWithEth(2, 5, address(0), "");
    }

    function test_mintTokenWithEth_revertsWhen_notAToken() external {
        vm.prank(address(sparksManager));
        vm.expectRevert(IZoraSparks1155Errors.TokenDoesNotExist.selector);
        sparks.mintTokenWithEth(2, 5, address(0), "");
    }

    function setupMockERC20() internal returns (MockERC20) {
        MockERC20 mockERC20 = new MockERC20("MockERC20", "MERC20");
        return mockERC20;
    }

    function mintWithERC20(uint256 tokenId, address tokenAddress, uint256 quantityToMint, address recipient) internal {
        sparksManager.mintWithERC20(tokenId, tokenAddress, quantityToMint, recipient);
    }

    function test_mintWithERC20_transfersBalanceToContract() external {
        MockERC20 erc20 = setupMockERC20();

        uint256 erc20TokenId = 100;
        uint256 tokenPrice = sparks.MINIMUM_ERC20_PRICE() * 2;

        uint256 initialErc20Balance = 1000000;

        uint256 quantityToMint = 5;

        uint256 expectedErc20ToTransfer = quantityToMint * tokenPrice;

        // create an erc20 based mint token id using the mock erc20 address as the token address, and set it as default mintable
        vm.prank(admin);
        sparksManager.createToken(erc20TokenId, TokenConfig({price: tokenPrice, tokenAddress: address(erc20), redeemHandler: address(0)}));

        // mint some erc20s to the minter
        vm.startPrank(minter);
        erc20.mint(initialErc20Balance);
        // approve what is needed to transfer to the sparks contract
        erc20.approve(address(sparksManager), expectedErc20ToTransfer);

        // mint the mint token id using the erc20 token
        sparksManager.mintWithERC20(erc20TokenId, address(erc20), quantityToMint, mintRecipient);

        assertEq(erc20.balanceOf(minter), initialErc20Balance - expectedErc20ToTransfer);
        assertEq(erc20.balanceOf(address(sparks)), expectedErc20ToTransfer);
        assertEq(sparks.balanceOf(mintRecipient, erc20TokenId), quantityToMint);
    }

    function test_mintWithERC20_revertsWhen_erc20Slippage() external {
        MockERC20 erc20 = setupMockERC20();

        uint256 erc20TokenId = 100;
        uint256 tokenPrice = sparks.MINIMUM_ERC20_PRICE() * 2;

        uint256 initialErc20Balance = 1000000;

        uint256 quantityToMint = 5;

        uint256 expectedErc20ToTransfer = quantityToMint * tokenPrice;

        // create an erc20 based mint token id using the mock erc20 address as the token address, and set it as default mintable
        vm.prank(admin);
        sparksManager.createToken(erc20TokenId, TokenConfig({price: tokenPrice, tokenAddress: address(erc20), redeemHandler: address(0)}));

        // set a tax on the erc20
        erc20.setTax(10);

        // mint some erc20s to the minter
        vm.startPrank(minter);
        erc20.mint(initialErc20Balance);
        // approve what is needed to transfer to the sparks contract
        erc20.approve(address(sparksManager), expectedErc20ToTransfer);

        vm.expectRevert(IZoraSparks1155Errors.ERC20TransferSlippage.selector);
        // mint the mint token id using the erc20 token
        sparksManager.mintWithERC20(erc20TokenId, address(erc20), quantityToMint, mintRecipient);
    }

    function test_redeem_sendsValueOfTokens_toRecipient(bool isErc20Token) external {
        // create a token
        uint256 tokenId = 5;
        uint256 pricePerToken = isErc20Token ? 100_000 : 1 ether;

        MockERC20 erc20 = setupMockERC20();

        address tokenAddress = isErc20Token ? address(erc20) : address(0);

        vm.prank(admin);
        sparksManager.createToken(tokenId, TokenConfig({price: pricePerToken, tokenAddress: tokenAddress, redeemHandler: address(0)}));

        uint256 quantityToMint = 7;

        // mint some tokens to a recipient
        if (isErc20Token) {
            vm.startPrank(minter);
            erc20.mint(quantityToMint * pricePerToken + 100);
            erc20.approve(address(sparksManager), quantityToMint * pricePerToken + 100);
            sparksManager.mintWithERC20(tokenId, tokenAddress, quantityToMint, mintRecipient);
            vm.stopPrank();
        } else {
            vm.deal(minter, quantityToMint * pricePerToken);
            vm.prank(minter);
            sparksManager.mintWithEth{value: quantityToMint * pricePerToken}(tokenId, quantityToMint, mintRecipient);
        }

        uint256 quantityToRedeem = 4;
        // redeem some tokens to a redeem recipient
        vm.prank(mintRecipient);
        uint256 valueRedeemed = sparks.redeem(tokenId, quantityToRedeem, redeemRecipient).valueRedeemed;

        assertEq(valueRedeemed, quantityToRedeem * pricePerToken);

        if (isErc20Token) {
            assertEq(erc20.balanceOf(redeemRecipient), quantityToRedeem * pricePerToken);
            assertEq(erc20.balanceOf(minter), 100);
        } else {
            // balance of contract should be reduced by the value of the tokens
            assertEq(payable(address(sparks)).balance, (quantityToMint - quantityToRedeem) * pricePerToken);
            // balance of redeem recipient should be increased by the value of the tokens
            assertEq(redeemRecipient.balance, quantityToRedeem * pricePerToken);
        }

        // balance of tokens should be reduced
        assertEq(sparks.balanceOf(mintRecipient, tokenId), quantityToMint - quantityToRedeem);
    }

    function test_redeem_revertsWhen_insufficientBalance() external {
        // create a token
        uint256 tokenId = 5;
        uint256 pricePerToken = 0.52 ether;

        createEthToken(tokenId, uint96(pricePerToken));

        uint256 quantityToMint = 7;

        // mint some tokens to a recipient
        vm.deal(minter, quantityToMint * pricePerToken);
        vm.prank(minter);
        sparksManager.mintWithEth{value: quantityToMint * pricePerToken}(tokenId, quantityToMint, mintRecipient);

        uint256 quantityToRedeem = quantityToMint + 1;

        // redeem in excess of balance
        vm.prank(mintRecipient);
        vm.expectRevert(abi.encodeWithSelector(IERC1155Errors.ERC1155InsufficientBalance.selector, mintRecipient, quantityToMint, quantityToRedeem, tokenId));
        sparks.redeem(tokenId, quantityToRedeem, redeemRecipient);

        // redeem from account that doesnt have tokens
        vm.prank(minter);
        vm.expectRevert(abi.encodeWithSelector(IERC1155Errors.ERC1155InsufficientBalance.selector, minter, 0, quantityToMint, tokenId));
        sparks.redeem(tokenId, quantityToMint, redeemRecipient);

        // redeem full balance, then redeem again, it should revert
        vm.prank(mintRecipient);
        sparks.redeem(tokenId, quantityToMint, redeemRecipient);

        vm.prank(mintRecipient);
        vm.expectRevert(abi.encodeWithSelector(IERC1155Errors.ERC1155InsufficientBalance.selector, mintRecipient, 0, 1, tokenId));
        sparks.redeem(tokenId, 1, redeemRecipient);
    }

    function test_redeem_revertsWhen_addressZero() external {
        uint256 pricePerToken = initialTokenPrice;
        uint256 quantityToMint = 7;

        // mint some tokens to a recipient
        vm.deal(minter, quantityToMint * pricePerToken);
        vm.prank(minter);
        sparksManager.mintWithEth{value: quantityToMint * pricePerToken}(initialTokenId, quantityToMint, minter);

        uint256 quantityToRedeem = 4;

        // redeem some tokens to a redeem recipient
        vm.prank(minter);
        vm.expectRevert(IZoraSparks1155Errors.InvalidRecipient.selector);
        sparks.redeem(initialTokenId, quantityToRedeem, address(0));
    }

    function test_redeem_failsWhen_cannotSendValueToRecipient() external {
        // create a token
        uint256 tokenId = 5;
        uint256 pricePerToken = 0.52 ether;

        createEthToken(tokenId, uint96(pricePerToken));

        uint256 quantityToMint = 7;

        // mint some tokens to a recipient
        vm.deal(minter, quantityToMint * pricePerToken);
        vm.prank(minter);
        sparksManager.mintWithEth{value: quantityToMint * pricePerToken}(tokenId, quantityToMint, mintRecipient);

        uint256 quantityToRedeem = 4;

        address transferRejector = address(new ReceiveRejector());

        // redeem some tokens to a redeem recipient
        vm.startPrank(mintRecipient);
        vm.expectRevert(IZoraSparks1155Errors.ETHTransferFailed.selector);
        sparks.redeem(tokenId, quantityToRedeem, transferRejector);
    }

    function testFuzz_redeeemWithdrawsCorrectAmount(
        uint8 firstTokenQuantityToMint,
        uint8 firstTokenQuantityToRedeem,
        uint8 secondTokenQuantityToMint,
        uint8 secondTokenQuantityToRedeem
    ) external {
        vm.assume(firstTokenQuantityToMint < 50);
        vm.assume(secondTokenQuantityToMint < 50);
        // done prevent overflows
        // ensure redeeming valid amount
        vm.assume(firstTokenQuantityToRedeem < firstTokenQuantityToMint);
        vm.assume(secondTokenQuantityToRedeem < secondTokenQuantityToMint);
        uint256 firstTokenId = 5;
        uint256 secondTokenId = 10;

        uint256 firstTokenPrice = 1.2 ether;
        uint256 secondTokenPrice = 2.3 ether;

        // create 2 tokens, but second one is not default mintable
        createEthToken(firstTokenId, uint96(firstTokenPrice));
        createEthToken(secondTokenId, uint96(secondTokenPrice));

        // mint some tokens to a recipient
        if (firstTokenQuantityToMint > 0) {
            vm.deal(minter, firstTokenPrice * firstTokenQuantityToMint);
            vm.prank(minter);
            sparksManager.mintWithEth{value: firstTokenPrice * firstTokenQuantityToMint}(firstTokenId, firstTokenQuantityToMint, mintRecipient);
        }

        if (secondTokenQuantityToMint > 0) {
            vm.deal(minter, secondTokenPrice * secondTokenQuantityToMint);
            vm.prank(minter);
            sparksManager.mintWithEth{value: secondTokenPrice * secondTokenQuantityToMint}(secondTokenId, secondTokenQuantityToMint, mintRecipient);
        }

        // check balances
        assertEq(sparks.balanceOf(mintRecipient, firstTokenId), firstTokenQuantityToMint);
        assertEq(sparks.balanceOf(mintRecipient, secondTokenId), secondTokenQuantityToMint);
        // check eth balance of contract
        uint256 valueDeposited = (firstTokenPrice * firstTokenQuantityToMint) + (secondTokenPrice * secondTokenQuantityToMint);
        assertEq(payable(address(sparks)).balance, valueDeposited);

        // now redeem some tokens
        if (firstTokenQuantityToRedeem > 0) {
            vm.prank(mintRecipient);
            sparks.redeem(firstTokenId, firstTokenQuantityToRedeem, redeemRecipient);
        }

        if (secondTokenQuantityToRedeem > 0) {
            vm.prank(mintRecipient);
            sparks.redeem(secondTokenId, secondTokenQuantityToRedeem, redeemRecipient);
        }

        // check balances
        assertEq(sparks.balanceOf(mintRecipient, firstTokenId), firstTokenQuantityToMint - firstTokenQuantityToRedeem);
        assertEq(sparks.balanceOf(mintRecipient, secondTokenId), secondTokenQuantityToMint - secondTokenQuantityToRedeem);
        // check eth balances
        uint256 valueRedeemed = (firstTokenPrice * firstTokenQuantityToRedeem) + (secondTokenPrice * secondTokenQuantityToRedeem);
        assertEq(payable(address(sparks)).balance, valueDeposited - valueRedeemed);
        assertEq(redeemRecipient.balance, valueRedeemed);
    }

    function mintErc20AndBuyMint(address _minter, MockERC20 erc20, uint256 tokenId, uint256 mintTokenQuantity, address _mintRecipient) internal {
        uint256 quantity = sparks.tokenPrice(tokenId) * mintTokenQuantity;
        vm.startPrank(_minter);
        erc20.mint(quantity);
        erc20.approve(address(sparksManager), quantity);
        sparksManager.mintWithERC20(tokenId, address(erc20), mintTokenQuantity, _mintRecipient);
        vm.stopPrank();
    }

    function testFuzz_redeeemBatch_withdrawsCorrectAmount(
        bool firstTokenIsErc20,
        uint8 firstTokenQuantityToMint,
        uint8 firstTokenQuantityToRedeem,
        bool secondTokenIsErc20,
        uint8 secondTokenQuantityToMint,
        uint8 secondTokenQuantityToRedeem
    ) external {
        vm.assume(firstTokenQuantityToMint < 50);
        vm.assume(secondTokenQuantityToMint < 50);
        // done prevent overflows
        // ensure redeeming valid amount
        vm.assume(firstTokenQuantityToRedeem < firstTokenQuantityToMint);
        vm.assume(secondTokenQuantityToRedeem < secondTokenQuantityToMint);
        uint256 firstTokenId = 5;
        uint256 secondTokenId = 10;

        uint256 firstTokenPrice = firstTokenIsErc20 ? 20_000 : 1.2 ether;
        uint256 secondTokenPrice = secondTokenIsErc20 ? 30_000 : 2.3 ether;

        uint256 expectedEthValueRedeemed;
        uint256 valueDeposited;

        // create 2 tokens, but second one is not default mintable
        if (firstTokenIsErc20) {
            createErc20Token(firstTokenId, address(erc20a), uint96(firstTokenPrice));
        } else {
            createEthToken(firstTokenId, uint96(firstTokenPrice));
            valueDeposited += firstTokenPrice * firstTokenQuantityToMint;
            expectedEthValueRedeemed += firstTokenPrice * firstTokenQuantityToRedeem;
        }
        if (secondTokenIsErc20) {
            createErc20Token(secondTokenId, address(erc20b), uint96(secondTokenPrice));
        } else {
            createEthToken(secondTokenId, uint96(secondTokenPrice));
            valueDeposited += secondTokenPrice * secondTokenQuantityToMint;
            expectedEthValueRedeemed += secondTokenPrice * secondTokenQuantityToRedeem;
        }

        // mint some tokens to a recipient
        if (firstTokenQuantityToMint > 0) {
            if (firstTokenIsErc20) {
                mintErc20AndBuyMint(minter, erc20a, firstTokenId, firstTokenQuantityToMint, mintRecipient);
            } else {
                vm.deal(minter, firstTokenPrice * firstTokenQuantityToMint);
                vm.prank(minter);
                sparksManager.mintWithEth{value: firstTokenPrice * firstTokenQuantityToMint}(firstTokenId, firstTokenQuantityToMint, mintRecipient);
            }
        }

        if (secondTokenQuantityToMint > 0) {
            if (secondTokenIsErc20) {
                mintErc20AndBuyMint(minter, erc20b, secondTokenId, secondTokenQuantityToMint, mintRecipient);
            } else {
                vm.deal(minter, secondTokenPrice * secondTokenQuantityToMint);
                vm.prank(minter);
                sparksManager.mintWithEth{value: secondTokenPrice * secondTokenQuantityToMint}(secondTokenId, secondTokenQuantityToMint, mintRecipient);
            }
        }

        // check eth balance of contract

        assertEq(payable(address(sparks)).balance, valueDeposited);

        uint256 valueRedeemed;
        {
            uint256[] memory tokenIds = new uint256[](2);
            tokenIds[0] = firstTokenId;
            tokenIds[1] = secondTokenId;

            uint256[] memory quantities = new uint256[](2);
            quantities[0] = firstTokenQuantityToRedeem;
            quantities[1] = secondTokenQuantityToRedeem;

            vm.prank(mintRecipient);
            Redemption[] memory redemptions = sparks.redeemBatch(tokenIds, quantities, redeemRecipient);
            for (uint256 i = 0; i < redemptions.length; i++) {
                if (redemptions[i].tokenAddress == address(0)) {
                    valueRedeemed += redemptions[i].valueRedeemed;
                }
            }
        }

        // check balances
        assertEq(sparks.balanceOf(mintRecipient, firstTokenId), firstTokenQuantityToMint - firstTokenQuantityToRedeem, "token 1 change");
        assertEq(sparks.balanceOf(mintRecipient, secondTokenId), secondTokenQuantityToMint - secondTokenQuantityToRedeem, "token 2 change");

        assertEq(valueRedeemed, expectedEthValueRedeemed, "value redeemed");
        assertEq(payable(address(sparks)).balance, valueDeposited - expectedEthValueRedeemed, "sparks balance");
        assertEq(redeemRecipient.balance, expectedEthValueRedeemed, "redeem recipient balance");

        if (firstTokenIsErc20) {
            assertEq(erc20a.balanceOf(redeemRecipient), firstTokenPrice * firstTokenQuantityToRedeem);
        }
        if (secondTokenIsErc20) {
            assertEq(erc20b.balanceOf(redeemRecipient), secondTokenPrice * secondTokenQuantityToRedeem);
        }
    }

    function test_redeemBatch_revertsWhen_cannotSend() external {
        // create a token
        uint256 tokenId = 5;
        uint256 pricePerToken = 0.52 ether;

        createEthToken(tokenId, uint96(pricePerToken));

        uint256 quantityToMint = 7;

        // mint some tokens to a recipient
        vm.deal(minter, quantityToMint * pricePerToken);
        vm.prank(minter);
        sparksManager.mintWithEth{value: quantityToMint * pricePerToken}(tokenId, quantityToMint, mintRecipient);

        uint256 quantityToRedeem = 4;

        address transferRejector = address(new ReceiveRejector());

        uint256[] memory tokenIds = new uint256[](1);
        tokenIds[0] = tokenId;

        uint256[] memory quantities = new uint256[](1);
        quantities[0] = quantityToRedeem;

        // redeem some tokens to a redeem recipient
        vm.startPrank(mintRecipient);
        vm.expectRevert(IZoraSparks1155Errors.ETHTransferFailed.selector);
        sparks.redeemBatch(tokenIds, quantities, transferRejector);
    }

    function test_redeemBatch_revertsWhen_recipientAddressZero() external {
        // create a token
        uint256 quantityToMint = 7;
        uint256 pricePerToken = initialTokenPrice;

        uint256 tokenId = initialTokenId;

        // mint some tokens to a recipient
        vm.deal(minter, quantityToMint * pricePerToken);
        vm.prank(minter);
        sparksManager.mintWithEth{value: quantityToMint * pricePerToken}(tokenId, quantityToMint, mintRecipient);

        uint256 quantityToRedeem = 4;

        uint256[] memory tokenIds = new uint256[](1);
        tokenIds[0] = tokenId;

        uint256[] memory quantities = new uint256[](1);
        quantities[0] = quantityToRedeem;

        // redeem some tokens to a redeem recipient
        vm.startPrank(mintRecipient);
        vm.expectRevert(IZoraSparks1155Errors.InvalidRecipient.selector);
        sparks.redeemBatch(tokenIds, quantities, address(0));
    }
}
