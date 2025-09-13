// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;
import {Test} from "forge-std/Test.sol";
import {IZoraFactory} from "../src/interfaces/IZoraFactory.sol";
import {ZoraFactoryImpl} from "../src/ZoraFactoryImpl.sol";
import {BaseTest} from "./utils/BaseTest.sol";
import {CoinsDeployerBase} from "../src/deployment/CoinsDeployerBase.sol";
import {CoinConfigurationVersions} from "../src/libs/CoinConfigurationVersions.sol";
import {ICoin} from "../src/interfaces/ICoin.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ISwapRouter} from "../src/interfaces/ISwapRouter.sol";
import {IWETH} from "../src/interfaces/IWETH.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {Currency} from "@uniswap/v4-core/src/types/Currency.sol";
import {BuySupplyWithSwapRouterHook} from "../src/hooks/deployment/BuySupplyWithSwapRouterHook.sol";
import {ZoraV4CoinHook} from "../src/hooks/ZoraV4CoinHook.sol";
import {console} from "forge-std/console.sol";
import {IDeployedCoinVersionLookup} from "../src/interfaces/IDeployedCoinVersionLookup.sol";
import {IHooksUpgradeGate} from "../src/interfaces/IHooksUpgradeGate.sol";
import {HooksDeployment} from "../src/libs/HooksDeployment.sol";
import {IHooks} from "@uniswap/v4-core/src/interfaces/IHooks.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {MultiOwnable} from "../src/utils/MultiOwnable.sol";
import {ContentCoin} from "../src/ContentCoin.sol";
import {UniV4SwapHelper} from "../src/libs/UniV4SwapHelper.sol";
import {StateLibrary} from "@uniswap/v4-core/src/libraries/StateLibrary.sol";
import {IZoraV4CoinHook} from "../src/interfaces/IZoraV4CoinHook.sol";
import {PoolStateReader} from "../src/libs/PoolStateReader.sol";
import {LpPosition} from "../src/types/LpPosition.sol";

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

        ZoraFactoryImpl newImpl = new ZoraFactoryImpl(address(coinV4Impl), address(creatorCoinImpl), address(hook), address(zoraHookRegistry));

        vm.prank(factoryProxy.owner());
        factoryProxy.upgradeToAndCall(address(newImpl), "");

        assertEq(factoryProxy.implementation(), address(newImpl));
    }

    function test_cannotUpgradeToMismatchedContractName() public {
        // this test that we cannot upgrade to a contract with a mismatched contract name
        // once we have upgraded to the version that checks the contract name when upgrading
        vm.createSelectFork("base", 29675508);

        factoryProxy = ZoraFactoryImpl(0x777777751622c0d3258f214F9DF38E35BF45baF3);

        ZoraFactoryImpl newImpl = new ZoraFactoryImpl(address(coinV4Impl), address(creatorCoinImpl), address(hook), address(zoraHookRegistry));

        vm.prank(factoryProxy.owner());
        factoryProxy.upgradeToAndCall(address(newImpl), "");

        BadImpl badImpl = new BadImpl();

        vm.prank(factoryProxy.owner());
        vm.expectRevert(abi.encodeWithSelector(IZoraFactory.UpgradeToMismatchedContractName.selector, "ZoraCoinFactory", "BadImpl"));
        factoryProxy.upgradeToAndCall(address(badImpl), "");
    }

    // This fork test needs to be updated after hook registry + new factory is deployed
    // function test_canUpgradeToSameContractName() public {
    //     // this test that we can upgrade to the same contract name, when we have already upgraded to a version that has a contract name
    //     vm.createSelectFork("base", 29675508);

    //     factoryProxy = ZoraFactoryImpl(0x777777751622c0d3258f214F9DF38E35BF45baF3);

    // ZoraFactoryImpl newImpl = new ZoraFactoryImpl(address(coinV4Impl), address(creatorCoinImpl), address(hook), address(zoraHookRegistry));

    //     vm.prank(factoryProxy.owner());
    //     factoryProxy.upgradeToAndCall(address(newImpl), "");

    // ZoraFactoryImpl newImpl2 = new ZoraFactoryImpl(factoryProxy.coinV4Impl(), factoryProxy.creatorCoinImpl(), address(hook), address(zoraHookRegistry));

    //     vm.prank(factoryProxy.owner());
    //     factoryProxy.upgradeToAndCall(address(newImpl2), "");

    //     assertEq(factoryProxy.implementation(), address(newImpl2));
    // }

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
        _swapSomeCurrencyForCoin(ICoin(coinAddress), ZORA, uint128(IERC20(ZORA).balanceOf(trader)), trader);

        // do some swaps to test out
        _swapSomeCoinForCurrency(ICoin(coinAddress), ZORA, uint128(IERC20(coinAddress).balanceOf(trader)), trader);
    }

    address coinVersionLookup = 0x777777751622c0d3258f214F9DF38E35BF45baF3;
    address upgradeGate = 0xD88f6BdD765313CaFA5888C177c325E2C3AbF2D2;

    function _swapSomeCurrencyForCoinAndExpectRevert(ICoin _coin, address currency, uint128 amountIn, address trader) internal {
        uint128 minAmountOut = uint128(0);

        (bytes memory commands, bytes[] memory inputs) = UniV4SwapHelper.buildExactInputSingleSwapCommand(
            currency,
            amountIn,
            address(_coin),
            minAmountOut,
            _coin.getPoolKey(),
            bytes("")
        );

        vm.startPrank(trader);
        UniV4SwapHelper.approveTokenWithPermit2(permit2, address(router), currency, amountIn, uint48(block.timestamp + 1 days));

        // Execute the swap
        uint256 deadline = block.timestamp + 20;
        vm.expectRevert();
        router.execute(commands, inputs, deadline);

        vm.stopPrank();
    }

    function test_canUpgradeBrokenContentCoinAndSwap() public {
        vm.createSelectFork("base", 32613149);

        address trader = 0xf69fEc6d858c77e969509843852178bd24CAd2B6;

        address contentCoin = 0xB9799C839818bF50240CE683363D00c43a2E23b8;

        address creatorCoin = ICoin(contentCoin).currency();

        uint256 amountIn = 0.000111 ether;

        bytes memory creationCode = HooksDeployment.makeHookCreationCode(address(poolManager), coinVersionLookup, new address[](0), upgradeGate);

        (IHooks newHook, ) = HooksDeployment.deployHookWithExistingOrNewSalt(address(this), creationCode, bytes32(0));

        address existingHook = address(ICoin(contentCoin).hooks());

        address[] memory baseImpls = new address[](1);
        baseImpls[0] = existingHook;

        vm.prank(Ownable(upgradeGate).owner());
        IHooksUpgradeGate(upgradeGate).registerUpgradePath(baseImpls, address(newHook));

        vm.prank(MultiOwnable(contentCoin).owners()[0]);
        ContentCoin(contentCoin).migrateLiquidity(address(newHook), "");

        // do some swaps to test out
        _swapSomeCurrencyForCoin(ICoin(contentCoin), creatorCoin, uint128(amountIn), trader);
    }

    function getPositionInfo(
        PoolKey memory key,
        address owner,
        int24 tickLower,
        int24 tickUpper
    ) internal view returns (uint128 liquidity, uint256 feeGrowthInside0LastX128, uint256 feeGrowthInside1LastX128) {
        return StateLibrary.getPositionInfo(poolManager, key.toId(), owner, tickLower, tickUpper, bytes32(0));
    }

    function getLiquidityForPositions(PoolKey memory key, LpPosition[] memory positions) internal view returns (uint128[] memory liquidityForPositions) {
        liquidityForPositions = new uint128[](positions.length);

        for (uint256 i = 0; i < positions.length; i++) {
            (uint128 liquidity, , ) = getPositionInfo(key, address(key.hooks), positions[i].tickLower, positions[i].tickUpper);
            liquidityForPositions[i] = liquidity;
        }
    }

    function getLiquidityForPoolCoin(ICoin coin) internal view returns (uint128[] memory liquidityForPositions) {
        return getLiquidityForPositions(coin.getPoolKey(), IZoraV4CoinHook(address(coin.hooks())).getPoolCoin(coin.getPoolKey()).positions);
    }

    function test_canUpgradeBrokenCreatorCoinAndSwap() public {
        vm.createSelectFork("base", 31872861);

        address trader = 0xf69fEc6d858c77e969509843852178bd24CAd2B6;

        ICoin creatorCoin = ICoin(0x2F03aB8fD97F5874bc3274C296Bb954Ae92EdA34);

        address zora = creatorCoin.currency();

        address existingHook = address(creatorCoin.hooks());

        bytes memory creationCode = HooksDeployment.makeHookCreationCode(address(poolManager), coinVersionLookup, new address[](0), upgradeGate);

        (IHooks newHook, ) = HooksDeployment.deployHookWithExistingOrNewSalt(address(this), creationCode, bytes32(0));

        address[] memory baseImpls = new address[](1);
        baseImpls[0] = existingHook;

        vm.prank(Ownable(upgradeGate).owner());
        IHooksUpgradeGate(upgradeGate).registerUpgradePath(baseImpls, address(newHook));

        LpPosition[] memory beforePositions = IZoraV4CoinHook(address(creatorCoin.hooks())).getPoolCoin(creatorCoin.getPoolKey()).positions;
        PoolKey memory beforeKey = creatorCoin.getPoolKey();

        uint128[] memory beforeLiquidity = getLiquidityForPositions(beforeKey, beforePositions);
        // get before price
        uint160 beforePrice = PoolStateReader.getSqrtPriceX96(creatorCoin.getPoolKey(), poolManager);

        vm.prank(MultiOwnable(address(creatorCoin)).owners()[0]);
        ContentCoin(address(creatorCoin)).migrateLiquidity(address(newHook), "");

        // get liquidity of original positions after migration
        uint128[] memory liquidityOfPositionsAfterMigration = getLiquidityForPositions(beforeKey, beforePositions);

        // there should be no liquidity left in the original positions after migration
        for (uint256 i = 0; i < liquidityOfPositionsAfterMigration.length; i++) {
            assertEq(liquidityOfPositionsAfterMigration[i], 0);
        }

        // get liquidity of new positions after migration
        PoolKey memory afterKey = creatorCoin.getPoolKey();
        LpPosition[] memory afterPositions = IZoraV4CoinHook(address(afterKey.hooks)).getPoolCoin(afterKey).positions;
        uint128[] memory afterLiquidity = getLiquidityForPositions(afterKey, afterPositions);

        for (uint256 i = 0; i < beforeLiquidity.length; i++) {
            // we added any extra liquidity to the last position, so we don't expect it to be the same
            if (i != beforeLiquidity.length - 1) {
                assertApproxEqAbs(beforeLiquidity[i], afterLiquidity[i], 200);
            }
        }

        uint160 afterPrice = PoolStateReader.getSqrtPriceX96(creatorCoin.getPoolKey(), poolManager);

        assertEq(beforePrice, afterPrice);

        // make sure that the new hook has no balance of 0 or 1
        assertApproxEqAbs(creatorCoin.getPoolKey().currency0.balanceOf(address(newHook)), 0, 10);
        assertApproxEqAbs(creatorCoin.getPoolKey().currency1.balanceOf(address(newHook)), 0, 10);

        // now try to swap some currency for the creator coin - it should succeed
        _swapSomeCurrencyForCoin(creatorCoin, zora, uint128(IERC20(zora).balanceOf(trader) / 2), trader);
    }

    function test_canFixBrokenContentCoinAndSwap() public {
        vm.createSelectFork("base", 31835069);

        address trader = 0xf69fEc6d858c77e969509843852178bd24CAd2B6;

        address contentCoin = 0x4E93A01c90f812284F71291a8d1415a904957156;

        address creatorCoin = ICoin(contentCoin).currency();

        uint256 amountIn = IERC20(creatorCoin).balanceOf(trader);

        require(amountIn > 0, "no balance");

        // this swap should revert because the content coin is broken
        _swapSomeCurrencyForCoinAndExpectRevert(ICoin(contentCoin), creatorCoin, uint128(amountIn), trader);

        bytes memory creationCode = HooksDeployment.makeHookCreationCode(address(poolManager), coinVersionLookup, new address[](0), upgradeGate);

        (IHooks newHook, ) = HooksDeployment.deployHookWithExistingOrNewSalt(address(this), creationCode, bytes32(0));

        // etch new hook into the content coin, it shouldn't revert anymore when swapping
        vm.etch(address(ICoin(contentCoin).hooks()), address(newHook).code);

        _swapSomeCurrencyForCoin(ICoin(contentCoin), creatorCoin, uint128(amountIn), trader);
    }
}
