// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {BaseTest} from "./utils/BaseTest.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {IZoraLimitOrderBook} from "../src/IZoraLimitOrderBook.sol";
import {PermittedCallers} from "../src/access/PermittedCallers.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {Currency} from "@uniswap/v4-core/src/types/Currency.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {SwapWithLimitOrders} from "../src/router/SwapWithLimitOrders.sol";
import {LimitOrderConfig} from "../src/libs/SwapLimitOrders.sol";

contract LimitOrderAccessControlTest is BaseTest {
    address public unauthorizedUser;
    address public authorizedCaller;
    address public newOwner;

    function setUp() public override {
        super.setUpNonForked();

        // Set up test users
        unauthorizedUser = makeAddr("unauthorizedUser");
        authorizedCaller = makeAddr("authorizedCaller");
        newOwner = makeAddr("newOwner");
    }

    function _prepareOrder(
        address caller,
        PoolKey memory key
    ) internal returns (bool isCurrency0, address orderCoin, uint256[] memory orderSizes, int24[] memory orderTicks) {
        isCurrency0 = Currency.unwrap(key.currency0) == address(creatorCoin);
        orderCoin = _orderCoin(key, isCurrency0);

        orderSizes = new uint256[](1);
        orderSizes[0] = 1 ether;
        orderTicks = new int24[](1);
        int24 currentTick = _alignedTick(_currentTick(key), key.tickSpacing);
        orderTicks[0] = isCurrency0 ? currentTick + key.tickSpacing * 4 : currentTick - key.tickSpacing * 4;

        if (orderCoin == address(0)) {
            vm.deal(caller, 2 ether);
        } else {
            deal(orderCoin, caller, 2 ether);
        }

        vm.startPrank(caller);
        if (orderCoin != address(0)) {
            IERC20(orderCoin).approve(address(limitOrderBook), 1 ether);
        }
    }

    function _createOrder(
        PoolKey memory key,
        bool isCurrency0,
        uint256[] memory orderSizes,
        int24[] memory orderTicks,
        address caller,
        address orderCoin
    ) internal {
        limitOrderBook.create{value: orderCoin == address(0) ? 1 ether : 0}(key, isCurrency0, orderSizes, orderTicks, caller);
        vm.stopPrank();
    }

    function _registerTestHook(address hookAddress) internal {
        address[] memory hooks = new address[](1);
        hooks[0] = hookAddress;
        string[] memory tags = new string[](1);
        tags[0] = "TEST_HOOK";
        vm.prank(users.factoryOwner);
        zoraHookRegistry.registerHooks(hooks, tags);
    }

    function _setPublicAccess(bool isPublic) internal {
        address[] memory callers = new address[](1);
        callers[0] = address(0); // PUBLIC_ACCESS sentinel
        bool[] memory permitted = new bool[](1);
        permitted[0] = isPublic;
        limitOrderBook.setPermittedCallers(callers, permitted);
    }

    // Test: create() works in public mode (default)
    function test_create_publicMode() public {
        PoolKey memory key = creatorCoin.getPoolKey();

        // Verify any address is permitted by default (public mode)
        assertTrue(limitOrderBook.isPermittedCaller(unauthorizedUser), "any address should be permitted in public mode");

        // Anyone can create orders in public mode
        (bool isCurrency0, address orderCoin, uint256[] memory orderSizes, int24[] memory orderTicks) = _prepareOrder(unauthorizedUser, key);
        _createOrder(key, isCurrency0, orderSizes, orderTicks, unauthorizedUser, orderCoin);
    }

    // Test: setPermittedCallers can toggle public access control via address(0)
    function test_setPermittedCallers_togglesPublicAccessControl() public {
        PoolKey memory key = creatorCoin.getPoolKey();

        // Initially public - anyone can create
        assertTrue(limitOrderBook.isPermittedCaller(unauthorizedUser));
        (bool isCurrency0, address orderCoin, uint256[] memory orderSizes, int24[] memory orderTicks) = _prepareOrder(unauthorizedUser, key);
        _createOrder(key, isCurrency0, orderSizes, orderTicks, unauthorizedUser, orderCoin);

        // Owner sets to permissioned mode by disabling address(0)
        _setPublicAccess(false);
        assertFalse(limitOrderBook.isPermittedCaller(unauthorizedUser));

        // Now unauthorized user should fail
        (isCurrency0, orderCoin, orderSizes, orderTicks) = _prepareOrder(unauthorizedUser, key);
        vm.expectRevert(PermittedCallers.CallerNotPermitted.selector);
        limitOrderBook.create{value: orderCoin == address(0) ? 1 ether : 0}(key, isCurrency0, orderSizes, orderTicks, unauthorizedUser);
        vm.stopPrank();

        // Owner sets back to public mode
        _setPublicAccess(true);
        assertTrue(limitOrderBook.isPermittedCaller(unauthorizedUser));

        // Now anyone can create again
        (isCurrency0, orderCoin, orderSizes, orderTicks) = _prepareOrder(unauthorizedUser, key);
        _createOrder(key, isCurrency0, orderSizes, orderTicks, unauthorizedUser, orderCoin);
    }

    // Test: unauthorized user cannot create in permissioned mode
    function test_create_permissionedMode_unauthorizedFails() public {
        PoolKey memory key = creatorCoin.getPoolKey();

        // Set to permissioned mode
        _setPublicAccess(false);

        // Unauthorized user tries to create
        (bool isCurrency0, address orderCoin, uint256[] memory orderSizes, int24[] memory orderTicks) = _prepareOrder(unauthorizedUser, key);
        vm.expectRevert(PermittedCallers.CallerNotPermitted.selector);
        limitOrderBook.create{value: orderCoin == address(0) ? 1 ether : 0}(key, isCurrency0, orderSizes, orderTicks, unauthorizedUser);
        vm.stopPrank();
    }

    // Test: setPermittedCallers grants and revokes access
    function test_setPermittedCallers_grantsAndRevokesAccess() public {
        PoolKey memory key = creatorCoin.getPoolKey();

        // Set to permissioned mode
        _setPublicAccess(false);

        // Initially unauthorized user cannot create
        (bool isCurrency0, address orderCoin, uint256[] memory orderSizes, int24[] memory orderTicks) = _prepareOrder(unauthorizedUser, key);
        vm.expectRevert(PermittedCallers.CallerNotPermitted.selector);
        limitOrderBook.create{value: orderCoin == address(0) ? 1 ether : 0}(key, isCurrency0, orderSizes, orderTicks, unauthorizedUser);
        vm.stopPrank();

        // Grant access to user
        address[] memory callers = new address[](1);
        callers[0] = unauthorizedUser;
        bool[] memory permitted = new bool[](1);
        permitted[0] = true;
        limitOrderBook.setPermittedCallers(callers, permitted);

        assertTrue(limitOrderBook.isPermittedCaller(unauthorizedUser), "user should be permitted");

        // Now user can create
        (isCurrency0, orderCoin, orderSizes, orderTicks) = _prepareOrder(unauthorizedUser, key);
        _createOrder(key, isCurrency0, orderSizes, orderTicks, unauthorizedUser, orderCoin);

        // Revoke access
        permitted[0] = false;
        limitOrderBook.setPermittedCallers(callers, permitted);

        assertFalse(limitOrderBook.isPermittedCaller(unauthorizedUser), "user should not be permitted");

        // Now user cannot create again
        (isCurrency0, orderCoin, orderSizes, orderTicks) = _prepareOrder(unauthorizedUser, key);
        vm.expectRevert(PermittedCallers.CallerNotPermitted.selector);
        limitOrderBook.create{value: orderCoin == address(0) ? 1 ether : 0}(key, isCurrency0, orderSizes, orderTicks, unauthorizedUser);
        vm.stopPrank();
    }

    // Test: setPermittedCallers works with multiple addresses
    function test_setPermittedCallers_batchUpdate() public {
        address caller1 = makeAddr("caller1");
        address caller2 = makeAddr("caller2");
        address caller3 = makeAddr("caller3");

        _setPublicAccess(false);

        // Grant access to multiple callers
        address[] memory callers = new address[](3);
        callers[0] = caller1;
        callers[1] = caller2;
        callers[2] = caller3;
        // set public to false
        bool[] memory permitted = new bool[](3);
        permitted[0] = true;
        permitted[1] = true;
        permitted[2] = true;

        limitOrderBook.setPermittedCallers(callers, permitted);

        assertTrue(limitOrderBook.isPermittedCaller(caller1));
        assertTrue(limitOrderBook.isPermittedCaller(caller2));
        assertTrue(limitOrderBook.isPermittedCaller(caller3));

        // Revoke access from caller2
        address[] memory revokeList = new address[](1);
        revokeList[0] = caller2;
        bool[] memory revokePermitted = new bool[](1);
        revokePermitted[0] = false;

        limitOrderBook.setPermittedCallers(revokeList, revokePermitted);

        assertTrue(limitOrderBook.isPermittedCaller(caller1));
        assertFalse(limitOrderBook.isPermittedCaller(caller2));
        assertTrue(limitOrderBook.isPermittedCaller(caller3));
    }

    // Test: non-hook cannot fill while unlocked
    function test_nonHookCannotFillWhileUnlocked() public {
        PoolKey memory key = creatorCoin.getPoolKey();

        // Create a mock contract that will try to call fill during unlock
        UnlockedFillCaller caller = new UnlockedFillCaller(address(limitOrderBook), address(poolManager));

        // Attempt to call fill while unlocked - should revert with UnlockedFillNotAllowed
        vm.expectRevert(IZoraLimitOrderBook.UnlockedFillNotAllowed.selector);
        caller.attemptUnlockedFill(key, false, -type(int24).max, type(int24).max, 1, address(0));
    }

    // Test: registered hook can fill while unlocked
    function test_fillRegisteredHookCanFillWhileUnlocked() public {
        PoolKey memory key = creatorCoin.getPoolKey();

        vm.recordLogs();
        _executeSingleHopSwapWithLimitOrders(users.seller, key, DEFAULT_LIMIT_ORDER_AMOUNT, _defaultMultiples(), _defaultPercentages());
        CreatedOrderLog[] memory created = _decodeCreatedLogs(vm.getRecordedLogs());
        assertGt(created.length, 0, "expected orders to be created");

        // Move price past orders so they are fully crossed
        _movePriceBeyondTicksWithAutoFillDisabled(created);

        (int24 startTick, int24 endTick) = _tickWindow(created, key);
        UnlockedFillCaller caller = new UnlockedFillCaller(address(limitOrderBook), address(poolManager));
        _registerTestHook(address(caller));

        vm.recordLogs();
        caller.attemptUnlockedFill(key, created[0].isCurrency0, startTick, endTick, created.length, address(0));
        FilledOrderLog[] memory fills = _decodeFilledLogs(vm.getRecordedLogs());

        assertEq(fills.length, created.length, "fill count mismatch");
        assertEq(_makerBalance(users.seller, created[0].coin), 0, "maker balance should be zero");
    }

    // Test: unregistered hook cannot fill while unlocked
    function test_fillUnregisteredHookCannotFillWhileUnlocked() public {
        PoolKey memory key = creatorCoin.getPoolKey();
        UnlockedFillCaller caller = new UnlockedFillCaller(address(limitOrderBook), address(poolManager));

        vm.expectRevert(IZoraLimitOrderBook.UnlockedFillNotAllowed.selector);
        caller.attemptUnlockedFill(key, true, -type(int24).max, type(int24).max, 5, address(0));
    }

    // Test: fill maxFillCount defaults to storage
    function test_fill_MaxFillCountDefaultsToStorage() public {
        PoolKey memory key = creatorCoin.getPoolKey();

        vm.recordLogs();
        _executeSingleHopSwapWithLimitOrders(users.seller, key, DEFAULT_LIMIT_ORDER_AMOUNT, _defaultMultiples(), _defaultPercentages());
        CreatedOrderLog[] memory created = _decodeCreatedLogs(vm.getRecordedLogs());
        assertGt(created.length, 2, "expected multiple orders");

        // Move price past orders so they are fully crossed
        _movePriceBeyondTicksWithAutoFillDisabled(created);

        uint256 previousMax = limitOrderBook.getMaxFillCount();
        limitOrderBook.setMaxFillCount(2);
        (int24 startTick, int24 endTick) = _tickWindow(created, key);

        vm.recordLogs();
        limitOrderBook.fill(key, created[0].isCurrency0, startTick, endTick, 0, address(0));
        FilledOrderLog[] memory fills = _decodeFilledLogs(vm.getRecordedLogs());
        assertEq(fills.length, 2, "should use stored maxFillCount when input is zero");

        limitOrderBook.setMaxFillCount(previousMax);
    }

    // Test: fillBatch ignores empty order arrays
    function test_fillBatchIgnoresEmptyOrderArrays() public {
        PoolKey memory key = creatorCoin.getPoolKey();

        vm.recordLogs();
        _executeSingleHopSwapWithLimitOrders(users.seller, key, DEFAULT_LIMIT_ORDER_AMOUNT, _defaultMultiples(), _defaultPercentages());
        CreatedOrderLog[] memory created = _decodeCreatedLogs(vm.getRecordedLogs());
        assertGt(created.length, 2, "expected >=2 orders");

        // Move price past orders so they are fully crossed
        _movePriceBeyondTicksWithAutoFillDisabled(created);

        uint256 makerBalanceBefore = _makerBalance(users.seller, created[0].coin);

        bytes32[] memory ids = new bytes32[](2);
        ids[0] = created[0].orderId;
        ids[1] = created[1].orderId;

        IZoraLimitOrderBook.OrderBatch[] memory batches = new IZoraLimitOrderBook.OrderBatch[](3);
        batches[0].key = key;
        batches[0].isCurrency0 = created[0].isCurrency0;
        batches[0].orderIds = new bytes32[](0);
        batches[1].key = key;
        batches[1].isCurrency0 = created[0].isCurrency0;
        batches[1].orderIds = ids;
        batches[2].key = key;
        batches[2].isCurrency0 = created[0].isCurrency0;
        batches[2].orderIds = new bytes32[](0);

        vm.recordLogs();
        limitOrderBook.fill(batches, address(0));
        FilledOrderLog[] memory fills = _decodeFilledLogs(vm.getRecordedLogs());
        assertEq(fills.length, ids.length, "only populated batch should fill");

        uint256 makerBalanceAfter = _makerBalance(users.seller, created[0].coin);
        uint256 expectedDelta = created[0].size + created[1].size;
        assertApproxEqAbs(makerBalanceBefore - makerBalanceAfter, expectedDelta, 3, "unexpected maker balance delta");
    }

    // Test: unlockCallback reverts for non-poolManager
    function test_unlockCallbackRevertsForNonPoolManager() public {
        vm.expectRevert(IZoraLimitOrderBook.NotPoolManager.selector);
        limitOrderBook.unlockCallback(bytes(""));
    }

    // Test: receive reverts for non-poolManager
    function test_receiveRevertsForNonPoolManager() public {
        vm.deal(address(this), 1 ether);
        vm.expectRevert(IZoraLimitOrderBook.NotPoolManager.selector);
        payable(address(limitOrderBook)).transfer(1 wei);
    }

    // Test: setMaxFillCount - owner can set
    function test_setMaxFillCount_ownerCanSet() public {
        // Initially max fill count should be 50 (set in BaseTest)
        assertEq(limitOrderBook.getMaxFillCount(), 50);

        // Owner (this contract) should be able to set it
        limitOrderBook.setMaxFillCount(20);

        assertEq(limitOrderBook.getMaxFillCount(), 20);
    }

    // Test: setMaxFillCount - unauthorized user cannot set
    function test_setMaxFillCount_unauthorizedUserCannotSet() public {
        // Unauthorized user tries to set max fill count
        vm.prank(unauthorizedUser);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, unauthorizedUser));
        limitOrderBook.setMaxFillCount(20);

        // Verify value hasn't changed (still 50 from BaseTest)
        assertEq(limitOrderBook.getMaxFillCount(), 50);
    }

    // Test: setPermittedCallers - owner can set
    function test_setPermittedCallers_ownerCanSet() public {
        address[] memory callers = new address[](1);
        callers[0] = authorizedCaller;
        bool[] memory permitted = new bool[](1);
        permitted[0] = true;

        limitOrderBook.setPermittedCallers(callers, permitted);
        assertTrue(limitOrderBook.isPermittedCaller(authorizedCaller));
    }

    // Test: setPermittedCallers - unauthorized user cannot set
    function test_setPermittedCallers_unauthorizedUserCannotSet() public {
        address[] memory callers = new address[](0);
        bool[] memory permitted = new bool[](0);

        vm.prank(unauthorizedUser);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, unauthorizedUser));
        limitOrderBook.setPermittedCallers(callers, permitted);
    }

    // Test: setLimitOrderConfig - owner can set
    function test_setLimitOrderConfig_ownerCanSet() public {
        // Owner (this contract) should be able to set limit order config
        uint256[] memory multiples = new uint256[](2);
        multiples[0] = 2e18; // 2x
        multiples[1] = 3e18; // 3x

        uint256[] memory percentages = new uint256[](2);
        percentages[0] = 5000; // 50%
        percentages[1] = 5000; // 50%

        LimitOrderConfig memory config = LimitOrderConfig({multiples: multiples, percentages: percentages});

        swapWithLimitOrders.setLimitOrderConfig(config);
    }

    // Test: setLimitOrderConfig - unauthorized user cannot set
    function test_setLimitOrderConfig_unauthorizedUserCannotSet() public {
        uint256[] memory multiples = new uint256[](2);
        multiples[0] = 2e18;
        multiples[1] = 3e18;

        uint256[] memory percentages = new uint256[](2);
        percentages[0] = 5000;
        percentages[1] = 5000;

        LimitOrderConfig memory config = LimitOrderConfig({multiples: multiples, percentages: percentages});

        // Unauthorized user tries to set config
        vm.prank(unauthorizedUser);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, unauthorizedUser));
        swapWithLimitOrders.setLimitOrderConfig(config);
    }

    // Test: ownership transfer (two-step process)
    function test_ownershipTransfer() public {
        // Initial owner is this contract
        assertEq(limitOrderBook.owner(), address(this));

        // Step 1: Current owner proposes transfer
        limitOrderBook.transferOwnership(newOwner);

        // Ownership hasn't changed yet
        assertEq(limitOrderBook.owner(), address(this));
        assertEq(limitOrderBook.pendingOwner(), newOwner);

        // New owner cannot perform owner actions yet
        vm.prank(newOwner);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, newOwner));
        limitOrderBook.setMaxFillCount(100);

        // Step 2: New owner accepts transfer
        vm.prank(newOwner);
        limitOrderBook.acceptOwnership();

        // Now ownership has transferred
        assertEq(limitOrderBook.owner(), newOwner);

        // New owner can perform owner actions
        vm.prank(newOwner);
        limitOrderBook.setMaxFillCount(100);
        assertEq(limitOrderBook.getMaxFillCount(), 100);

        // Old owner cannot perform owner actions
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, address(this)));
        limitOrderBook.setMaxFillCount(50);
    }
}

