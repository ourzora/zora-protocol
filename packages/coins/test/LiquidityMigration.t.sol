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
import {ICoin} from "../src/interfaces/ICoin.sol";
import {Currency} from "@uniswap/v4-core/src/types/Currency.sol";
import {CoinCommon} from "../src/libs/CoinCommon.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {IHooksUpgradeGate} from "../src/interfaces/IHooksUpgradeGate.sol";

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

        address originalHook = address(hook);

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
        LpPosition[] memory positions = hook.getPoolCoin(poolKey).positions;

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

    function test_migrateLiquidity_enablesSwapsOnOldPoolKey() public {
        address currency = address(mockERC20A);
        mockERC20A.mint(address(poolManager), 1_000_000_000 ether);
        _deployV4Coin(currency);

        address trader = makeAddr("trader");

        mockERC20A.mint(trader, 10 ether);

        // do some swaps
        _swapSomeCurrencyForCoin(coinV4, currency, 1 ether, trader);
        _swapSomeCoinForCurrency(coinV4, currency, uint128(coinV4.balanceOf(trader)), trader);

        address newHook = address(new LiquidityMigrationReceiver());

        PoolKey memory poolKey = coinV4.getPoolKey();

        registerUpgradePath(address(poolKey.hooks), address(newHook));

        // migrate the liquidity
        vm.prank(users.creator);
        coinV4.migrateLiquidity(address(newHook), "");

        // now swap using the existing pool key, it should succeed
        _swapSomeCurrencyForCoin(poolKey, coinV4, currency, uint128(mockERC20A.balanceOf(trader)), trader);
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
        emit ICoin.LiquidityMigrated(poolKey, fromPoolKeyHash, newPoolKey, toPoolKeyHash);
        coinV4.migrateLiquidity(address(newHook), "");
    }

    function test_migrateLiquidity_revertsIfNewHookDoesNotSupportDestinationInterface() public {
        address currency = address(mockERC20A);
        _deployV4Coin(currency);

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

        address originalHook = address(hook);

        address newHook = address(new LiquidityMigrationReceiver());

        // Note: NOT registering the upgrade path
        // expect the migration to revert with UpgradePathNotRegistered error
        vm.prank(users.creator);
        vm.expectRevert(abi.encodeWithSelector(IUpgradeableV4Hook.UpgradePathNotRegistered.selector, originalHook, newHook));
        coinV4.migrateLiquidity(address(newHook), "");
    }

    function test_migrateLiquidity_revertsIfNotCalledByCoin() public {
        address currency = address(mockERC20A);
        _deployV4Coin(currency);

        address originalHook = address(hook);
        address newHook = address(new LiquidityMigrationReceiver());
        PoolKey memory poolKey = coinV4.getPoolKey();

        registerUpgradePath(address(poolKey.hooks), address(newHook));

        // Try to call migrate directly on hook instead of through coin
        vm.prank(users.creator);
        vm.expectRevert(abi.encodeWithSelector(IZoraV4CoinHook.OnlyCoin.selector, users.creator, address(coinV4)));
        IUpgradeableV4Hook(originalHook).migrateLiquidity(address(newHook), poolKey, "");
    }

    // Hook Upgrade Gate Tests
    function test_hookUpgradeGate_removeUpgradePath() public {
        address baseImpl = makeAddr("baseImpl");
        address upgradeImpl = makeAddr("upgradeImpl");

        // First register the upgrade path
        address[] memory baseImpls = new address[](1);
        baseImpls[0] = baseImpl;

        vm.prank(hookUpgradeGate.owner());
        hookUpgradeGate.registerUpgradePath(baseImpls, upgradeImpl);

        // Verify it's registered
        assertTrue(hookUpgradeGate.isRegisteredUpgradePath(baseImpl, upgradeImpl));

        // Remove the upgrade path
        vm.prank(hookUpgradeGate.owner());
        vm.expectEmit(true, true, false, false);
        emit IHooksUpgradeGate.UpgradeRemoved(baseImpl, upgradeImpl);
        hookUpgradeGate.removeUpgradePath(baseImpl, upgradeImpl);

        // Verify it's removed
        assertFalse(hookUpgradeGate.isRegisteredUpgradePath(baseImpl, upgradeImpl));
    }

    function test_hookUpgradeGate_removeUpgradePath_onlyOwner() public {
        address baseImpl = makeAddr("baseImpl");
        address upgradeImpl = makeAddr("upgradeImpl");
        address nonOwner = makeAddr("nonOwner");

        // Try to remove upgrade path as non-owner
        vm.prank(nonOwner);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, nonOwner));
        hookUpgradeGate.removeUpgradePath(baseImpl, upgradeImpl);
    }

    function test_hookUpgradeGate_registerUpgradePath_onlyOwner() public {
        address baseImpl = makeAddr("baseImpl");
        address upgradeImpl = makeAddr("upgradeImpl");
        address nonOwner = makeAddr("nonOwner");

        address[] memory baseImpls = new address[](1);
        baseImpls[0] = baseImpl;

        // Try to register upgrade path as non-owner
        vm.prank(nonOwner);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, nonOwner));
        hookUpgradeGate.registerUpgradePath(baseImpls, upgradeImpl);
    }

    function test_hookUpgradeGate_registerMultipleUpgradePaths() public {
        address baseImpl1 = makeAddr("baseImpl1");
        address baseImpl2 = makeAddr("baseImpl2");
        address baseImpl3 = makeAddr("baseImpl3");
        address upgradeImpl = makeAddr("upgradeImpl");

        address[] memory baseImpls = new address[](3);
        baseImpls[0] = baseImpl1;
        baseImpls[1] = baseImpl2;
        baseImpls[2] = baseImpl3;

        // Register multiple upgrade paths at once
        vm.prank(hookUpgradeGate.owner());
        vm.expectEmit(true, true, false, false);
        emit IHooksUpgradeGate.UpgradeRegistered(baseImpl1, upgradeImpl);
        vm.expectEmit(true, true, false, false);
        emit IHooksUpgradeGate.UpgradeRegistered(baseImpl2, upgradeImpl);
        vm.expectEmit(true, true, false, false);
        emit IHooksUpgradeGate.UpgradeRegistered(baseImpl3, upgradeImpl);
        hookUpgradeGate.registerUpgradePath(baseImpls, upgradeImpl);

        // Verify all paths are registered
        assertTrue(hookUpgradeGate.isRegisteredUpgradePath(baseImpl1, upgradeImpl));
        assertTrue(hookUpgradeGate.isRegisteredUpgradePath(baseImpl2, upgradeImpl));
        assertTrue(hookUpgradeGate.isRegisteredUpgradePath(baseImpl3, upgradeImpl));
    }

    function test_hookUpgradeGate_registerEmptyArray() public {
        address upgradeImpl = makeAddr("upgradeImpl");
        address[] memory baseImpls = new address[](0);

        // Register with empty array - should succeed but do nothing
        vm.prank(hookUpgradeGate.owner());
        hookUpgradeGate.registerUpgradePath(baseImpls, upgradeImpl);

        // No events should be emitted, no state changes
    }

    function test_hookUpgradeGate_removeNonexistentUpgradePath() public {
        address baseImpl = makeAddr("baseImpl");
        address upgradeImpl = makeAddr("upgradeImpl");

        // Try to remove a path that was never registered
        vm.prank(hookUpgradeGate.owner());
        vm.expectEmit(true, true, false, false);
        emit IHooksUpgradeGate.UpgradeRemoved(baseImpl, upgradeImpl);
        hookUpgradeGate.removeUpgradePath(baseImpl, upgradeImpl);

        // Should still be false (was already false)
        assertFalse(hookUpgradeGate.isRegisteredUpgradePath(baseImpl, upgradeImpl));
    }

    function test_hookUpgradeGate_registerSamePathTwice() public {
        address baseImpl = makeAddr("baseImpl");
        address upgradeImpl = makeAddr("upgradeImpl");

        address[] memory baseImpls = new address[](1);
        baseImpls[0] = baseImpl;

        // Register once
        vm.prank(hookUpgradeGate.owner());
        hookUpgradeGate.registerUpgradePath(baseImpls, upgradeImpl);
        assertTrue(hookUpgradeGate.isRegisteredUpgradePath(baseImpl, upgradeImpl));

        // Register again - should succeed and overwrite (true -> true)
        vm.prank(hookUpgradeGate.owner());
        vm.expectEmit(true, true, false, false);
        emit IHooksUpgradeGate.UpgradeRegistered(baseImpl, upgradeImpl);
        hookUpgradeGate.registerUpgradePath(baseImpls, upgradeImpl);
        assertTrue(hookUpgradeGate.isRegisteredUpgradePath(baseImpl, upgradeImpl));
    }

    function test_hookUpgradeGate_zeroAddressHandling() public {
        address[] memory baseImpls = new address[](2);
        baseImpls[0] = address(0);
        baseImpls[1] = makeAddr("baseImpl");
        address upgradeImpl = address(0);

        // Should allow zero addresses (no validation in contract)
        vm.prank(hookUpgradeGate.owner());
        hookUpgradeGate.registerUpgradePath(baseImpls, upgradeImpl);

        assertTrue(hookUpgradeGate.isRegisteredUpgradePath(address(0), address(0)));
        assertTrue(hookUpgradeGate.isRegisteredUpgradePath(makeAddr("baseImpl"), address(0)));
    }

    function test_hookUpgradeGate_isAllowedHookUpgradeMapping() public {
        address baseImpl = makeAddr("baseImpl");
        address upgradeImpl = makeAddr("upgradeImpl");

        // Test direct mapping access
        assertFalse(hookUpgradeGate.isAllowedHookUpgrade(baseImpl, upgradeImpl));

        // Register upgrade path
        address[] memory baseImpls = new address[](1);
        baseImpls[0] = baseImpl;
        vm.prank(hookUpgradeGate.owner());
        hookUpgradeGate.registerUpgradePath(baseImpls, upgradeImpl);

        // Test direct mapping access
        assertTrue(hookUpgradeGate.isAllowedHookUpgrade(baseImpl, upgradeImpl));

        // Should match isRegisteredUpgradePath
        assertEq(hookUpgradeGate.isAllowedHookUpgrade(baseImpl, upgradeImpl), hookUpgradeGate.isRegisteredUpgradePath(baseImpl, upgradeImpl));
    }
}
