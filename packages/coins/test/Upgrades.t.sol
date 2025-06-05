// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;
import {Test} from "forge-std/Test.sol";
import {IZoraFactory} from "../src/interfaces/IZoraFactory.sol";
import {ZoraFactoryImpl} from "../src/ZoraFactoryImpl.sol";
import {BaseTest} from "./utils/BaseTest.sol";
import {CoinsDeployerBase} from "../src/deployment/CoinsDeployerBase.sol";
import {CoinConfigurationVersions} from "../src/libs/CoinConfigurationVersions.sol";
import {ICoinV4} from "../src/interfaces/ICoinV4.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ISwapRouter} from "../src/interfaces/ISwapRouter.sol";
import {IWETH} from "../src/interfaces/IWETH.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {Currency} from "@uniswap/v4-core/src/types/Currency.sol";

import {console} from "forge-std/console.sol";

contract BadImpl {
    function contractName() public pure returns (string memory) {
        return "BadImpl";
    }
}

contract UpgradesTest is BaseTest, CoinsDeployerBase {
    ZoraFactoryImpl public factoryProxy;

    function test_canUpgradeFromVersionWithoutContractName() public {
        // this test that we can upgrade from the current version, which doesn't have a contract name
        vm.createSelectFork("base", 29675508);

        factoryProxy = ZoraFactoryImpl(0x777777751622c0d3258f214F9DF38E35BF45baF3);

        ZoraFactoryImpl newImpl = new ZoraFactoryImpl(factoryProxy.coinImpl(), address(coinV4Impl));

        vm.prank(factoryProxy.owner());
        factoryProxy.upgradeToAndCall(address(newImpl), "");

        assertEq(factoryProxy.implementation(), address(newImpl));
    }

    function test_cannotUpgradeToMismatchedContractName() public {
        // this test that we cannot upgrade to a contract with a mismatched contract name
        // once we have upgraded to the version that checks the contract name when upgrading
        vm.createSelectFork("base", 29675508);

        factoryProxy = ZoraFactoryImpl(0x777777751622c0d3258f214F9DF38E35BF45baF3);

        ZoraFactoryImpl newImpl = new ZoraFactoryImpl(factoryProxy.coinImpl(), address(coinV4Impl));

        vm.prank(factoryProxy.owner());
        factoryProxy.upgradeToAndCall(address(newImpl), "");

        BadImpl badImpl = new BadImpl();

        vm.prank(factoryProxy.owner());
        vm.expectRevert(abi.encodeWithSelector(IZoraFactory.UpgradeToMismatchedContractName.selector, "ZoraCoinFactory", "BadImpl"));
        factoryProxy.upgradeToAndCall(address(badImpl), "");
    }

    function test_canUpgradeToSameContractName() public {
        // this test that we can upgrade to the same contract name, when we have already upgraded to a version that has a contract name
        vm.createSelectFork("base", 29675508);

        factoryProxy = ZoraFactoryImpl(0x777777751622c0d3258f214F9DF38E35BF45baF3);

        ZoraFactoryImpl newImpl = new ZoraFactoryImpl(factoryProxy.coinImpl(), address(coinV4Impl));

        vm.prank(factoryProxy.owner());
        factoryProxy.upgradeToAndCall(address(newImpl), "");

        ZoraFactoryImpl newImpl2 = new ZoraFactoryImpl(factoryProxy.coinImpl(), factoryProxy.coinV4Impl());

        vm.prank(factoryProxy.owner());
        factoryProxy.upgradeToAndCall(address(newImpl2), "");

        assertEq(factoryProxy.implementation(), address(newImpl2));
    }

    function test_canUpgradeAndSwap() public {
        vm.createSelectFork("base");

        factoryProxy = ZoraFactoryImpl(0x777777751622c0d3258f214F9DF38E35BF45baF3);

        CoinsDeployment memory deployment = readDeployment();

        vm.prank(factoryProxy.owner());
        factoryProxy.upgradeToAndCall(deployment.zoraFactoryImpl, "");

        // deploy a v4 coin

        bytes memory poolConfig = CoinConfigurationVersions.defaultDopplerMultiCurveUniV4(ZORA);

        uint128 amountIn = 1 ether;

        // build weth to usdc swap
        ISwapRouter.ExactInputSingleParams memory params = ISwapRouter.ExactInputSingleParams({
            tokenIn: WETH_ADDRESS,
            tokenOut: ZORA,
            fee: 3000,
            recipient: deployment.zoraV4CoinHook,
            amountIn: amountIn,
            amountOutMinimum: 0,
            sqrtPriceLimitX96: 0
        });

        address trader = 0xC077e4cC02fa01A5b7fAca1acE9BBe9f5ac5Af9F;

        vm.startPrank(trader);
        vm.deal(trader, amountIn);
        IWETH(WETH_ADDRESS).deposit{value: amountIn}();
        IWETH(WETH_ADDRESS).approve(address(swapRouter), amountIn);

        (address coinAddress, ) = factoryProxy.deploy(
            users.creator,
            _getDefaultOwners(),
            "https://test.com",
            "Testcoin",
            "TEST",
            poolConfig,
            users.platformReferrer,
            deployment.zoraV4CoinHook,
            abi.encode(params),
            keccak256("test")
        );

        // do some swaps to test out
        _swapSomeCurrencyForCoin(ICoinV4(coinAddress), ZORA, uint128(IERC20(ZORA).balanceOf(trader)), trader);

        // do some swaps to test out
        _swapSomeCoinForCurrency(ICoinV4(coinAddress), ZORA, uint128(IERC20(coinAddress).balanceOf(trader)), trader);
    }

    function test_realSwapUsingCurrentCode() external {
        bytes[] memory inputs = new bytes[](5);

        vm.createSelectFork("base", 31138268);

        address trader = vm.parseAddress("0xa3c881f39972925d865b300bcd65e72a6222c10a");

        ICoinV4 coin = ICoinV4(vm.parseAddress("0xca1de5b8e8336326d5749fde43e245285cd1daf1"));

        PoolKey memory key = coin.getPoolKey();

        address[] memory trustedMessageSenders = new address[](0);
        deployCodeTo(
            "ZoraV4CoinHook.sol:ZoraV4CoinHook",
            abi.encode(V4_POOL_MANAGER, 0x3d7A3f3351855e135CF89AB412A7C2AA449f9296, trustedMessageSenders),
            address(coin.hooks())
        );

        _swapSomeCurrencyForCoin(coin, ZORA, uint128(IERC20(ZORA).balanceOf(trader)), trader);
    }
}
