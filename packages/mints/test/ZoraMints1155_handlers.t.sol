// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "forge-std/Test.sol";

import {BaseRedeemHandler} from "../src/BaseRedeemHandler.sol";
import {IZoraMints1155, IZoraMints1155Errors} from "../src/interfaces/IZoraMints1155.sol";
import {ZoraMints1155} from "../src/ZoraMints1155.sol";
import {ZoraMintsManagerImpl} from "../src/ZoraMintsManagerImpl.sol";
import {ZoraMintsFixtures} from "./fixtures/ZoraMintsFixtures.sol";
import {TokenConfig} from "../src/ZoraMintsTypes.sol";
import {IRedeemHandler} from "../src/interfaces/IRedeemHandler.sol";
import {MockERC20} from "./mocks/MockERC20.sol";
import {IERC165} from "@openzeppelin/contracts/utils/introspection/IERC165.sol";

contract RedeemHookMock is BaseRedeemHandler {
    constructor(IZoraMints1155 zoraMints) BaseRedeemHandler(zoraMints) {}

    bool private reject;
    uint256 private redeemReturnValue;

    function setReject(bool _reject) external {
        reject = _reject;
    }

    function setRedeemReturnValue(uint256 _value) external {
        redeemReturnValue = _value;
    }

    function handleRedeemEth(address redeemer, uint tokenId, uint quantity, address recipient) external payable override onlyMints {
        if (reject) revert("Reject");
    }

    function handleRedeemErc20(uint256 valueToRedeem, address redeemer, uint tokenId, uint quantity, address recipient) external view override onlyMints {
        if (reject) revert("Reject");
    }
}

contract BadRedeemHandler is IERC165 {
    function supportsInterface(bytes4) external pure override returns (bool) {
        return false;
    }
}

contract ZoraMints1155HandlersTest is Test {
    address admin = makeAddr("admin");
    address proxyAdmin = makeAddr("proxyAdmin");
    address redeemRecipient = makeAddr("redeemRecipient");
    address collector;
    uint256 collectorPrivateKey;

    ZoraMints1155 mints;

    uint256 initialTokenId = 995;
    uint256 initialTokenPrice = 4.32 ether;

    ZoraMintsManagerImpl mintsManager;

    function setUp() external {
        (collector, collectorPrivateKey) = makeAddrAndKey("collector");
        (, mints, mintsManager) = ZoraMintsFixtures.setupMintsProxyWithMockPreminter(proxyAdmin, admin, initialTokenId, initialTokenPrice);
    }

    function test_whenRedeemHandler_whenEth_callsHandleRedeemEthOnHandler_withValueOfRedemption() external {
        uint256 tokenPrice = 2 ether;
        uint256 tokenId = 5;

        IRedeemHandler redeemHandler = new RedeemHookMock(mints);

        TokenConfig memory tokenConfig = TokenConfig({price: tokenPrice, tokenAddress: address(0), redeemHandler: address(redeemHandler)});

        // setup the token
        vm.prank(admin);
        mintsManager.createToken(tokenId, tokenConfig, true);

        // mint some tokens with eth
        uint256 quantityToMint = 7;

        uint256 mintPrice = mintsManager.getEthPrice() * quantityToMint;

        vm.deal(collector, mintPrice);
        vm.prank(collector);
        mintsManager.mintWithEth{value: mintPrice}(quantityToMint, collector);

        uint256 quantityToRedeem = 3;

        // redeem handler's handleRedeem should be called with the full redeem value for the payable value
        vm.expectCall(
            address(redeemHandler),
            quantityToRedeem * tokenPrice,
            abi.encodeCall(IRedeemHandler.handleRedeemEth, (collector, tokenId, quantityToRedeem, redeemRecipient))
        );

        vm.prank(collector);
        uint256 redemptionValue = mints.redeem(tokenId, quantityToRedeem, redeemRecipient).valueRedeemed;

        // redeem should return the redemption value returned from the handler
        assertEq(redemptionValue, quantityToRedeem * tokenPrice);
    }

    function test_whenRedeemHandler_whenErc20_callsHandleRedeemErc20OnHandler_andTransfersErc20ToHandler() external {
        uint256 tokenPrice = 100_000;
        uint256 tokenId = 5;

        MockERC20 erc20 = new MockERC20("", "");

        IRedeemHandler redeemHandler = new RedeemHookMock(mints);

        TokenConfig memory tokenConfig = TokenConfig({price: tokenPrice, tokenAddress: address(erc20), redeemHandler: address(redeemHandler)});

        // setup the token
        vm.prank(admin);
        mintsManager.createToken(tokenId, tokenConfig, true);

        // mint some tokens with eth
        uint256 quantityToMint = 7;

        uint256 mintPrice = tokenPrice * quantityToMint;

        vm.startPrank(collector);
        erc20.mint(mintPrice);
        erc20.approve(address(mintsManager), mintPrice);
        mintsManager.mintWithERC20(address(erc20), quantityToMint, collector);

        uint256 quantityToRedeem = 3;

        // redeem handler's handleRedeem should be called with the full redeem value for the payable value
        vm.expectCall(
            address(redeemHandler),
            0,
            abi.encodeCall(IRedeemHandler.handleRedeemErc20, (quantityToRedeem * tokenPrice, collector, tokenId, quantityToRedeem, redeemRecipient))
        );

        uint256 redemptionValue = mints.redeem(tokenId, quantityToRedeem, redeemRecipient).valueRedeemed;

        // redeem should return the redemption value returned from the handler
        assertEq(redemptionValue, quantityToRedeem * tokenPrice);

        // redeem handler should hold balance of erc20s
        assertEq(erc20.balanceOf(address(redeemHandler)), quantityToRedeem * tokenPrice);
    }

    function test_createToken_shouldRevertWhen_redeemHandler_notARedeemHandler() external {
        BadRedeemHandler badRedeemHandler = new BadRedeemHandler();

        TokenConfig memory tokenConfig = TokenConfig({price: 1 ether, tokenAddress: address(0), redeemHandler: address(badRedeemHandler)});

        // setup the token
        vm.prank(admin);
        vm.expectRevert(abi.encodeWithSelector(IZoraMints1155Errors.NotARedeemHandler.selector, address(badRedeemHandler)));
        mintsManager.createToken(100, tokenConfig, true);
    }
}
