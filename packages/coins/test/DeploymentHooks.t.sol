// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {BaseTest} from "./utils/BaseTest.sol";
import {BuySupplyWithSwapRouterHook} from "../src/hooks/deployment/BuySupplyWithSwapRouterHook.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IUniswapV3Pool} from "../src/interfaces/IUniswapV3Pool.sol";
import {CoinConfigurationVersions} from "../src/libs/CoinConfigurationVersions.sol";
import {IERC165} from "@openzeppelin/contracts/utils/introspection/IERC165.sol";
import {ICoin} from "../src/interfaces/ICoin.sol";
import {IHasAfterCoinDeploy} from "../src/hooks/deployment/BaseCoinDeployHook.sol";
import {IZoraFactory} from "../src/interfaces/IZoraFactory.sol";
import {ISwapRouter} from "../src/interfaces/ISwapRouter.sol";
import {CoinConstants} from "../src/libs/CoinConstants.sol";
import {ContentCoin} from "../src/ContentCoin.sol";

// Create a fake hook that doesn't support the IHasAfterCoinDeploy interface
contract FakeHookNoInterface {
    function supportsInterface(bytes4) external pure returns (bool) {
        return false; // Always returns false, doesn't support any interface
    }
}

contract DeploymentsHooksTest is BaseTest {
    address constant zora = 0x1111111111166b7FE7bd91427724B487980aFc69;
    BuySupplyWithSwapRouterHook buySupplyWithSwapRouterHook;

    function _generateDefaultPoolConfig(address currency) internal pure returns (bytes memory) {
        return _generatePoolConfig(currency);
    }

    function setUp() public override {
        super.setUpWithBlockNumber(30267794);

        buySupplyWithSwapRouterHook = new BuySupplyWithSwapRouterHook(factory, address(swapRouter), address(V4_POOL_MANAGER));
    }

    function _deployWithHook(address _hook, bytes memory hookData, address currency) internal returns (address, bytes memory) {
        bytes memory poolConfig = _generateDefaultPoolConfig(currency);
        return
            factory.deployWithHook(
                users.creator,
                _getDefaultOwners(),
                "https://test.com",
                "Testcoin",
                "TEST",
                poolConfig,
                users.platformReferrer,
                address(_hook),
                hookData
            );
    }

    function _encodeAfterCoinDeploy(address buyRecipient, bytes memory swapRouterCall) internal pure returns (bytes memory) {
        return abi.encode(buyRecipient, swapRouterCall);
    }

    function _encodeExactInputSingle(address buyRecipient, ISwapRouter.ExactInputSingleParams memory params) internal pure returns (bytes memory) {
        return _encodeAfterCoinDeploy(buyRecipient, abi.encodeWithSelector(ISwapRouter.exactInputSingle.selector, params));
    }

    function _encodeExactInput(address buyRecipient, ISwapRouter.ExactInputParams memory params) internal pure returns (bytes memory) {
        return _encodeAfterCoinDeploy(buyRecipient, abi.encodeWithSelector(ISwapRouter.exactInput.selector, params));
    }

    function test_buySupplyWithEthUsingV4Hook_withExactInputMultiHop(uint256 initialOrderSize) public {
        vm.assume(initialOrderSize > CoinConstants.MIN_ORDER_SIZE);
        vm.assume(initialOrderSize < 1 ether);

        vm.deal(users.creator, initialOrderSize);

        // lets try weth to usdc to zora

        uint24 poolFee = 3000;

        bytes memory hookData = _encodeExactInput(
            users.creator,
            ISwapRouter.ExactInputParams({
                path: abi.encodePacked(address(weth), poolFee, USDC_ADDRESS, poolFee, zora),
                recipient: address(buySupplyWithSwapRouterHook),
                amountIn: initialOrderSize,
                amountOutMinimum: 0
            })
        );

        bytes memory poolConfig = CoinConfigurationVersions.defaultDopplerMultiCurveUniV4(zora);

        vm.prank(users.creator);
        (address coinAddress, bytes memory hookDataOut) = factory.deployWithHook{value: initialOrderSize}(
            users.creator,
            _getDefaultOwners(),
            "https://test.com",
            "Testcoin",
            "TEST",
            poolConfig,
            users.platformReferrer,
            address(buySupplyWithSwapRouterHook),
            hookData
        );

        coinV4 = ContentCoin(payable(coinAddress));

        (uint256 amountCurrency, uint256 coinsPurchased) = abi.decode(hookDataOut, (uint256, uint256));

        assertEq(coinV4.currency(), zora, "currency");
        assertGt(amountCurrency, 0, "amountCurrency > 0");
        assertGt(coinsPurchased, 0, "coinsPurchased > 0");
        assertEq(coinV4.balanceOf(users.creator), CoinConstants.CREATOR_LAUNCH_REWARD + coinsPurchased, "balanceOf creator");
        // assertGt(IERC20(zora).balanceOf(address(pool)), 0, "Pool ZORA balance");
    }

    function test_buySupplyWithEthUsingV3Hook_revertsWhenBadCall() public {
        vm.deal(users.creator, 0.0001 ether);

        uint24 poolFee = 3000;

        // exact output single is not supported
        bytes memory hookData = _encodeAfterCoinDeploy(
            users.creator,
            abi.encodeWithSelector(
                ISwapRouter.exactOutputSingle.selector,
                ISwapRouter.ExactOutputParams({
                    path: abi.encodePacked(address(weth), poolFee, USDC_ADDRESS, poolFee, zora),
                    recipient: address(buySupplyWithSwapRouterHook),
                    amountOut: 0.0001 ether,
                    amountInMaximum: 0
                })
            )
        );

        vm.prank(users.creator);
        vm.expectRevert(BuySupplyWithSwapRouterHook.InvalidSwapRouterCall.selector);
        factory.deployWithHook{value: 0.0001 ether}(
            users.creator,
            _getDefaultOwners(),
            "https://test.com",
            "Testcoin",
            "TEST",
            _generateDefaultPoolConfig(zora),
            users.platformReferrer,
            address(buySupplyWithSwapRouterHook),
            hookData
        );
    }

    function test_buySupplyWithEthUsingV3Hook_revertsWhenHookNotRecipient() public {
        uint256 initialOrderSize = 0.0001 ether;
        vm.deal(users.creator, initialOrderSize);

        bytes memory hookData = _encodeExactInputSingle(
            users.creator,
            ISwapRouter.ExactInputSingleParams({
                tokenIn: address(weth),
                tokenOut: zora,
                fee: 3000,
                recipient: address(users.creator),
                amountIn: initialOrderSize,
                amountOutMinimum: 0,
                sqrtPriceLimitX96: 0
            })
        );

        vm.prank(users.creator);
        vm.expectRevert(BuySupplyWithSwapRouterHook.Erc20NotReceived.selector);
        factory.deployWithHook{value: initialOrderSize}(
            users.creator,
            _getDefaultOwners(),
            "https://test.com",
            "Testcoin",
            "TEST",
            _generateDefaultPoolConfig(zora),
            users.platformReferrer,
            address(buySupplyWithSwapRouterHook),
            hookData
        );
    }

    function test_deployWithHook_revertsWhenEthAndNoHook() public {
        uint256 initialOrderSize = 0.0001 ether;
        vm.deal(users.creator, initialOrderSize);

        vm.prank(users.creator);
        vm.expectRevert(IZoraFactory.EthTransferInvalid.selector);
        factory.deployWithHook{value: initialOrderSize}(
            users.creator,
            _getDefaultOwners(),
            "https://test.com",
            "Testcoin",
            "TEST",
            _generateDefaultPoolConfig(zora),
            users.platformReferrer,
            address(0),
            ""
        );
    }

    function test_invalidHookReverts() public {
        // Deploy a fake hook that doesn't support the IHasAfterCoinDeploy interface
        FakeHookNoInterface fakeHook = new FakeHookNoInterface();

        bytes memory hookData = "";

        // Expect the transaction to revert with InvalidHook error
        vm.expectRevert(IZoraFactory.InvalidHook.selector);
        vm.prank(users.creator);
        _deployWithHook(address(fakeHook), hookData, zora);
    }

    function test_noHookWorksAsNormal() public {
        // Expect the transaction to revert with InvalidHook error
        vm.prank(users.creator);
        _deployWithHook(address(0), bytes(""), zora);
    }
}
