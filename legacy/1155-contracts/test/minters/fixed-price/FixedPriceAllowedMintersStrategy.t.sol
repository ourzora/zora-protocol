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

import {IFixedPriceAllowedMintersStrategy, FixedPriceAllowedMintersStrategy} from "../../../src/minters/fixed-price/FixedPriceAllowedMintersStrategy.sol";

contract FixedPriceAllowedMintersStrategyTest is Test {
    ZoraCreator1155Impl internal targetImpl;
    ZoraCreator1155Impl internal target;
    FixedPriceAllowedMintersStrategy internal fixedPrice;

    address payable internal admin;
    address internal zora;
    address internal tokenRecipient;
    address internal fundsRecipient;
    address[] internal rewardsRecipients;

    address internal allowedMinter;
    address[] internal minters;

    event SaleSet(address indexed mediaContract, uint256 indexed tokenId, FixedPriceAllowedMintersStrategy.SalesConfig salesConfig);
    event MintComment(address indexed sender, address indexed tokenContract, uint256 indexed tokenId, uint256 quantity, string comment);
    event MinterSet(address indexed mediaContract, uint256 indexed tokenId, address indexed minter, bool allowed);

    function setUp() external {
        admin = payable(makeAddr("admin"));
        zora = makeAddr("zora");
        tokenRecipient = makeAddr("tokenRecipient");
        fundsRecipient = makeAddr("fundsRecipient");
        rewardsRecipients = new address[](1);

        allowedMinter = makeAddr("allowedMinter");
        minters = new address[](1);
        minters[0] = allowedMinter;

        targetImpl = new ZoraCreator1155Impl(zora, address(0x1234), address(new ProtocolRewards()), makeAddr("timedSaleStrategy"));
        target = ZoraCreator1155Impl(payable(address(new Zora1155(address(targetImpl)))));

        target.initialize("test", "test", ICreatorRoyaltiesControl.RoyaltyConfiguration(0, 0, address(0)), admin, new bytes[](0));
        fixedPrice = new FixedPriceAllowedMintersStrategy();
    }

    function test_ContractName() external {
        assertEq(fixedPrice.contractName(), "Fixed Price Allowed Minters Strategy");
    }

    function test_ContractURI() external {
        assertEq(fixedPrice.contractURI(), "https://github.com/ourzora/zora-protocol/");
    }

    function test_Version() external {
        assertEq(fixedPrice.contractVersion(), "1.0.1");
    }

    function test_SetSale() external {
        vm.startPrank(admin);

        uint256 newTokenId = target.setupNewToken("https://zora.co/testing/token.json", 10);
        target.addPermission(newTokenId, address(fixedPrice), target.PERMISSION_BIT_MINTER());

        target.callSale(
            newTokenId,
            fixedPrice,
            abi.encodeWithSelector(
                FixedPriceAllowedMintersStrategy.setSale.selector,
                newTokenId,
                IFixedPriceAllowedMintersStrategy.SalesConfig({
                    pricePerToken: 1 ether,
                    saleStart: 0,
                    saleEnd: type(uint64).max,
                    maxTokensPerAddress: 0,
                    fundsRecipient: address(0)
                })
            )
        );

        target.callSale(newTokenId, fixedPrice, abi.encodeWithSelector(IFixedPriceAllowedMintersStrategy.setMinters.selector, newTokenId, minters, true));

        vm.stopPrank();

        bool isMinter = fixedPrice.isMinter(address(target), newTokenId, minters[0]);
        assertTrue(isMinter);

        FixedPriceAllowedMintersStrategy.SalesConfig memory config = fixedPrice.sale(address(target), newTokenId);

        assertEq(config.pricePerToken, 1 ether);
        assertEq(config.saleStart, 0);
        assertEq(config.saleEnd, type(uint64).max);
        assertEq(config.maxTokensPerAddress, 0);
        assertEq(config.fundsRecipient, address(0));

        uint256 numMinted = fixedPrice.getMintedPerWallet(address(target), newTokenId, address(this));
        assertEq(numMinted, 0);
    }

    function test_MintFromAllowedMinter() external {
        vm.startPrank(admin);

        uint256 newTokenId = target.setupNewToken("https://zora.co/testing/token.json", 10);
        target.addPermission(newTokenId, address(fixedPrice), target.PERMISSION_BIT_MINTER());

        target.callSale(
            newTokenId,
            fixedPrice,
            abi.encodeWithSelector(
                FixedPriceAllowedMintersStrategy.setSale.selector,
                newTokenId,
                IFixedPriceAllowedMintersStrategy.SalesConfig({
                    pricePerToken: 1 ether,
                    saleStart: 0,
                    saleEnd: type(uint64).max,
                    maxTokensPerAddress: 0,
                    fundsRecipient: address(0)
                })
            )
        );

        target.callSale(newTokenId, fixedPrice, abi.encodeWithSelector(IFixedPriceAllowedMintersStrategy.setMinters.selector, newTokenId, minters, true));

        vm.stopPrank();

        uint256 numTokens = 10;
        uint256 totalReward = target.computeTotalReward(target.mintFee(), numTokens);
        uint256 totalValue = (1 ether * numTokens) + totalReward;

        vm.deal(allowedMinter, totalValue);

        vm.startPrank(allowedMinter);
        target.mint{value: totalValue}(fixedPrice, newTokenId, 10, rewardsRecipients, abi.encode(tokenRecipient, "test comment"));

        assertEq(target.balanceOf(tokenRecipient, newTokenId), 10);
        assertEq(address(target).balance, 10 ether);

        uint256 numMinted = fixedPrice.getMintedPerWallet(address(target), newTokenId, allowedMinter); // We don't record the limit + num minted for this module
        assertEq(numMinted, 0);

        vm.stopPrank();
    }

    function test_MintFromAllowedMinterContractWide() external {
        vm.startPrank(admin);

        uint256 newTokenId = target.setupNewToken("https://zora.co/testing/token.json", 10);
        uint256 newNewTokenId = target.setupNewToken("https://zora.co/testing/token.json", 20);

        target.addPermission(0, address(fixedPrice), target.PERMISSION_BIT_MINTER());
        target.addPermission(newTokenId, address(fixedPrice), target.PERMISSION_BIT_MINTER());
        target.addPermission(newNewTokenId, address(fixedPrice), target.PERMISSION_BIT_MINTER());

        target.callSale(
            newTokenId,
            fixedPrice,
            abi.encodeWithSelector(
                FixedPriceAllowedMintersStrategy.setSale.selector,
                newTokenId,
                IFixedPriceAllowedMintersStrategy.SalesConfig({
                    pricePerToken: 1 ether,
                    saleStart: 0,
                    saleEnd: type(uint64).max,
                    maxTokensPerAddress: 0,
                    fundsRecipient: address(0)
                })
            )
        );

        target.callSale(
            newNewTokenId,
            fixedPrice,
            abi.encodeWithSelector(
                FixedPriceAllowedMintersStrategy.setSale.selector,
                newNewTokenId,
                IFixedPriceAllowedMintersStrategy.SalesConfig({
                    pricePerToken: 1 ether,
                    saleStart: 0,
                    saleEnd: type(uint64).max,
                    maxTokensPerAddress: 0,
                    fundsRecipient: address(0)
                })
            )
        );

        target.callSale(0, fixedPrice, abi.encodeWithSelector(FixedPriceAllowedMintersStrategy.setMinters.selector, 0, minters, true));

        vm.stopPrank();

        uint256 numTokens = 10;
        uint256 totalReward = target.computeTotalReward(target.mintFee(), numTokens);
        uint256 totalValue = (1 ether * numTokens) + totalReward;
        vm.deal(allowedMinter, totalValue * 2);

        vm.startPrank(allowedMinter);
        target.mint{value: totalValue}(fixedPrice, newTokenId, 10, rewardsRecipients, abi.encode(tokenRecipient, "test comment"));
        target.mint{value: totalValue}(fixedPrice, newNewTokenId, 10, rewardsRecipients, abi.encode(tokenRecipient, "test comment"));

        assertEq(target.balanceOf(tokenRecipient, newTokenId), 10);
        assertEq(target.balanceOf(tokenRecipient, newNewTokenId), 10);
        assertEq(address(target).balance, 20 ether);

        vm.stopPrank();
    }

    function testRevert_MinterNotAllowed() external {
        vm.startPrank(admin);

        uint256 newTokenId = target.setupNewToken("https://zora.co/testing/token.json", 10);
        target.addPermission(newTokenId, address(fixedPrice), target.PERMISSION_BIT_MINTER());

        target.callSale(
            newTokenId,
            fixedPrice,
            abi.encodeWithSelector(
                FixedPriceAllowedMintersStrategy.setSale.selector,
                newTokenId,
                IFixedPriceAllowedMintersStrategy.SalesConfig({
                    pricePerToken: 1 ether,
                    saleStart: 0,
                    saleEnd: type(uint64).max,
                    maxTokensPerAddress: 0,
                    fundsRecipient: address(0)
                })
            )
        );

        target.callSale(newTokenId, fixedPrice, abi.encodeWithSelector(FixedPriceAllowedMintersStrategy.setMinters.selector, newTokenId, minters, true));
        vm.stopPrank();

        uint256 numTokens = 10;
        uint256 totalReward = target.computeTotalReward(target.mintFee(), numTokens);
        uint256 totalValue = (1 ether * numTokens) + totalReward;
        vm.deal(allowedMinter, totalValue);

        vm.expectRevert(abi.encodeWithSignature("ONLY_MINTER()"));
        target.mint{value: totalReward}(fixedPrice, newTokenId, 10, rewardsRecipients, abi.encode(tokenRecipient, "test comment"));
    }

    function test_MintersSetEvents() external {
        vm.startPrank(admin);

        uint256 newTokenId = target.setupNewToken("https://zora.co/testing/token.json", 10);
        target.addPermission(newTokenId, address(fixedPrice), target.PERMISSION_BIT_MINTER());

        target.callSale(
            newTokenId,
            fixedPrice,
            abi.encodeWithSelector(
                FixedPriceAllowedMintersStrategy.setSale.selector,
                newTokenId,
                IFixedPriceAllowedMintersStrategy.SalesConfig({
                    pricePerToken: 1 ether,
                    saleStart: 0,
                    saleEnd: type(uint64).max,
                    maxTokensPerAddress: 0,
                    fundsRecipient: address(0)
                })
            )
        );

        vm.expectEmit(true, true, true, true);
        emit MinterSet(address(target), newTokenId, allowedMinter, true);
        target.callSale(newTokenId, fixedPrice, abi.encodeWithSelector(FixedPriceAllowedMintersStrategy.setMinters.selector, newTokenId, minters, true));

        vm.expectEmit(true, true, true, true);
        emit MinterSet(address(target), newTokenId, allowedMinter, false);
        target.callSale(newTokenId, fixedPrice, abi.encodeWithSelector(FixedPriceAllowedMintersStrategy.setMinters.selector, newTokenId, minters, false));

        vm.stopPrank();
    }
}
