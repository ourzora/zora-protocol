// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {MockERC20} from "./mocks/MockERC20.sol";
import {BaseTest} from "./utils/BaseTest.sol";
import {HooksDeployment} from "../src/libs/HooksDeployment.sol";
import {IHooks} from "@uniswap/v4-core/src/interfaces/IHooks.sol";
import {IUpgradeableV4Hook, IUpgradeableDestinationV4Hook, BurnedPosition} from "../src/interfaces/IUpgradeableV4Hook.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {BaseHook, Hooks} from "@uniswap/v4-periphery/src/utils/BaseHook.sol";
import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {LpPosition} from "../src/types/LpPosition.sol";
import {V4Liquidity} from "../src/libs/V4Liquidity.sol";
import {IERC165} from "@openzeppelin/contracts/utils/introspection/IERC165.sol";
import {IZoraV4CoinHook} from "../src/interfaces/IZoraV4CoinHook.sol";
import {ICoinV4} from "../src/interfaces/ICoinV4.sol";
import {Currency} from "@uniswap/v4-core/src/types/Currency.sol";
import {CoinCommon} from "../src/libs/CoinCommon.sol";

contract LiquidityMigrationReceiver is IUpgradeableDestinationV4Hook, IERC165 {
    function initializeFromMigration(
        PoolKey calldata poolKey,
        address coin,
        uint160 sqrtPriceX96,
        BurnedPosition[] calldata migratedLiquidity,
        bytes calldata additionalData
    ) external override {
        // do nothing
    }

    function supportsInterface(bytes4 interfaceId) external pure override returns (bool) {
        return interfaceId == type(IUpgradeableDestinationV4Hook).interfaceId || interfaceId == type(IERC165).interfaceId;
    }
}

contract InvalidLiquidityMigrationReceiver is IERC165 {
    function supportsInterface(bytes4 interfaceId) external pure override returns (bool) {
        return interfaceId == type(IERC165).interfaceId;
        // Notably does NOT support IUpgradeableDestinationV4Hook
    }
}

