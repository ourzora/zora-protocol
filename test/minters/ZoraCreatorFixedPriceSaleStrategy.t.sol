// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import "forge-std/Test.sol";
import {ZoraCreator1155Impl} from "../../src/nft/ZoraCreator1155Impl.sol";
import {ZoraCreator1155Proxy} from "../../src/proxies/ZoraCreator1155Proxy.sol";
import {IZoraCreator1155} from "../../src/interfaces/IZoraCreator1155.sol";
import {IRenderer1155} from "../../src/interfaces/IRenderer1155.sol";
import {ICreatorRoyaltiesControl} from "../../src/interfaces/ICreatorRoyaltiesControl.sol";
import {IZoraCreator1155Factory} from "../../src/interfaces/IZoraCreator1155Factory.sol";
import {ZoraCreatorFixedPriceSaleStrategy} from "../../src/minters/fixed-price/ZoraCreatorFixedPriceSaleStrategy.sol";

contract ZoraCreator1155Test is Test {
    ZoraCreator1155Impl internal target;
    ZoraCreatorFixedPriceSaleStrategy internal fixedPrice;
    address internal admin = address(0x999);

    function setUp() external {
        bytes[] memory emptyData = new bytes[](0);
        ZoraCreator1155Impl targetImpl = new ZoraCreator1155Impl( 0, address(0));
        ZoraCreator1155Proxy proxy = new ZoraCreator1155Proxy(address(targetImpl));
        target = ZoraCreator1155Impl(address(proxy));
        target.initialize("test", ICreatorRoyaltiesControl.RoyaltyConfiguration(0, address(0)), admin, emptyData);
        fixedPrice = new ZoraCreatorFixedPriceSaleStrategy();
    }

    function test_setupPurchase() external {
        vm.startPrank(admin);
        uint256 newTokenId = target.setupNewToken("https://zora.co/testing/token.json", 10);
        target.addPermission(newTokenId, address(fixedPrice), target.PERMISSION_BIT_MINTER());
        target.callSale(
            newTokenId,
            fixedPrice,
            abi.encodeWithSelector(
                ZoraCreatorFixedPriceSaleStrategy.setupSale.selector,
                newTokenId,
                ZoraCreatorFixedPriceSaleStrategy.SalesConfig({
                    pricePerToken: 1 ether,
                    saleStart: 0,
                    saleEnd: type(uint64).max,
                    maxTokensPerTransaction: 0,
                    maxTokensPerAddress: 0,
                    fundsRecipient: address(0)
                })
            )
        );
        vm.stopPrank();

        address tokenRecipient = address(322);
        vm.deal(tokenRecipient, 20 ether);

        vm.startPrank(tokenRecipient);
        target.purchase{value: 10 ether}(fixedPrice, newTokenId, 10, abi.encode(tokenRecipient));

        assertEq(target.balanceOf(tokenRecipient, newTokenId), 10);
        assertEq(address(target).balance, 10 ether);

        vm.stopPrank();
    }
}
