// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import "forge-std/Test.sol";
import {ZoraRewards} from "@zoralabs/zora-rewards/dist/contracts/ZoraRewards.sol";
import {ZoraCreator1155Impl} from "../../../src/nft/ZoraCreator1155Impl.sol";
import {Zora1155} from "../../../src/proxies/Zora1155.sol";
import {IZoraCreator1155} from "../../../src/interfaces/IZoraCreator1155.sol";
import {IMinter1155} from "../../../src/interfaces/IMinter1155.sol";
import {ICreatorRoyaltiesControl} from "../../../src/interfaces/ICreatorRoyaltiesControl.sol";
import {IZoraCreator1155Factory} from "../../../src/interfaces/IZoraCreator1155Factory.sol";
import {ILimitedMintPerAddress} from "../../../src/interfaces/ILimitedMintPerAddress.sol";
import {ZoraCreatorFixedPriceSaleStrategy} from "../../../src/minters/fixed-price/ZoraCreatorFixedPriceSaleStrategy.sol";

contract ZoraCreatorFixedPriceSaleStrategyTest is Test {
    ZoraCreator1155Impl internal target;
    ZoraCreatorFixedPriceSaleStrategy internal fixedPrice;
    address payable internal admin = payable(address(0x999));
    address internal zora;

    event SaleSet(address indexed mediaContract, uint256 indexed tokenId, ZoraCreatorFixedPriceSaleStrategy.SalesConfig salesConfig);
    event MintComment(address indexed sender, address indexed tokenContract, uint256 indexed tokenId, uint256 quantity, string comment);

    function setUp() external {
        zora = makeAddr("zora");
        bytes[] memory emptyData = new bytes[](0);
        ZoraRewards zoraRewards = new ZoraRewards();
        ZoraCreator1155Impl targetImpl = new ZoraCreator1155Impl(0, zora, address(0), address(zoraRewards));
        Zora1155 proxy = new Zora1155(address(targetImpl));
        target = ZoraCreator1155Impl(address(proxy));
        target.initialize("test", "test", ICreatorRoyaltiesControl.RoyaltyConfiguration(0, 0, address(0)), admin, emptyData);
        fixedPrice = new ZoraCreatorFixedPriceSaleStrategy();
    }

    function test_ContractName() external {
        assertEq(fixedPrice.contractName(), "Fixed Price Sale Strategy");
    }

    function test_Version() external {
        assertEq(fixedPrice.contractVersion(), "1.1.0");
    }

    function test_MintFlow() external {
        vm.startPrank(admin);
        uint256 newTokenId = target.setupNewToken("https://zora.co/testing/token.json", 10);
        target.addPermission(newTokenId, address(fixedPrice), target.PERMISSION_BIT_MINTER());
        vm.expectEmit(true, true, true, true);
        emit SaleSet(
            address(target),
            newTokenId,
            ZoraCreatorFixedPriceSaleStrategy.SalesConfig({
                pricePerToken: 1 ether,
                saleStart: 0,
                saleEnd: type(uint64).max,
                maxTokensPerAddress: 0,
                fundsRecipient: address(0)
            })
        );
        target.callSale(
            newTokenId,
            fixedPrice,
            abi.encodeWithSelector(
                ZoraCreatorFixedPriceSaleStrategy.setSale.selector,
                newTokenId,
                ZoraCreatorFixedPriceSaleStrategy.SalesConfig({
                    pricePerToken: 1 ether,
                    saleStart: 0,
                    saleEnd: type(uint64).max,
                    maxTokensPerAddress: 0,
                    fundsRecipient: address(0)
                })
            )
        );
        vm.stopPrank();

        address tokenRecipient = address(322);
        vm.deal(tokenRecipient, 20 ether);

        vm.startPrank(tokenRecipient);
        target.mint{value: 10 ether}(fixedPrice, newTokenId, 10, abi.encode(tokenRecipient, ""));

        assertEq(target.balanceOf(tokenRecipient, newTokenId), 10);
        assertEq(address(target).balance, 10 ether);

        vm.stopPrank();
    }

    function test_MintWithCommentBackwardsCompatible() external {
        vm.startPrank(admin);
        uint256 newTokenId = target.setupNewToken("https://zora.co/testing/token.json", 10);
        target.addPermission(newTokenId, address(fixedPrice), target.PERMISSION_BIT_MINTER());
        vm.expectEmit(true, true, true, true);
        emit SaleSet(
            address(target),
            newTokenId,
            ZoraCreatorFixedPriceSaleStrategy.SalesConfig({
                pricePerToken: 1 ether,
                saleStart: 0,
                saleEnd: type(uint64).max,
                maxTokensPerAddress: 0,
                fundsRecipient: address(0)
            })
        );
        target.callSale(
            newTokenId,
            fixedPrice,
            abi.encodeWithSelector(
                ZoraCreatorFixedPriceSaleStrategy.setSale.selector,
                newTokenId,
                ZoraCreatorFixedPriceSaleStrategy.SalesConfig({
                    pricePerToken: 1 ether,
                    saleStart: 0,
                    saleEnd: type(uint64).max,
                    maxTokensPerAddress: 0,
                    fundsRecipient: address(0)
                })
            )
        );
        vm.stopPrank();

        address tokenRecipient = address(322);
        vm.deal(tokenRecipient, 20 ether);

        vm.startPrank(tokenRecipient);
        target.mint{value: 10 ether}(fixedPrice, newTokenId, 10, abi.encode(tokenRecipient));

        assertEq(target.balanceOf(tokenRecipient, newTokenId), 10);
        assertEq(address(target).balance, 10 ether);

        vm.stopPrank();
    }

    function test_MintWithComment() external {
        vm.startPrank(admin);
        uint256 newTokenId = target.setupNewToken("https://zora.co/testing/token.json", 10);
        target.addPermission(newTokenId, address(fixedPrice), target.PERMISSION_BIT_MINTER());
        vm.expectEmit(true, true, true, true);
        emit SaleSet(
            address(target),
            newTokenId,
            ZoraCreatorFixedPriceSaleStrategy.SalesConfig({
                pricePerToken: 1 ether,
                saleStart: 0,
                saleEnd: type(uint64).max,
                maxTokensPerAddress: 0,
                fundsRecipient: address(0)
            })
        );
        target.callSale(
            newTokenId,
            fixedPrice,
            abi.encodeWithSelector(
                ZoraCreatorFixedPriceSaleStrategy.setSale.selector,
                newTokenId,
                ZoraCreatorFixedPriceSaleStrategy.SalesConfig({
                    pricePerToken: 1 ether,
                    saleStart: 0,
                    saleEnd: type(uint64).max,
                    maxTokensPerAddress: 0,
                    fundsRecipient: address(0)
                })
            )
        );
        vm.stopPrank();

        address tokenRecipient = address(322);
        vm.deal(tokenRecipient, 20 ether);

        vm.startPrank(tokenRecipient);
        vm.expectEmit(true, true, true, true);
        emit MintComment(tokenRecipient, address(target), newTokenId, 10, "test comment");
        target.mint{value: 10 ether}(fixedPrice, newTokenId, 10, abi.encode(tokenRecipient, "test comment"));

        assertEq(target.balanceOf(tokenRecipient, newTokenId), 10);
        assertEq(address(target).balance, 10 ether);

        vm.stopPrank();
    }

    function test_SaleStart() external {
        vm.startPrank(admin);
        uint256 newTokenId = target.setupNewToken("https://zora.co/testing/token.json", 10);
        target.addPermission(newTokenId, address(fixedPrice), target.PERMISSION_BIT_MINTER());
        target.callSale(
            newTokenId,
            fixedPrice,
            abi.encodeWithSelector(
                ZoraCreatorFixedPriceSaleStrategy.setSale.selector,
                newTokenId,
                ZoraCreatorFixedPriceSaleStrategy.SalesConfig({
                    pricePerToken: 1 ether,
                    saleStart: uint64(block.timestamp + 1 days),
                    saleEnd: type(uint64).max,
                    maxTokensPerAddress: 10,
                    fundsRecipient: address(0)
                })
            )
        );
        vm.stopPrank();

        address tokenRecipient = address(322);
        vm.deal(tokenRecipient, 20 ether);

        vm.expectRevert(abi.encodeWithSignature("SaleHasNotStarted()"));
        vm.prank(tokenRecipient);
        target.mint{value: 10 ether}(fixedPrice, newTokenId, 10, abi.encode(tokenRecipient, ""));
    }

    function test_SaleEnd() external {
        vm.warp(2 days);

        vm.startPrank(admin);
        uint256 newTokenId = target.setupNewToken("https://zora.co/testing/token.json", 10);
        target.addPermission(newTokenId, address(fixedPrice), target.PERMISSION_BIT_MINTER());
        target.callSale(
            newTokenId,
            fixedPrice,
            abi.encodeWithSelector(
                ZoraCreatorFixedPriceSaleStrategy.setSale.selector,
                newTokenId,
                ZoraCreatorFixedPriceSaleStrategy.SalesConfig({
                    pricePerToken: 1 ether,
                    saleStart: 0,
                    saleEnd: uint64(1 days),
                    maxTokensPerAddress: 0,
                    fundsRecipient: address(0)
                })
            )
        );
        vm.stopPrank();

        address tokenRecipient = address(322);
        vm.deal(tokenRecipient, 20 ether);

        vm.expectRevert(abi.encodeWithSignature("SaleEnded()"));
        vm.prank(tokenRecipient);
        target.mint{value: 10 ether}(fixedPrice, newTokenId, 10, abi.encode(tokenRecipient, ""));
    }

    function test_MaxTokensPerAddress() external {
        vm.warp(2 days);

        vm.startPrank(admin);
        uint256 newTokenId = target.setupNewToken("https://zora.co/testing/token.json", 10);
        target.addPermission(newTokenId, address(fixedPrice), target.PERMISSION_BIT_MINTER());
        target.callSale(
            newTokenId,
            fixedPrice,
            abi.encodeWithSelector(
                ZoraCreatorFixedPriceSaleStrategy.setSale.selector,
                newTokenId,
                ZoraCreatorFixedPriceSaleStrategy.SalesConfig({
                    pricePerToken: 1 ether,
                    saleStart: 0,
                    saleEnd: type(uint64).max,
                    maxTokensPerAddress: 5,
                    fundsRecipient: address(0)
                })
            )
        );
        vm.stopPrank();

        address tokenRecipient = address(322);
        vm.deal(tokenRecipient, 20 ether);

        vm.prank(tokenRecipient);
        vm.expectRevert(abi.encodeWithSelector(ILimitedMintPerAddress.UserExceedsMintLimit.selector, tokenRecipient, 5, 6));
        target.mint{value: 6 ether}(fixedPrice, newTokenId, 6, abi.encode(tokenRecipient, ""));
    }

    function testFail_setupMint() external {
        vm.startPrank(admin);
        uint256 newTokenId = target.setupNewToken("https://zora.co/testing/token.json", 10);
        target.addPermission(newTokenId, address(fixedPrice), target.PERMISSION_BIT_MINTER());
        target.callSale(
            newTokenId,
            fixedPrice,
            abi.encodeWithSelector(
                ZoraCreatorFixedPriceSaleStrategy.setSale.selector,
                newTokenId,
                ZoraCreatorFixedPriceSaleStrategy.SalesConfig({
                    pricePerToken: 1 ether,
                    saleStart: 0,
                    saleEnd: type(uint64).max,
                    maxTokensPerAddress: 9,
                    fundsRecipient: address(0)
                })
            )
        );
        vm.stopPrank();

        address tokenRecipient = address(322);
        vm.deal(tokenRecipient, 20 ether);

        vm.startPrank(tokenRecipient);
        target.mint{value: 10 ether}(fixedPrice, newTokenId, 10, abi.encode(tokenRecipient));

        assertEq(target.balanceOf(tokenRecipient, newTokenId), 10);
        assertEq(address(target).balance, 10 ether);

        vm.stopPrank();
    }

    function test_PricePerToken() external {
        vm.warp(2 days);

        vm.startPrank(admin);
        uint256 newTokenId = target.setupNewToken("https://zora.co/testing/token.json", 10);
        target.addPermission(newTokenId, address(fixedPrice), target.PERMISSION_BIT_MINTER());
        target.callSale(
            newTokenId,
            fixedPrice,
            abi.encodeWithSelector(
                ZoraCreatorFixedPriceSaleStrategy.setSale.selector,
                newTokenId,
                ZoraCreatorFixedPriceSaleStrategy.SalesConfig({
                    pricePerToken: 1 ether,
                    saleStart: 0,
                    saleEnd: type(uint64).max,
                    maxTokensPerAddress: 0,
                    fundsRecipient: address(0)
                })
            )
        );
        vm.stopPrank();

        address tokenRecipient = address(322);
        vm.deal(tokenRecipient, 20 ether);

        vm.startPrank(tokenRecipient);
        vm.expectRevert(abi.encodeWithSignature("WrongValueSent()"));
        target.mint{value: 0.9 ether}(fixedPrice, newTokenId, 1, abi.encode(tokenRecipient, ""));
        vm.expectRevert(abi.encodeWithSignature("WrongValueSent()"));
        target.mint{value: 1.1 ether}(fixedPrice, newTokenId, 1, abi.encode(tokenRecipient, ""));
        target.mint{value: 1 ether}(fixedPrice, newTokenId, 1, abi.encode(tokenRecipient, ""));
        vm.stopPrank();
    }

    function test_FundsRecipient() external {
        vm.startPrank(admin);
        uint256 newTokenId = target.setupNewToken("https://zora.co/testing/token.json", 10);
        target.addPermission(newTokenId, address(fixedPrice), target.PERMISSION_BIT_MINTER());
        target.callSale(
            newTokenId,
            fixedPrice,
            abi.encodeWithSelector(
                ZoraCreatorFixedPriceSaleStrategy.setSale.selector,
                newTokenId,
                ZoraCreatorFixedPriceSaleStrategy.SalesConfig({
                    pricePerToken: 1 ether,
                    saleStart: 0,
                    saleEnd: type(uint64).max,
                    maxTokensPerAddress: 0,
                    fundsRecipient: address(1)
                })
            )
        );
        vm.stopPrank();

        address tokenRecipient = address(322);
        vm.deal(tokenRecipient, 20 ether);
        vm.prank(tokenRecipient);
        target.mint{value: 10 ether}(fixedPrice, newTokenId, 10, abi.encode(tokenRecipient, ""));

        assertEq(address(1).balance, 10 ether);
    }

    function test_MintedPerRecipientGetter() external {
        vm.startPrank(admin);
        uint256 newTokenId = target.setupNewToken("https://zora.co/testing/token.json", 10);
        target.addPermission(newTokenId, address(fixedPrice), target.PERMISSION_BIT_MINTER());
        target.callSale(
            newTokenId,
            fixedPrice,
            abi.encodeWithSelector(
                ZoraCreatorFixedPriceSaleStrategy.setSale.selector,
                newTokenId,
                ZoraCreatorFixedPriceSaleStrategy.SalesConfig({
                    pricePerToken: 0 ether,
                    saleStart: 0,
                    saleEnd: type(uint64).max,
                    maxTokensPerAddress: 20,
                    fundsRecipient: address(0)
                })
            )
        );
        vm.stopPrank();

        address tokenRecipient = address(322);
        vm.deal(tokenRecipient, 20 ether);
        vm.prank(tokenRecipient);
        target.mint{value: 0 ether}(fixedPrice, newTokenId, 10, abi.encode(tokenRecipient, ""));

        assertEq(fixedPrice.getMintedPerWallet(address(target), newTokenId, tokenRecipient), 10);
    }

    function test_ResetSale() external {
        vm.startPrank(admin);
        uint256 newTokenId = target.setupNewToken("https://zora.co/testing/token.json", 10);
        target.addPermission(newTokenId, address(fixedPrice), target.PERMISSION_BIT_MINTER());
        vm.expectEmit(false, false, false, false);
        emit SaleSet(
            address(target),
            newTokenId,
            ZoraCreatorFixedPriceSaleStrategy.SalesConfig({pricePerToken: 0, saleStart: 0, saleEnd: 0, maxTokensPerAddress: 0, fundsRecipient: address(0)})
        );
        target.callSale(newTokenId, fixedPrice, abi.encodeWithSelector(ZoraCreatorFixedPriceSaleStrategy.resetSale.selector, newTokenId));
        vm.stopPrank();

        ZoraCreatorFixedPriceSaleStrategy.SalesConfig memory sale = fixedPrice.sale(address(target), newTokenId);
        assertEq(sale.pricePerToken, 0);
        assertEq(sale.saleStart, 0);
        assertEq(sale.saleEnd, 0);
        assertEq(sale.maxTokensPerAddress, 0);
        assertEq(sale.fundsRecipient, address(0));
    }

    function test_fixedPriceSaleSupportsInterface() public {
        assertTrue(fixedPrice.supportsInterface(0x6890e5b3));
        assertTrue(fixedPrice.supportsInterface(0x01ffc9a7));
        assertFalse(fixedPrice.supportsInterface(0x0));
    }
}
