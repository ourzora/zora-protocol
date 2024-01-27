// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import "forge-std/Test.sol";
import {ProtocolRewards} from "@zoralabs/protocol-rewards/src/ProtocolRewards.sol";
import {ZoraCreator1155Impl} from "../../../src/nft/ZoraCreator1155Impl.sol";
import {Zora1155} from "../../../src/proxies/Zora1155.sol";
import {IZoraCreator1155Errors} from "../../../src/interfaces/IZoraCreator1155Errors.sol";
import {IMinter1155} from "../../../src/interfaces/IMinter1155.sol";
import {ICreatorRoyaltiesControl} from "../../../src/interfaces/ICreatorRoyaltiesControl.sol";
import {IZoraCreator1155Factory} from "../../../src/interfaces/IZoraCreator1155Factory.sol";
import {ILimitedMintPerAddressErrors} from "../../../src/interfaces/ILimitedMintPerAddress.sol";
import {ERC20CreatorFixedPriceSaleStrategy} from "../../../src/minters/fixed-price/ERC20CreatorFixedPriceSaleStrategy.sol";
import {ERC20PresetMinterPauser} from "@openzeppelin/contracts/token/ERC20/presets/ERC20PresetMinterPauser.sol";

contract ERC20CreatorFixedPriceSaleStrategyTest is Test {
    ZoraCreator1155Impl internal target;
    ERC20CreatorFixedPriceSaleStrategy internal fixedPriceErc20;
    ERC20PresetMinterPauser internal usdc;
    address payable internal admin = payable(address(0x999));
    address internal zora;
    address internal tokenRecipient;
    address internal fundsRecipient;

    event SaleSet(address indexed mediaContract, uint256 indexed tokenId, ERC20CreatorFixedPriceSaleStrategy.SalesConfig salesConfig);
    event MintComment(address indexed sender, address indexed tokenContract, uint256 indexed tokenId, uint256 quantity, string comment);

    function setUp() external {
        zora = makeAddr("zora");
        tokenRecipient = makeAddr("tokenRecipient");
        fundsRecipient = makeAddr("fundsRecipient");

        bytes[] memory emptyData = new bytes[](0);
        ProtocolRewards protocolRewards = new ProtocolRewards();
        ZoraCreator1155Impl targetImpl = new ZoraCreator1155Impl(zora, address(0), address(protocolRewards));
        Zora1155 proxy = new Zora1155(address(targetImpl));
        target = ZoraCreator1155Impl(payable(address(proxy)));
        target.initialize("test", "test", ICreatorRoyaltiesControl.RoyaltyConfiguration(0, 0, address(0)), admin, emptyData);
        fixedPriceErc20 = new ERC20CreatorFixedPriceSaleStrategy();
        vm.prank(admin);
        usdc = new ERC20PresetMinterPauser("USDC", "USDC");
    }

    function test_ContractName() external {
        assertEq(fixedPriceErc20.contractName(), "Fixed Price Sale Strategy");
    }

    function test_Version() external {
        assertEq(fixedPriceErc20.contractVersion(), "1.1.0");
    }

    function test_MintFlow() external {
        vm.startPrank(admin);
        uint256 newTokenId = target.setupNewToken("https://zora.co/testing/token.json", 10);
    
        // GRANT MINTER ADMIN ROLE - adminMint (skip zora fee)
        target.addPermission(newTokenId, address(fixedPriceErc20), target.PERMISSION_BIT_ADMIN());
        uint96 pricePerToken = 100;
        

        // CREATOR CALLS callSale on CREATORCROP
        vm.expectEmit(true, true, true, true);
        emit SaleSet(
            address(target),
            newTokenId,
            ERC20CreatorFixedPriceSaleStrategy.SalesConfig({
                pricePerToken: pricePerToken,
                saleStart: 0,
                saleEnd: type(uint64).max,
                maxTokensPerAddress: 0,
                fundsRecipient: fundsRecipient,
                erc20Address: address(usdc)
            })
        );
        target.callSale(
            newTokenId,
            fixedPriceErc20,
            abi.encodeWithSelector(
                ERC20CreatorFixedPriceSaleStrategy.setSale.selector,
                newTokenId,
                ERC20CreatorFixedPriceSaleStrategy.SalesConfig({
                    pricePerToken: pricePerToken,
                    saleStart: 0,
                    saleEnd: type(uint64).max,
                    maxTokensPerAddress: 0,
                    fundsRecipient: fundsRecipient,
                    erc20Address: address(usdc)
                })
            )
        );
        vm.stopPrank();

        
        // AIRDROP USDC
        uint256 numTokens = 10;
        uint256 totalValue = (pricePerToken * numTokens);
        vm.prank(admin);
        usdc.mint(tokenRecipient, totalValue);

        // COLLECTOR APPROVED USDC for MINTER
        vm.startPrank(tokenRecipient);
        usdc.approve(address(fixedPriceErc20), totalValue);

        // COLLECTOR CALL requestMint 
        fixedPriceErc20.requestMint(address(target), newTokenId, numTokens, 0, abi.encode(tokenRecipient, ""));

        // VERIFY COLLECT
        assertEq(target.balanceOf(tokenRecipient, newTokenId), numTokens);

        // VERIFY USDC PAYMENT
        assertEq(usdc.balanceOf(fundsRecipient), totalValue);
        vm.stopPrank();
    }

    // function test_MintWithCommentBackwardsCompatible() external {
    //     vm.startPrank(admin);
    //     uint256 newTokenId = target.setupNewToken("https://zora.co/testing/token.json", 10);
    //     target.addPermission(newTokenId, address(fixedPriceErc20), target.PERMISSION_BIT_MINTER());
    //     vm.expectEmit(true, true, true, true);
    //     emit SaleSet(
    //         address(target),
    //         newTokenId,
    //         ERC20CreatorFixedPriceSaleStrategy.SalesConfig({
    //             pricePerToken: 1 ether,
    //             saleStart: 0,
    //             saleEnd: type(uint64).max,
    //             maxTokensPerAddress: 0,
    //             fundsRecipient: address(0),
    //             erc20Address: address(0)
    //         })
    //     );
    //     target.callSale(
    //         newTokenId,
    //         fixedPriceErc20,
    //         abi.encodeWithSelector(
    //             ERC20CreatorFixedPriceSaleStrategy.setSale.selector,
    //             newTokenId,
    //             ERC20CreatorFixedPriceSaleStrategy.SalesConfig({
    //                 pricePerToken: 1 ether,
    //                 saleStart: 0,
    //                 saleEnd: type(uint64).max,
    //                 maxTokensPerAddress: 0,
    //                 fundsRecipient: address(0),
    //                 erc20Address: address(0)
    //             })
    //         )
    //     );
    //     vm.stopPrank();

    //     uint256 numTokens = 10;
    //     uint256 totalReward = target.computeTotalReward(numTokens);
    //     uint256 totalValue = (1 ether * numTokens) + totalReward;

    //     vm.deal(tokenRecipient, totalValue);

    //     vm.startPrank(tokenRecipient);
    //     target.mintWithRewards{value: totalValue}(fixedPriceErc20, newTokenId, 10, abi.encode(tokenRecipient), address(0));

    //     assertEq(target.balanceOf(tokenRecipient, newTokenId), 10);
    //     assertEq(address(target).balance, 10 ether);

    //     vm.stopPrank();
    // }

    // function test_MintWithComment() external {
    //     vm.startPrank(admin);
    //     uint256 newTokenId = target.setupNewToken("https://zora.co/testing/token.json", 10);
    //     target.addPermission(newTokenId, address(fixedPriceErc20), target.PERMISSION_BIT_MINTER());
    //     vm.expectEmit(true, true, true, true);
    //     emit SaleSet(
    //         address(target),
    //         newTokenId,
    //         ERC20CreatorFixedPriceSaleStrategy.SalesConfig({
    //             pricePerToken: 1 ether,
    //             saleStart: 0,
    //             saleEnd: type(uint64).max,
    //             maxTokensPerAddress: 0,
    //             fundsRecipient: address(0),
    //             erc20Address: address(0)
    //         })
    //     );
    //     target.callSale(
    //         newTokenId,
    //         fixedPriceErc20,
    //         abi.encodeWithSelector(
    //             ERC20CreatorFixedPriceSaleStrategy.setSale.selector,
    //             newTokenId,
    //             ERC20CreatorFixedPriceSaleStrategy.SalesConfig({
    //                 pricePerToken: 1 ether,
    //                 saleStart: 0,
    //                 saleEnd: type(uint64).max,
    //                 maxTokensPerAddress: 0,
    //                 fundsRecipient: address(0),
    //                 erc20Address: address(0)
    //             })
    //         )
    //     );
    //     vm.stopPrank();

    //     uint256 numTokens = 10;
    //     uint256 totalReward = target.computeTotalReward(numTokens);
    //     uint256 totalValue = (1 ether * numTokens) + totalReward;

    //     vm.deal(tokenRecipient, totalValue);

    //     vm.startPrank(tokenRecipient);
    //     vm.expectEmit(true, true, true, true);
    //     emit MintComment(tokenRecipient, address(target), newTokenId, 10, "test comment");
    //     target.mintWithRewards{value: totalValue}(fixedPriceErc20, newTokenId, 10, abi.encode(tokenRecipient, "test comment"), address(0));

    //     assertEq(target.balanceOf(tokenRecipient, newTokenId), 10);
    //     assertEq(address(target).balance, 10 ether);

    //     vm.stopPrank();
    // }

    // function test_SaleStart() external {
    //     vm.startPrank(admin);
    //     uint256 newTokenId = target.setupNewToken("https://zora.co/testing/token.json", 10);
    //     target.addPermission(newTokenId, address(fixedPriceErc20), target.PERMISSION_BIT_MINTER());
    //     target.callSale(
    //         newTokenId,
    //         fixedPriceErc20,
    //         abi.encodeWithSelector(
    //             ERC20CreatorFixedPriceSaleStrategy.setSale.selector,
    //             newTokenId,
    //             ERC20CreatorFixedPriceSaleStrategy.SalesConfig({
    //                 pricePerToken: 1 ether,
    //                 saleStart: uint64(block.timestamp + 1 days),
    //                 saleEnd: type(uint64).max,
    //                 maxTokensPerAddress: 10,
    //                 fundsRecipient: address(0),
    //                 erc20Address: address(0)
    //             })
    //         )
    //     );
    //     vm.stopPrank();

    //     vm.deal(tokenRecipient, 20 ether);

    //     vm.expectRevert(abi.encodeWithSignature("SaleHasNotStarted()"));
    //     vm.prank(tokenRecipient);
    //     target.mintWithRewards{value: 10 ether}(fixedPriceErc20, newTokenId, 10, abi.encode(tokenRecipient, ""), address(0));
    // }

    // function test_WrongValueSent() external {
    //     uint96 pricePerToken = 1 ether;

    //     vm.startPrank(admin);
    //     uint256 newTokenId = target.setupNewToken("https://zora.co/testing/token.json", 10);
    //     target.addPermission(newTokenId, address(fixedPriceErc20), target.PERMISSION_BIT_MINTER());
    //     target.callSale(
    //         newTokenId,
    //         fixedPriceErc20,
    //         abi.encodeWithSelector(
    //             ERC20CreatorFixedPriceSaleStrategy.setSale.selector,
    //             newTokenId,
    //             ERC20CreatorFixedPriceSaleStrategy.SalesConfig({
    //                 pricePerToken: pricePerToken,
    //                 saleStart: 0,
    //                 saleEnd: type(uint64).max,
    //                 maxTokensPerAddress: 11,
    //                 fundsRecipient: address(0),
    //                 erc20Address: address(0)
    //             })
    //         )
    //     );
    //     vm.stopPrank();

    //     vm.deal(tokenRecipient, 20 ether);
    //     uint256 quantity = 1;
    //     uint256 totalReward = target.computeTotalReward(quantity);
    //     uint256 totalValue = (pricePerToken * quantity) + totalReward;
    //     vm.expectRevert(abi.encodeWithSignature("WrongValueSent()"));
    //     vm.prank(tokenRecipient);
    //     target.mintWithRewards{value: totalValue + 1}(fixedPriceErc20, newTokenId, quantity, abi.encode(tokenRecipient, ""), address(0));
    // }

    // function test_SaleEnd() external {
    //     vm.warp(2 days);

    //     vm.startPrank(admin);
    //     uint256 newTokenId = target.setupNewToken("https://zora.co/testing/token.json", 10);
    //     target.addPermission(newTokenId, address(fixedPriceErc20), target.PERMISSION_BIT_MINTER());
    //     target.callSale(
    //         newTokenId,
    //         fixedPriceErc20,
    //         abi.encodeWithSelector(
    //             ERC20CreatorFixedPriceSaleStrategy.setSale.selector,
    //             newTokenId,
    //             ERC20CreatorFixedPriceSaleStrategy.SalesConfig({
    //                 pricePerToken: 1 ether,
    //                 saleStart: 0,
    //                 saleEnd: uint64(1 days),
    //                 maxTokensPerAddress: 0,
    //                 fundsRecipient: address(0),
    //                 erc20Address: address(0)
    //             })
    //         )
    //     );
    //     vm.stopPrank();

    //     vm.deal(tokenRecipient, 20 ether);

    //     vm.expectRevert(abi.encodeWithSignature("SaleEnded()"));
    //     vm.prank(tokenRecipient);
    //     target.mintWithRewards{value: 10 ether}(fixedPriceErc20, newTokenId, 10, abi.encode(tokenRecipient, ""), address(0));
    // }

    // function test_MaxTokensPerAddress() external {
    //     vm.warp(2 days);

    //     vm.startPrank(admin);
    //     uint256 newTokenId = target.setupNewToken("https://zora.co/testing/token.json", 10);
    //     target.addPermission(newTokenId, address(fixedPriceErc20), target.PERMISSION_BIT_MINTER());
    //     target.callSale(
    //         newTokenId,
    //         fixedPriceErc20,
    //         abi.encodeWithSelector(
    //             ERC20CreatorFixedPriceSaleStrategy.setSale.selector,
    //             newTokenId,
    //             ERC20CreatorFixedPriceSaleStrategy.SalesConfig({
    //                 pricePerToken: 1 ether,
    //                 saleStart: 0,
    //                 saleEnd: type(uint64).max,
    //                 maxTokensPerAddress: 5,
    //                 fundsRecipient: address(0),
    //                 erc20Address: address(0)
    //             })
    //         )
    //     );
    //     vm.stopPrank();

    //     uint256 numTokens = 6;
    //     uint256 totalReward = target.computeTotalReward(numTokens);
    //     uint256 totalValue = (1 ether * numTokens) + totalReward;

    //     vm.deal(tokenRecipient, totalValue);

    //     vm.prank(tokenRecipient);
    //     vm.expectRevert(abi.encodeWithSelector(ILimitedMintPerAddressErrors.UserExceedsMintLimit.selector, tokenRecipient, 5, 6));
    //     target.mintWithRewards{value: totalValue}(fixedPriceErc20, newTokenId, numTokens, abi.encode(tokenRecipient, ""), address(0));
    // }

    // function testFail_setupMint() external {
    //     vm.startPrank(admin);
    //     uint256 newTokenId = target.setupNewToken("https://zora.co/testing/token.json", 10);
    //     target.addPermission(newTokenId, address(fixedPriceErc20), target.PERMISSION_BIT_MINTER());
    //     target.callSale(
    //         newTokenId,
    //         fixedPriceErc20,
    //         abi.encodeWithSelector(
    //             ERC20CreatorFixedPriceSaleStrategy.setSale.selector,
    //             newTokenId,
    //             ERC20CreatorFixedPriceSaleStrategy.SalesConfig({
    //                 pricePerToken: 1 ether,
    //                 saleStart: 0,
    //                 saleEnd: type(uint64).max,
    //                 maxTokensPerAddress: 9,
    //                 fundsRecipient: address(0),
    //                 erc20Address: address(0)
    //             })
    //         )
    //     );
    //     vm.stopPrank();

    //     vm.deal(tokenRecipient, 20 ether);

    //     vm.startPrank(tokenRecipient);
    //     target.mintWithRewards{value: 10 ether}(fixedPriceErc20, newTokenId, 10, abi.encode(tokenRecipient), address(0));

    //     assertEq(target.balanceOf(tokenRecipient, newTokenId), 10);
    //     assertEq(address(target).balance, 10 ether);

    //     vm.stopPrank();
    // }

    // function test_PricePerToken() external {
    //     vm.warp(2 days);

    //     vm.startPrank(admin);
    //     uint256 newTokenId = target.setupNewToken("https://zora.co/testing/token.json", 10);
    //     target.addPermission(newTokenId, address(fixedPriceErc20), target.PERMISSION_BIT_MINTER());
    //     target.callSale(
    //         newTokenId,
    //         fixedPriceErc20,
    //         abi.encodeWithSelector(
    //             ERC20CreatorFixedPriceSaleStrategy.setSale.selector,
    //             newTokenId,
    //             ERC20CreatorFixedPriceSaleStrategy.SalesConfig({
    //                 pricePerToken: 1 ether,
    //                 saleStart: 0,
    //                 saleEnd: type(uint64).max,
    //                 maxTokensPerAddress: 0,
    //                 fundsRecipient: address(0),
    //                 erc20Address: address(0)
    //             })
    //         )
    //     );
    //     vm.stopPrank();

    //     vm.deal(tokenRecipient, 20 ether);

    //     vm.startPrank(tokenRecipient);

    //     target.mintWithRewards{value: 1.000777 ether}(fixedPriceErc20, newTokenId, 1, abi.encode(tokenRecipient, ""), address(0));

    //     vm.stopPrank();
    // }

    // function test_FundsRecipient() external {
    //     uint96 pricePerToken = 1 ether;
    //     uint256 numTokens = 10;

    //     vm.startPrank(admin);
    //     uint256 newTokenId = target.setupNewToken("https://zora.co/testing/token.json", 10);
    //     target.addPermission(newTokenId, address(fixedPriceErc20), target.PERMISSION_BIT_MINTER());
    //     target.callSale(
    //         newTokenId,
    //         fixedPriceErc20,
    //         abi.encodeWithSelector(
    //             ERC20CreatorFixedPriceSaleStrategy.setSale.selector,
    //             newTokenId,
    //             ERC20CreatorFixedPriceSaleStrategy.SalesConfig({
    //                 pricePerToken: pricePerToken,
    //                 saleStart: 0,
    //                 saleEnd: type(uint64).max,
    //                 maxTokensPerAddress: 0,
    //                 fundsRecipient: fundsRecipient,
    //                 erc20Address: address(0)
    //             })
    //         )
    //     );
    //     vm.stopPrank();

    //     uint256 totalReward = target.computeTotalReward(numTokens);
    //     uint256 totalValue = (pricePerToken * numTokens) + totalReward;

    //     vm.deal(tokenRecipient, totalValue);

    //     vm.prank(tokenRecipient);
    //     target.mintWithRewards{value: totalValue}(fixedPriceErc20, newTokenId, numTokens, abi.encode(tokenRecipient, ""), address(0));

    //     assertEq(fundsRecipient.balance, 10 ether);
    // }

    // function test_MintedPerRecipientGetter() external {
    //     vm.startPrank(admin);
    //     uint256 newTokenId = target.setupNewToken("https://zora.co/testing/token.json", 10);
    //     target.addPermission(newTokenId, address(fixedPriceErc20), target.PERMISSION_BIT_MINTER());
    //     target.callSale(
    //         newTokenId,
    //         fixedPriceErc20,
    //         abi.encodeWithSelector(
    //             ERC20CreatorFixedPriceSaleStrategy.setSale.selector,
    //             newTokenId,
    //             ERC20CreatorFixedPriceSaleStrategy.SalesConfig({
    //                 pricePerToken: 0 ether,
    //                 saleStart: 0,
    //                 saleEnd: type(uint64).max,
    //                 maxTokensPerAddress: 20,
    //                 fundsRecipient: address(0),
    //                 erc20Address: address(0)
    //             })
    //         )
    //     );
    //     vm.stopPrank();

    //     uint256 numTokens = 10;
    //     uint256 totalReward = target.computeTotalReward(numTokens);

    //     vm.deal(tokenRecipient, totalReward);

    //     vm.prank(tokenRecipient);
    //     target.mintWithRewards{value: totalReward}(fixedPriceErc20, newTokenId, 10, abi.encode(tokenRecipient, ""), address(0));

    //     assertEq(fixedPriceErc20.getMintedPerWallet(address(target), newTokenId, tokenRecipient), 10);
    // }

    function test_ResetSale() external {
        vm.startPrank(admin);
        uint256 newTokenId = target.setupNewToken("https://zora.co/testing/token.json", 10);
        target.addPermission(newTokenId, address(fixedPriceErc20), target.PERMISSION_BIT_MINTER());
        vm.expectEmit(false, false, false, false);
        emit SaleSet(
            address(target),
            newTokenId,
            ERC20CreatorFixedPriceSaleStrategy.SalesConfig({pricePerToken: 0, saleStart: 0, saleEnd: 0, maxTokensPerAddress: 0, fundsRecipient: address(0), erc20Address: address(0)})
        );
        target.callSale(newTokenId, fixedPriceErc20, abi.encodeWithSelector(ERC20CreatorFixedPriceSaleStrategy.resetSale.selector, newTokenId));
        vm.stopPrank();

        ERC20CreatorFixedPriceSaleStrategy.SalesConfig memory sale = fixedPriceErc20.sale(address(target), newTokenId);
        assertEq(sale.pricePerToken, 0);
        assertEq(sale.saleStart, 0);
        assertEq(sale.saleEnd, 0);
        assertEq(sale.maxTokensPerAddress, 0);
        assertEq(sale.fundsRecipient, address(0));
        assertEq(sale.erc20Address, address(0));
    }

    function test_SaleERC20Address() external {
        vm.startPrank(admin);
        uint256 newTokenId = target.setupNewToken("https://zora.co/testing/token.json", 10);
        target.addPermission(newTokenId, address(fixedPriceErc20), target.PERMISSION_BIT_MINTER());
        target.callSale(
            newTokenId,
            fixedPriceErc20,
            abi.encodeWithSelector(
                ERC20CreatorFixedPriceSaleStrategy.setSale.selector,
                newTokenId,
                ERC20CreatorFixedPriceSaleStrategy.SalesConfig({
                    pricePerToken: 0,
                    saleStart: 0,
                    saleEnd: 0,
                    maxTokensPerAddress: 0,
                    fundsRecipient: address(0),
                    erc20Address: address(usdc)
                })
            )
        );
        vm.stopPrank();

        ERC20CreatorFixedPriceSaleStrategy.SalesConfig memory sale = fixedPriceErc20.sale(address(target), newTokenId);
        assertEq(sale.pricePerToken, 0);
        assertEq(sale.saleStart, 0);
        assertEq(sale.saleEnd, 0);
        assertEq(sale.maxTokensPerAddress, 0);
        assertEq(sale.fundsRecipient, address(0));
        assertEq(sale.erc20Address, address(usdc));
    }

    function test_fixedPriceSaleSupportsInterface() public {
        assertTrue(fixedPriceErc20.supportsInterface(0x6890e5b3));
        assertTrue(fixedPriceErc20.supportsInterface(0x01ffc9a7));
        assertFalse(fixedPriceErc20.supportsInterface(0x0));
    }

    function testRevert_CannotSetSaleOfDifferentTokenId() public {
        vm.startPrank(admin);
        uint256 tokenId1 = target.setupNewToken("https://zora.co/testing/token.json", 10);
        uint256 tokenId2 = target.setupNewToken("https://zora.co/testing/token.json", 5);

        target.addPermission(tokenId1, address(fixedPriceErc20), target.PERMISSION_BIT_MINTER());
        target.addPermission(tokenId2, address(fixedPriceErc20), target.PERMISSION_BIT_MINTER());

        vm.expectRevert(abi.encodeWithSignature("Call_TokenIdMismatch()"));
        target.callSale(
            tokenId1,
            fixedPriceErc20,
            abi.encodeWithSelector(
                ERC20CreatorFixedPriceSaleStrategy.setSale.selector,
                tokenId2,
                ERC20CreatorFixedPriceSaleStrategy.SalesConfig({
                    pricePerToken: 1 ether,
                    saleStart: 0,
                    saleEnd: type(uint64).max,
                    maxTokensPerAddress: 0,
                    fundsRecipient: address(0),
                    erc20Address: address(0)
                })
            )
        );
        vm.stopPrank();
    }

    function testRevert_CannotResetSaleOfDifferentTokenId() public {
        vm.startPrank(admin);
        uint256 tokenId1 = target.setupNewToken("https://zora.co/testing/token.json", 10);
        uint256 tokenId2 = target.setupNewToken("https://zora.co/testing/token.json", 5);

        target.addPermission(tokenId1, address(fixedPriceErc20), target.PERMISSION_BIT_MINTER());
        target.addPermission(tokenId2, address(fixedPriceErc20), target.PERMISSION_BIT_MINTER());

        vm.expectRevert(abi.encodeWithSignature("Call_TokenIdMismatch()"));
        target.callSale(tokenId1, fixedPriceErc20, abi.encodeWithSelector(ERC20CreatorFixedPriceSaleStrategy.resetSale.selector, tokenId2));
        vm.stopPrank();
    }
}
