// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "./BaseTest.sol";
import {IERC20Z} from "../src/interfaces/IERC20Z.sol";
import {IZora1155} from "../src/interfaces/IZora1155.sol";
import {IRoyalties} from "../src/interfaces/IRoyalties.sol";
import {MockMintableERC721} from "./mock/MockMintableERC721.sol";
import {MockMintableERC1155} from "./mock/MockMintableERC1155.sol";
import {IERC1155} from "@openzeppelin/contracts/token/ERC1155/IERC1155.sol";
import {ERC20Z} from "../src/ERC20Z.sol";

contract ERC20zTest is BaseTest {
    function setUpTimedSale(uint64 saleStart) public {
        IZoraTimedSaleStrategy.SalesConfigV2 memory salesConfig = IZoraTimedSaleStrategy.SalesConfigV2({
            saleStart: saleStart,
            marketCountdown: DEFAULT_MARKET_COUNTDOWN,
            minimumMarketEth: DEFAULT_MINIMUM_MARKET_ETH,
            name: "Test",
            symbol: "TST"
        });
        vm.prank(users.creator);
        collection.callSale(tokenId, saleStrategy, abi.encodeWithSelector(saleStrategy.setSaleV2.selector, tokenId, salesConfig));

        vm.label(saleStrategy.sale(address(collection), tokenId).erc20zAddress, "ERC20Z");
        vm.label(saleStrategy.sale(address(collection), tokenId).poolAddress, "V3_POOL");
    }

    function testERC20zInit() public {
        address erc20z = setUpERC20z();

        assertEq(IERC20Z(erc20z).name(), "TestName");
        assertEq(IERC20Z(erc20z).symbol(), "TestSymbol");
    }

    function testRevertsWhenRoyaltiesAddressZero() public {
        // will be an evm error revert
        vm.expectRevert();
        new ERC20Z(IRoyalties(address(0)));
    }

    function testERC20zSendingRandomERC721() public {
        address erc20z = setUpERC20z();
        MockMintableERC721 mockERC721 = new MockMintableERC721();
        address testOwner = makeAddr("testOwner");
        vm.startPrank(testOwner);
        mockERC721.mint(1);
        vm.expectRevert(IERC20Z.OnlySupportReceivingERC721UniswapPoolNFTs.selector);
        mockERC721.safeTransferFrom(testOwner, erc20z, 1);
    }

    function testERC20ZSendingRandomERC1155() public {
        address erc20z = setUpERC20z();
        MockMintableERC1155 mockERC1155 = new MockMintableERC1155();
        address testOwner = makeAddr("testOwner");
        vm.startPrank(testOwner);
        mockERC1155.mint(1, 1);
        vm.expectRevert(IERC20Z.OnlySupportReceivingERC1155AssociatedZoraNFT.selector);
        mockERC1155.safeTransferFrom(testOwner, erc20z, 1, 1, "");

        uint256[] memory idsAndValues = new uint256[](1);
        idsAndValues[0] = 1;

        vm.expectRevert(IERC20Z.OnlySupportReceivingERC1155AssociatedZoraNFT.selector);
        mockERC1155.safeBatchTransferFrom(testOwner, erc20z, idsAndValues, idsAndValues, "");
    }

    function testERC20zTokenURI() public {
        address erc20z = setUpERC20z();

        assertEq(IZora1155(address(collection)).uri(tokenId), "token.uri");
        assertEq(IERC20Z(erc20z).tokenURI(), "token.uri");
    }

    function testERC20zContractURI() public {
        address erc20z = setUpERC20z();

        assertEq(IZora1155(address(collection)).uri(tokenId), "token.uri");
        assertEq(IERC20Z(erc20z).contractURI(), "token.uri");
    }

    function erc20zMintSetUp() public returns (address) {
        setUpTimedSale(uint64(block.timestamp));

        uint256 totalTokens = 2;
        uint256 totalValue = mintFee * totalTokens;
        vm.deal(users.collector, totalValue);

        vm.prank(users.collector);
        saleStrategy.mint{value: totalValue}(users.collector, totalTokens, address(collection), tokenId, users.mintReferral, "");

        IZoraTimedSaleStrategy.SaleStorage memory sale = saleStrategy.sale(address(collection), tokenId);
        return sale.erc20zAddress;
    }

    function testERC20zActivateInvalidParams() public {
        address erc20z = erc20zMintSetUp();
        IZoraTimedSaleStrategy.ERC20zActivate memory calculatedValues = saleStrategy.calculateERC20zActivate(address(collection), tokenId, erc20z);

        vm.prank(address(saleStrategy));
        IZora1155(address(collection)).reduceSupply(tokenId, calculatedValues.final1155Supply);
        vm.prank(address(saleStrategy));
        IZora1155(address(collection)).adminMint(erc20z, tokenId, calculatedValues.additionalERC1155ToMint, "");

        // test ERC20Z activate with invalid msg.sender
        vm.expectRevert(abi.encodeWithSignature("OnlySaleStrategy()"));
        IERC20Z(erc20z).activate(
            calculatedValues.finalTotalERC20ZSupply,
            calculatedValues.erc20Reserve,
            calculatedValues.erc20Liquidity,
            calculatedValues.excessERC20,
            calculatedValues.excessERC1155
        );

        // test ERC20Z activate with invalid params
        vm.expectRevert(abi.encodeWithSignature("InvalidParams()"));
        vm.prank(address(saleStrategy));
        IERC20Z(erc20z).activate(
            calculatedValues.finalTotalERC20ZSupply,
            123,
            calculatedValues.erc20Liquidity,
            calculatedValues.excessERC20,
            calculatedValues.excessERC1155
        );
    }

    function testERC20zActivateValid() public {
        address erc20z = erc20zMintSetUp();

        IZoraTimedSaleStrategy.ERC20zActivate memory calculatedValues = saleStrategy.calculateERC20zActivate(address(collection), tokenId, erc20z);

        uint176 nextTokenId = uint176(
            uint256(vm.load(address(nonfungiblePositionManager), bytes32(0x000000000000000000000000000000000000000000000000000000000000000d)))
        );

        uint256 newTokenId = uint256(nextTokenId);

        bool wethFirst = WETH_ADDRESS < erc20z;

        vm.startPrank(address(saleStrategy));
        IZora1155(address(collection)).reduceSupply(tokenId, calculatedValues.final1155Supply);
        IZora1155(address(collection)).adminMint(erc20z, tokenId, calculatedValues.additionalERC1155ToMint, "");

        vm.expectEmit(true, true, true, true);
        emit IERC20Z.SecondaryMarketActivated({
            token0: wethFirst ? WETH_ADDRESS : erc20z,
            amount0: wethFirst ? 44399999999999 : 399999999999999948,
            token1: wethFirst ? erc20z : WETH_ADDRESS,
            amount1: wethFirst ? 399999999999999948 : 44399999999999,
            fee: 10000,
            positionId: newTokenId,
            lpLiquidity: 4214261501141000,
            erc20Excess: 600000000000000000,
            erc1155Excess: 1
        });

        IERC20Z(erc20z).activate(
            calculatedValues.finalTotalERC20ZSupply,
            calculatedValues.erc20Reserve,
            calculatedValues.erc20Liquidity,
            calculatedValues.excessERC20,
            calculatedValues.excessERC1155
        );
        vm.stopPrank();
    }

    function testERC20zActivateNoReactivate() public {
        address erc20z = erc20zMintSetUp();

        IZoraTimedSaleStrategy.ERC20zActivate memory calculatedValues = saleStrategy.calculateERC20zActivate(address(collection), tokenId, erc20z);

        vm.startPrank(address(saleStrategy));
        IZora1155(address(collection)).reduceSupply(tokenId, calculatedValues.final1155Supply);
        IZora1155(address(collection)).adminMint(erc20z, tokenId, calculatedValues.additionalERC1155ToMint, "");

        IERC20Z(erc20z).activate(
            calculatedValues.finalTotalERC20ZSupply,
            calculatedValues.erc20Reserve,
            calculatedValues.erc20Liquidity,
            calculatedValues.excessERC20,
            calculatedValues.excessERC1155
        );

        vm.expectRevert(IERC20Z.AlreadyActivatedCannotReactivate.selector);
        IERC20Z(erc20z).activate(
            calculatedValues.finalTotalERC20ZSupply,
            calculatedValues.erc20Reserve,
            calculatedValues.erc20Liquidity,
            calculatedValues.excessERC20,
            calculatedValues.excessERC1155
        );
        vm.stopPrank();
    }

    function testERC20zConvertTokens() public {
        address erc20z = erc20zMintSetUp();

        IZoraTimedSaleStrategy.ERC20zActivate memory calculatedValues = saleStrategy.calculateERC20zActivate(address(collection), tokenId, erc20z);

        vm.startPrank(address(saleStrategy));
        IZora1155(address(collection)).reduceSupply(tokenId, calculatedValues.final1155Supply);
        IZora1155(address(collection)).adminMint(erc20z, tokenId, calculatedValues.additionalERC1155ToMint, "");
        IERC20Z(erc20z).activate(
            calculatedValues.finalTotalERC20ZSupply,
            calculatedValues.erc20Reserve,
            calculatedValues.erc20Liquidity,
            calculatedValues.excessERC20,
            calculatedValues.excessERC1155
        );
        vm.stopPrank();

        // convert 1155 token for erc20z token
        assertEq(IERC1155(address(collection)).balanceOf(users.collector, tokenId), 2);
        vm.startPrank(users.collector);
        IERC1155(address(collection)).setApprovalForAll(erc20z, true);
        IERC20Z(erc20z).wrap(1, users.collector);
        assertEq(IERC20Z(erc20z).balanceOf(users.collector), 1e18);

        // convert erc20z token for 1155 token
        IERC20Z(erc20z).approve(erc20z, 1e18);
        IERC20Z(erc20z).unwrap(1e18, users.collector);
        assertEq(IERC1155(address(collection)).balanceOf(users.collector, tokenId), 2);
        assertEq(IERC20Z(erc20z).balanceOf(users.collector), 0);

        vm.stopPrank();
    }

    function testERC20zConvertTokensSendingToToken() public {
        address erc20z = erc20zMintSetUp();

        IZoraTimedSaleStrategy.ERC20zActivate memory calculatedValues = saleStrategy.calculateERC20zActivate(address(collection), tokenId, erc20z);

        vm.startPrank(address(saleStrategy));
        IZora1155(address(collection)).reduceSupply(tokenId, calculatedValues.final1155Supply);
        IZora1155(address(collection)).adminMint(erc20z, tokenId, calculatedValues.additionalERC1155ToMint, "");
        IERC20Z(erc20z).activate(
            calculatedValues.finalTotalERC20ZSupply,
            calculatedValues.erc20Reserve,
            calculatedValues.erc20Liquidity,
            calculatedValues.excessERC20,
            calculatedValues.excessERC1155
        );
        vm.stopPrank();

        // convert 1155 token for erc20z token
        assertEq(IERC1155(address(collection)).balanceOf(users.collector, tokenId), 2);
        vm.startPrank(users.collector);
        IERC1155(address(collection)).safeTransferFrom(users.collector, erc20z, tokenId, 1, "");
        assertEq(IERC20Z(erc20z).balanceOf(users.collector), 1e18);

        // convert 1155 token for erc20z token (batch call)
        uint256[] memory batchTokenIds = new uint256[](1);
        batchTokenIds[0] = tokenId;
        uint256[] memory batchTokenAmounts = new uint256[](1);
        batchTokenAmounts[0] = 1;

        assertEq(IERC1155(address(collection)).balanceOf(users.collector, tokenId), 1);
        vm.startPrank(users.collector);
        IERC1155(address(collection)).safeBatchTransferFrom(users.collector, erc20z, batchTokenIds, batchTokenAmounts, "");
        assertEq(IERC20Z(erc20z).balanceOf(users.collector), 2e18);

        // convert erc20z token for 1155 token
        IERC20Z(erc20z).approve(erc20z, 1e18);
        IERC20Z(erc20z).unwrap(1e18, users.collector);
        assertEq(IERC1155(address(collection)).balanceOf(users.collector, tokenId), 1);
        assertEq(IERC20Z(erc20z).balanceOf(users.collector), 1e18);
        // fail converting erc20z token to 1155 token with 0 recipient address specified
        vm.startPrank(users.collector);

        // unknown data sent
        vm.expectRevert();
        IERC1155(address(collection)).safeTransferFrom(users.collector, erc20z, tokenId, 1, hex"abcdef");

        address newCollector = makeAddr("newCollector");
        IERC1155(address(collection)).safeTransferFrom(users.collector, erc20z, tokenId, 1, abi.encode(newCollector));
        assertEq(IERC20Z(erc20z).balanceOf(newCollector), 1e18);

        vm.stopPrank();
    }

    function testERC20zConvert1155Invalid() public {
        address erc20z = erc20zMintSetUp();

        // secondary market has not started
        vm.expectRevert(IERC20Z.SecondaryMarketHasNotYetStarted.selector);
        IERC20Z(erc20z).unwrap(1e18, users.collector);

        IZoraTimedSaleStrategy.ERC20zActivate memory calculatedValues = saleStrategy.calculateERC20zActivate(address(collection), tokenId, erc20z);

        vm.startPrank(address(saleStrategy));
        IZora1155(address(collection)).reduceSupply(tokenId, calculatedValues.final1155Supply);
        IZora1155(address(collection)).adminMint(erc20z, tokenId, calculatedValues.additionalERC1155ToMint, "");
        IERC20Z(erc20z).activate(
            calculatedValues.finalTotalERC20ZSupply,
            calculatedValues.erc20Reserve,
            calculatedValues.erc20Liquidity,
            calculatedValues.excessERC20,
            calculatedValues.excessERC1155
        );
        vm.stopPrank();

        // recipient address is zero
        vm.expectRevert(IERC20Z.RecipientAddressZero.selector);
        IERC20Z(erc20z).unwrap(1e18, address(0));

        // invalid amount
        vm.expectRevert(IERC20Z.InvalidAmount20z.selector);
        IERC20Z(erc20z).unwrap(0.000111 ether, users.collector);
    }

    function testERC20zConvert20zInvalid() public {
        address erc20z = erc20zMintSetUp();

        // secondary market has not started
        vm.startPrank(users.collector);
        IERC1155(address(collection)).setApprovalForAll(erc20z, true);
        vm.expectRevert(IERC20Z.SecondaryMarketHasNotYetStarted.selector);
        IERC20Z(erc20z).wrap(1, users.collector);
        vm.stopPrank();

        IZoraTimedSaleStrategy.ERC20zActivate memory calculatedValues = saleStrategy.calculateERC20zActivate(address(collection), tokenId, erc20z);

        vm.startPrank(address(saleStrategy));
        IZora1155(address(collection)).reduceSupply(tokenId, calculatedValues.final1155Supply);
        IZora1155(address(collection)).adminMint(erc20z, tokenId, calculatedValues.additionalERC1155ToMint, "");
        IERC20Z(erc20z).activate(
            calculatedValues.finalTotalERC20ZSupply,
            calculatedValues.erc20Reserve,
            calculatedValues.erc20Liquidity,
            calculatedValues.excessERC20,
            calculatedValues.excessERC1155
        );
        vm.stopPrank();

        // recipient address is zero
        vm.startPrank(users.collector);
        IERC1155(address(collection)).setApprovalForAll(erc20z, true);
        vm.expectRevert(IERC20Z.RecipientAddressZero.selector);
        IERC20Z(erc20z).wrap(1, address(0));

        vm.stopPrank();
    }

    function testReduceSupplyWrongAddress() public {
        setUpERC20z();
        setUpTimedSale(uint64(block.timestamp));

        vm.expectRevert();
        collection.reduceSupply(tokenId, 1000000000000);
    }

    function testERC20zConvertFuzz(uint256 tokens) public {
        vm.assume(tokens > 0 && tokens < 100_000_000);

        // activate primary
        setUpERC20z();
        setUpTimedSale(uint64(block.timestamp));

        uint256 totalValue = mintFee * tokens;
        vm.deal(users.collector, totalValue);

        vm.prank(users.collector);
        saleStrategy.mint{value: totalValue}(users.collector, tokens, address(collection), tokenId, users.mintReferral, "");
        IZoraTimedSaleStrategy.SaleStorage memory sale = saleStrategy.sale(address(collection), tokenId);
        address erc20z = sale.erc20zAddress;

        IZoraTimedSaleStrategy.ERC20zActivate memory calculatedValues = saleStrategy.calculateERC20zActivate(address(collection), tokenId, erc20z);

        // activate secondary
        vm.startPrank(address(saleStrategy));
        IZora1155(address(collection)).reduceSupply(tokenId, calculatedValues.final1155Supply);
        IZora1155(address(collection)).adminMint(erc20z, tokenId, calculatedValues.additionalERC1155ToMint, "");
        IERC20Z(erc20z).activate(
            calculatedValues.finalTotalERC20ZSupply,
            calculatedValues.erc20Reserve,
            calculatedValues.erc20Liquidity,
            calculatedValues.excessERC20,
            calculatedValues.excessERC1155
        );
        vm.stopPrank();

        // convert 1155 tokens for erc20z tokens
        assertEq(IERC1155(address(collection)).balanceOf(users.collector, tokenId), tokens);
        vm.startPrank(users.collector);
        IERC1155(address(collection)).setApprovalForAll(erc20z, true);
        IERC20Z(erc20z).wrap(tokens, users.collector);
        assertEq(IERC20Z(erc20z).balanceOf(users.collector), 1e18 * tokens);

        // convert erc20z tokens for 1155 tokens
        IERC20Z(erc20z).approve(erc20z, 1e18 * tokens);
        IERC20Z(erc20z).unwrap(1e18 * tokens, users.collector);
        assertEq(IERC1155(address(collection)).balanceOf(users.collector, tokenId), tokens);
        assertEq(IERC20Z(erc20z).balanceOf(users.collector), 0);

        vm.stopPrank();
    }
}