contract LiquidityMigrationTest is BaseTest {
    MockERC20 internal mockERC20A;

    function setUp() public override {
        super.setUpWithBlockNumber(30267794);

        mockERC20A = new MockERC20("MockERC20A", "MCKA");
    }

    function registerUpgradePath(address baseImpl, address upgradeImpl) internal {
        address[] memory baseImpls = new address[](1);
        baseImpls[0] = address(baseImpl);

        vm.prank(hookUpgradeGate.owner());
        hookUpgradeGate.registerUpgradePath(baseImpls, upgradeImpl);
    }

    function test_migrateLiquidity_migratesLiquidityToNewHook() public {
        address currency = address(mockERC20A);
        mockERC20A.mint(address(poolManager), 1_000_000_000 ether);
        _deployV4Coin(currency);

        address trader = makeAddr("trader");

        mockERC20A.mint(trader, 10 ether);

        // do some swaps
        _swapSomeCurrencyForCoin(coinV4, currency, 1 ether, trader);
        _swapSomeCoinForCurrency(coinV4, currency, uint128(coinV4.balanceOf(trader)), trader);
        _swapSomeCurrencyForCoin(coinV4, currency, 2 ether, trader);
        _swapSomeCoinForCurrency(coinV4, currency, uint128(coinV4.balanceOf(trader)), trader);

        address[] memory trustedMessageSenders = new address[](1);
        trustedMessageSenders[0] = UNIVERSAL_ROUTER;

        address originalHook = address(contentCoinHook);

        address newHook = address(new LiquidityMigrationReceiver());

        PoolKey memory poolKey = coinV4.getPoolKey();

        registerUpgradePath(address(poolKey.hooks), address(newHook));

        // get pool balance before, after and delta
        uint256 poolCurrencyBalanceBefore = mockERC20A.balanceOf(address(poolManager));
        uint256 poolCoinBalanceBefore = coinV4.balanceOf(address(poolManager));

        // get the original hook balances before the migration
        uint256 originalHookCurrencyBalanceBefore = mockERC20A.balanceOf(address(originalHook));
        uint256 originalHookCoinBalanceBefore = coinV4.balanceOf(address(originalHook));

        // migrate the liquidity
        vm.prank(users.creator);
        coinV4.migrateLiquidity(address(newHook), "");

        uint256 poolCurrencyBalanceAfter = mockERC20A.balanceOf(address(poolManager));
        uint256 poolCoinBalanceAfter = coinV4.balanceOf(address(poolManager));

        // make sure that the new hook has the balance
        assertEq(mockERC20A.balanceOf(address(newHook)), poolCurrencyBalanceBefore - poolCurrencyBalanceAfter, "new mock erc20 balance");
        assertEq(coinV4.balanceOf(address(newHook)), poolCoinBalanceBefore - poolCoinBalanceAfter, "new coin balance");

        // make sure that the original hook has no erc20 balance change
        assertEq(mockERC20A.balanceOf(address(originalHook)), originalHookCurrencyBalanceBefore, "original mock erc20 balance");
        assertEq(coinV4.balanceOf(address(originalHook)), originalHookCoinBalanceBefore, "original coin balance");

        // validate that the existing hook has no liquidity for its positions
        LpPosition[] memory positions = contentCoinHook.getPoolCoin(poolKey).positions;

        for (uint256 i = 0; i < positions.length; i++) {
            uint128 liquidity = V4Liquidity.getLiquidity(poolManager, address(originalHook), poolKey, positions[i].tickLower, positions[i].tickUpper);
            assertEq(liquidity, 0, string.concat("liquidity should be 0 for position ", vm.toString(i)));
        }

        // validate the poolkey was updated on the coin
        PoolKey memory newPoolKey = coinV4.getPoolKey();
        assertEq(address(newPoolKey.hooks), address(newHook), "poolkey hooks");
        assertEq(Currency.unwrap(newPoolKey.currency0), Currency.unwrap(poolKey.currency0), "poolkey currency0");
        assertEq(Currency.unwrap(newPoolKey.currency1), Currency.unwrap(poolKey.currency1), "poolkey currency1");
        assertEq(newPoolKey.fee, poolKey.fee, "poolkey fee");
        assertEq(newPoolKey.tickSpacing, poolKey.tickSpacing, "poolkey tickSpacing");
    }

    function test_migrateLiquidity_emitsLiquidityMigrated() public {
        address currency = address(mockERC20A);
        _deployV4Coin(currency);

        address newHook = address(new LiquidityMigrationReceiver());

        PoolKey memory poolKey = coinV4.getPoolKey();

        registerUpgradePath(address(poolKey.hooks), address(newHook));

        bytes32 fromPoolKeyHash = CoinCommon.hashPoolKey(poolKey);

        PoolKey memory newPoolKey = PoolKey({
            currency0: poolKey.currency0,
            currency1: poolKey.currency1,
            fee: poolKey.fee,
            tickSpacing: poolKey.tickSpacing,
            hooks: IHooks(address(newHook))
        });

        bytes32 toPoolKeyHash = CoinCommon.hashPoolKey(newPoolKey);

        // migrate the liquidity
        vm.prank(users.creator);
        vm.expectEmit(true, true, true, true);
        emit ICoinV4.LiquidityMigrated(poolKey, fromPoolKeyHash, newPoolKey, toPoolKeyHash);
        coinV4.migrateLiquidity(address(newHook), "");
    }

    function test_migrateLiquidity_revertsIfNewHookDoesNotSupportDestinationInterface() public {
        address currency = address(mockERC20A);
        _deployV4Coin(currency);

        address originalHook = address(contentCoinHook);

        address invalidNewHook = address(new InvalidLiquidityMigrationReceiver());

        PoolKey memory poolKey = coinV4.getPoolKey();

        registerUpgradePath(address(poolKey.hooks), address(invalidNewHook));

        // expect the migration to revert with InvalidNewHook error
        vm.prank(users.creator);
        vm.expectRevert(abi.encodeWithSelector(IUpgradeableV4Hook.InvalidNewHook.selector, invalidNewHook));
        coinV4.migrateLiquidity(address(invalidNewHook), "");
    }

    function test_migrateLiquidity_revertsIfUpgradePathNotRegistered() public {
        address currency = address(mockERC20A);
        _deployV4Coin(currency);

        address originalHook = address(contentCoinHook);

        address newHook = address(new LiquidityMigrationReceiver());

        PoolKey memory poolKey = coinV4.getPoolKey();

        // Note: NOT registering the upgrade path

        // expect the migration to revert with UpgradePathNotRegistered error
        vm.prank(users.creator);
        vm.expectRevert(abi.encodeWithSelector(IUpgradeableV4Hook.UpgradePathNotRegistered.selector, originalHook, newHook));
        coinV4.migrateLiquidity(address(newHook), "");
    }

    function test_migrateLiquidity_revertsIfNotCalledByCoin() public {
        address currency = address(mockERC20A);
        _deployV4Coin(currency);

        address originalHook = address(contentCoinHook);
        address newHook = address(new LiquidityMigrationReceiver());
        PoolKey memory poolKey = coinV4.getPoolKey();

        registerUpgradePath(address(poolKey.hooks), address(newHook));

        // Try to call migrate directly on hook instead of through coin
        vm.prank(users.creator);
        vm.expectRevert(abi.encodeWithSelector(IZoraV4CoinHook.OnlyCoin.selector, users.creator, address(coinV4)));
        IUpgradeableV4Hook(originalHook).migrateLiquidity(address(newHook), poolKey, "");
    }
}