contract UnlockedFillCaller {
    IZoraLimitOrderBook public immutable limitOrderBook;
    IPoolManager public immutable poolManager;

    PoolKey private pendingKey;
    bool private pendingIsCurrency0;
    int24 private pendingStartTick;
    int24 private pendingEndTick;
    uint256 private pendingMaxFillCount;
    address private pendingFillReferral;

    constructor(address _limitOrderBook, address _poolManager) {
        limitOrderBook = IZoraLimitOrderBook(_limitOrderBook);
        poolManager = IPoolManager(_poolManager);
    }

    function attemptUnlockedFill(PoolKey memory key, bool isCurrency0, int24 startTick, int24 endTick, uint256 maxFillCount, address fillReferral) external {
        pendingKey = key;
        pendingIsCurrency0 = isCurrency0;
        pendingStartTick = startTick;
        pendingEndTick = endTick;
        pendingMaxFillCount = maxFillCount;
        pendingFillReferral = fillReferral;

        poolManager.unlock(abi.encode(0));
    }

    function unlockCallback(bytes calldata) external returns (bytes memory) {
        limitOrderBook.fill(pendingKey, pendingIsCurrency0, pendingStartTick, pendingEndTick, pendingMaxFillCount, pendingFillReferral);
        return bytes("");
    }
}
