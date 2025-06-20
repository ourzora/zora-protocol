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
import {BuySupplyWithSwapRouterHook} from "../src/hooks/deployment/BuySupplyWithSwapRouterHook.sol";
import {ContentCoinHook} from "../src/hooks/ContentCoinHook.sol";
import {console} from "forge-std/console.sol";
import {IDeployedCoinVersionLookup} from "../src/interfaces/IDeployedCoinVersionLookup.sol";
import {IHooksUpgradeGate} from "../src/interfaces/IHooksUpgradeGate.sol";
import {HooksDeployment} from "../src/libs/HooksDeployment.sol";
import {IHooks} from "@uniswap/v4-core/src/interfaces/IHooks.sol";

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

        ZoraFactoryImpl newImpl = new ZoraFactoryImpl(
            factoryProxy.coinImpl(),
            address(coinV4Impl),
            address(creatorCoinImpl),
            address(contentCoinHook),
            address(creatorCoinHook)
        );

        vm.prank(factoryProxy.owner());
        factoryProxy.upgradeToAndCall(address(newImpl), "");

        assertEq(factoryProxy.implementation(), address(newImpl));
    }

    function test_cannotUpgradeToMismatchedContractName() public {
        // this test that we cannot upgrade to a contract with a mismatched contract name
        // once we have upgraded to the version that checks the contract name when upgrading
        vm.createSelectFork("base", 29675508);

        factoryProxy = ZoraFactoryImpl(0x777777751622c0d3258f214F9DF38E35BF45baF3);

        ZoraFactoryImpl newImpl = new ZoraFactoryImpl(
            factoryProxy.coinImpl(),
            address(coinV4Impl),
            address(creatorCoinImpl),
            address(contentCoinHook),
            address(creatorCoinHook)
        );

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

        ZoraFactoryImpl newImpl = new ZoraFactoryImpl(
            factoryProxy.coinImpl(),
            address(coinV4Impl),
            address(creatorCoinImpl),
            address(contentCoinHook),
            address(creatorCoinHook)
        );

        vm.prank(factoryProxy.owner());
        factoryProxy.upgradeToAndCall(address(newImpl), "");

        ZoraFactoryImpl newImpl2 = new ZoraFactoryImpl(
            factoryProxy.coinImpl(),
            factoryProxy.coinV4Impl(),
            factoryProxy.creatorCoinImpl(),
            address(contentCoinHook),
            address(creatorCoinHook)
        );

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

        address buySupplyWithSwapRouterHook = deployment.buySupplyWithSwapRouterHook;

        // build weth to usdc swap
        bytes memory call = abi.encodeWithSelector(
            ISwapRouter.exactInputSingle.selector,
            ISwapRouter.ExactInputSingleParams({
                tokenIn: WETH_ADDRESS,
                tokenOut: ZORA,
                fee: 3000,
                recipient: buySupplyWithSwapRouterHook,
                amountIn: amountIn,
                amountOutMinimum: 0,
                sqrtPriceLimitX96: 0
            })
        );

        address buyRecipient = makeAddr("buyRecipient");

        address trader = 0xC077e4cC02fa01A5b7fAca1acE9BBe9f5ac5Af9F;

        vm.startPrank(trader);
        vm.deal(trader, amountIn);

        (address coinAddress, ) = factoryProxy.deploy{value: amountIn}(
            users.creator,
            _getDefaultOwners(),
            "https://test.com",
            "Testcoin",
            "TEST",
            poolConfig,
            users.platformReferrer,
            buySupplyWithSwapRouterHook,
            abi.encode(buyRecipient, call),
            keccak256("test")
        );

        // do some swaps to test out
        _swapSomeCurrencyForCoin(ICoinV4(coinAddress), ZORA, uint128(IERC20(ZORA).balanceOf(trader)), trader);

        // do some swaps to test out
        _swapSomeCoinForCurrency(ICoinV4(coinAddress), ZORA, uint128(IERC20(coinAddress).balanceOf(trader)), trader);
    }

    function test_canSwapForJacob() public {
        vm.createSelectFork("base", 31835069);

        address trader = 0xf69fEc6d858c77e969509843852178bd24CAd2B6;

        address contentCoin = 0x4E93A01c90f812284F71291a8d1415a904957156;

        address creatorCoin = ICoinV4(contentCoin).currency();

        uint256 amountIn = IERC20(creatorCoin).balanceOf(trader);

        address coinVersionLookup = 0x777777751622c0d3258f214F9DF38E35BF45baF3;
        address upgradeGate = 0xD88f6BdD765313CaFA5888C177c325E2C3AbF2D2;

        bytes memory creationCode = HooksDeployment.contentCoinCreationCode(address(poolManager), coinVersionLookup, new address[](0), upgradeGate);

        (IHooks hookCopy, ) = HooksDeployment.deployHookWithExistingOrNewSalt(address(this), creationCode, bytes32(0));

        vm.etch(0xd3D133469ADC85e01A4887404D8AC12d630e9040, address(hookCopy).code);

        console.log("currency 0", Currency.unwrap(ICoinV4(contentCoin).getPoolKey().currency0));
        console.log("currency 1", Currency.unwrap(ICoinV4(contentCoin).getPoolKey().currency1));

        // do some swaps to test out
        _swapSomeCurrencyForCoin(ICoinV4(contentCoin), creatorCoin, uint128(amountIn), trader);
    }
}
