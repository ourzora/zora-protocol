// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {BaseTest} from "./utils/BaseTest.sol";
import {AccessManager} from "@openzeppelin/contracts/access/manager/AccessManager.sol";
import {SimpleAccessManaged} from "../src/access/SimpleAccessManaged.sol";
import {IZoraLimitOrderBook} from "../src/IZoraLimitOrderBook.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {Currency} from "@uniswap/v4-core/src/types/Currency.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";

contract LimitOrderAccessControlTest is BaseTest {
    uint64 public constant CREATOR_ROLE = 1;
    address public unauthorizedUser;
    address public authorizedRouter;

    function setUp() public override {
        super.setUpNonForked();

        // Set up test users
        unauthorizedUser = makeAddr("unauthorizedUser");
        authorizedRouter = makeAddr("authorizedRouter");
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

    function test_create_worksWithPublicRole() public {
        PoolKey memory key = creatorCoin.getPoolKey();

        (bool isCurrency0, address orderCoin, uint256[] memory orderSizes, int24[] memory orderTicks) = _prepareOrder(unauthorizedUser, key);
        _createOrder(key, isCurrency0, orderSizes, orderTicks, unauthorizedUser, orderCoin);
    }

    function test_transitionToPermissioned() public {
        PoolKey memory key = creatorCoin.getPoolKey();

        // Initially anyone can create orders (PUBLIC_ROLE is set in BaseTest)
        (bool isCurrency0, address orderCoin, uint256[] memory orderSizes, int24[] memory orderTicks) = _prepareOrder(unauthorizedUser, key);
        _createOrder(key, isCurrency0, orderSizes, orderTicks, unauthorizedUser, orderCoin);

        // Create a specific role for authorized creators
        accessManager.labelRole(CREATOR_ROLE, "CREATOR");

        // Grant role to authorized router
        accessManager.grantRole(CREATOR_ROLE, authorizedRouter, 0);

        // Switch function to require CREATOR_ROLE
        bytes4[] memory selectors = new bytes4[](1);
        selectors[0] = IZoraLimitOrderBook.create.selector;
        accessManager.setTargetFunctionRole(address(limitOrderBook), selectors, CREATOR_ROLE);

        // Now unauthorized user should fail
        (isCurrency0, orderCoin, orderSizes, orderTicks) = _prepareOrder(unauthorizedUser, key);
        vm.expectRevert(SimpleAccessManaged.AccessManagedUnauthorized.selector);
        limitOrderBook.create{value: orderCoin == address(0) ? 1 ether : 0}(key, isCurrency0, orderSizes, orderTicks, unauthorizedUser);
        vm.stopPrank();

        // But authorized router should succeed
        (isCurrency0, orderCoin, orderSizes, orderTicks) = _prepareOrder(authorizedRouter, key);
        _createOrder(key, isCurrency0, orderSizes, orderTicks, authorizedRouter, orderCoin);

        // If we got here without reverting, the test passed
    }

    function test_unauthorizedUserCannotCreate() public {
        PoolKey memory key = creatorCoin.getPoolKey();

        // Set up permissioned mode
        accessManager.labelRole(CREATOR_ROLE, "CREATOR");
        accessManager.grantRole(CREATOR_ROLE, authorizedRouter, 0);

        bytes4[] memory selectors = new bytes4[](1);
        selectors[0] = IZoraLimitOrderBook.create.selector;
        accessManager.setTargetFunctionRole(address(limitOrderBook), selectors, CREATOR_ROLE);

        // Unauthorized user tries to create
        (bool isCurrency0, address orderCoin, uint256[] memory orderSizes, int24[] memory orderTicks) = _prepareOrder(unauthorizedUser, key);
        vm.expectRevert(SimpleAccessManaged.AccessManagedUnauthorized.selector);
        limitOrderBook.create{value: orderCoin == address(0) ? 1 ether : 0}(key, isCurrency0, orderSizes, orderTicks, unauthorizedUser);
        vm.stopPrank();
    }

    function test_grantAndRevokeRole() public {
        PoolKey memory key = creatorCoin.getPoolKey();

        // Set up permissioned mode
        accessManager.labelRole(CREATOR_ROLE, "CREATOR");

        bytes4[] memory selectors = new bytes4[](1);
        selectors[0] = IZoraLimitOrderBook.create.selector;
        accessManager.setTargetFunctionRole(address(limitOrderBook), selectors, CREATOR_ROLE);

        // Initially unauthorized user cannot create
        (bool isCurrency0, address orderCoin, uint256[] memory orderSizes, int24[] memory orderTicks) = _prepareOrder(unauthorizedUser, key);
        vm.expectRevert(SimpleAccessManaged.AccessManagedUnauthorized.selector);
        limitOrderBook.create{value: orderCoin == address(0) ? 1 ether : 0}(key, isCurrency0, orderSizes, orderTicks, unauthorizedUser);
        vm.stopPrank();

        // Grant role to user
        accessManager.grantRole(CREATOR_ROLE, unauthorizedUser, 0);

        // Now user can create
        (isCurrency0, orderCoin, orderSizes, orderTicks) = _prepareOrder(unauthorizedUser, key);
        _createOrder(key, isCurrency0, orderSizes, orderTicks, unauthorizedUser, orderCoin);

        // Revoke role
        accessManager.revokeRole(CREATOR_ROLE, unauthorizedUser);

        // Now user cannot create again
        (isCurrency0, orderCoin, orderSizes, orderTicks) = _prepareOrder(unauthorizedUser, key);
        vm.expectRevert(SimpleAccessManaged.AccessManagedUnauthorized.selector);
        limitOrderBook.create{value: orderCoin == address(0) ? 1 ether : 0}(key, isCurrency0, orderSizes, orderTicks, unauthorizedUser);
        vm.stopPrank();
    }

    function test_adminCanReconfigure() public {
        PoolKey memory key = creatorCoin.getPoolKey();

        // Admin sets up initial permissioned mode
        accessManager.labelRole(CREATOR_ROLE, "CREATOR");
        accessManager.grantRole(CREATOR_ROLE, authorizedRouter, 0);

        bytes4[] memory selectors = new bytes4[](1);
        selectors[0] = IZoraLimitOrderBook.create.selector;
        accessManager.setTargetFunctionRole(address(limitOrderBook), selectors, CREATOR_ROLE);

        // Unauthorized user cannot create
        (bool isCurrency0, address orderCoin, uint256[] memory orderSizes, int24[] memory orderTicks) = _prepareOrder(unauthorizedUser, key);
        vm.expectRevert(SimpleAccessManaged.AccessManagedUnauthorized.selector);
        limitOrderBook.create{value: orderCoin == address(0) ? 1 ether : 0}(key, isCurrency0, orderSizes, orderTicks, unauthorizedUser);
        vm.stopPrank();

        // Admin decides to open it back up to public
        accessManager.setTargetFunctionRole(address(limitOrderBook), selectors, accessManager.PUBLIC_ROLE());

        // Now anyone can create again
        (isCurrency0, orderCoin, orderSizes, orderTicks) = _prepareOrder(unauthorizedUser, key);
        _createOrder(key, isCurrency0, orderSizes, orderTicks, unauthorizedUser, orderCoin);
    }

    function test_nonHookCannotFillWhileUnlocked() public {
        PoolKey memory key = creatorCoin.getPoolKey();

        // Create a mock contract that will try to call fill during unlock
        UnlockedFillCaller caller = new UnlockedFillCaller(address(limitOrderBook), address(poolManager));

        // Attempt to call fill while unlocked - should revert with UnlockedFillNotAllowed
        vm.expectRevert(IZoraLimitOrderBook.UnlockedFillNotAllowed.selector);
        caller.attemptUnlockedFill(key, false, -type(int24).max, type(int24).max, 1, address(0));
    }

    function test_fillRegisteredHookCanFillWhileUnlocked() public {
        PoolKey memory key = creatorCoin.getPoolKey();

        vm.recordLogs();
        _executeSingleHopSwapWithLimitOrders(users.seller, key, DEFAULT_LIMIT_ORDER_AMOUNT, _defaultMultiples(), _defaultPercentages());
        CreatedOrderLog[] memory created = _decodeCreatedLogs(vm.getRecordedLogs());
        assertGt(created.length, 0, "expected orders to be created");

        (int24 startTick, int24 endTick) = _tickWindow(created, key);
        UnlockedFillCaller caller = new UnlockedFillCaller(address(limitOrderBook), address(poolManager));
        _registerTestHook(address(caller));

        vm.recordLogs();
        caller.attemptUnlockedFill(key, created[0].isCurrency0, startTick, endTick, created.length, address(0));
        FilledOrderLog[] memory fills = _decodeFilledLogs(vm.getRecordedLogs());

        assertEq(fills.length, created.length, "fill count mismatch");
        assertEq(_makerBalance(users.seller, created[0].coin), 0, "maker balance should be zero");
    }

    function test_fillUnregisteredHookCannotFillWhileUnlocked() public {
        PoolKey memory key = creatorCoin.getPoolKey();
        UnlockedFillCaller caller = new UnlockedFillCaller(address(limitOrderBook), address(poolManager));

        vm.expectRevert(IZoraLimitOrderBook.UnlockedFillNotAllowed.selector);
        caller.attemptUnlockedFill(key, true, -type(int24).max, type(int24).max, 5, address(0));
    }

    function test_fill_MaxFillCountDefaultsToStorage() public {
        PoolKey memory key = creatorCoin.getPoolKey();

        vm.recordLogs();
        _executeSingleHopSwapWithLimitOrders(users.seller, key, DEFAULT_LIMIT_ORDER_AMOUNT, _defaultMultiples(), _defaultPercentages());
        CreatedOrderLog[] memory created = _decodeCreatedLogs(vm.getRecordedLogs());
        assertGt(created.length, 2, "expected multiple orders");

        uint256 previousMax = limitOrderBook.getMaxFillCount();
        limitOrderBook.setMaxFillCount(2);
        (int24 startTick, int24 endTick) = _tickWindow(created, key);

        vm.recordLogs();
        limitOrderBook.fill(key, created[0].isCurrency0, startTick, endTick, 0, address(0));
        FilledOrderLog[] memory fills = _decodeFilledLogs(vm.getRecordedLogs());
        assertEq(fills.length, 2, "should use stored maxFillCount when input is zero");

        limitOrderBook.setMaxFillCount(previousMax);
    }

    function test_fillBatchIgnoresEmptyOrderArrays() public {
        PoolKey memory key = creatorCoin.getPoolKey();

        vm.recordLogs();
        _executeSingleHopSwapWithLimitOrders(users.seller, key, DEFAULT_LIMIT_ORDER_AMOUNT, _defaultMultiples(), _defaultPercentages());
        CreatedOrderLog[] memory created = _decodeCreatedLogs(vm.getRecordedLogs());
        assertGt(created.length, 2, "expected >=2 orders");

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

    function test_unlockCallbackRevertsForNonPoolManager() public {
        vm.expectRevert(IZoraLimitOrderBook.NotPoolManager.selector);
        limitOrderBook.unlockCallback(bytes(""));
    }

    function test_receiveRevertsForNonPoolManager() public {
        vm.deal(address(this), 1 ether);
        vm.expectRevert(IZoraLimitOrderBook.NotPoolManager.selector);
        payable(address(limitOrderBook)).transfer(1 wei);
    }

    function test_setMaxFillCount_worksWithPublicRole() public {
        // Initially max fill count should be 50 (set in BaseTest)
        assertEq(limitOrderBook.getMaxFillCount(), 50);

        // setMaxFillCount is already configured with PUBLIC_ROLE in BaseTest
        // Any user should be able to set it
        vm.prank(unauthorizedUser);
        limitOrderBook.setMaxFillCount(20);

        assertEq(limitOrderBook.getMaxFillCount(), 20);
    }

    function test_setMaxFillCount_unauthorizedUserCannotSet() public {
        uint64 MAX_FILL_COUNT_ROLE = 2;

        // Set up permissioned mode for setMaxFillCount
        accessManager.labelRole(MAX_FILL_COUNT_ROLE, "MAX_FILL_COUNT_SETTER");
        accessManager.grantRole(MAX_FILL_COUNT_ROLE, authorizedRouter, 0);

        bytes4[] memory selectors = new bytes4[](1);
        selectors[0] = IZoraLimitOrderBook.setMaxFillCount.selector;
        accessManager.setTargetFunctionRole(address(limitOrderBook), selectors, MAX_FILL_COUNT_ROLE);

        // Unauthorized user tries to set max fill count
        vm.prank(unauthorizedUser);
        vm.expectRevert(SimpleAccessManaged.AccessManagedUnauthorized.selector);
        limitOrderBook.setMaxFillCount(20);

        // Verify value hasn't changed (still 50 from BaseTest)
        assertEq(limitOrderBook.getMaxFillCount(), 50);
    }

    function test_setMaxFillCount_authorizedUserCanSet() public {
        uint64 MAX_FILL_COUNT_ROLE = 2;

        // Set up permissioned mode
        accessManager.labelRole(MAX_FILL_COUNT_ROLE, "MAX_FILL_COUNT_SETTER");
        accessManager.grantRole(MAX_FILL_COUNT_ROLE, authorizedRouter, 0);

        bytes4[] memory selectors = new bytes4[](1);
        selectors[0] = IZoraLimitOrderBook.setMaxFillCount.selector;
        accessManager.setTargetFunctionRole(address(limitOrderBook), selectors, MAX_FILL_COUNT_ROLE);

        // Authorized user sets max fill count
        vm.prank(authorizedRouter);
        limitOrderBook.setMaxFillCount(25);

        assertEq(limitOrderBook.getMaxFillCount(), 25);
    }

    function test_setMaxFillCount_adminCanSet() public {
        uint64 MAX_FILL_COUNT_ROLE = 2;

        // Set up permissioned mode
        accessManager.labelRole(MAX_FILL_COUNT_ROLE, "MAX_FILL_COUNT_SETTER");

        bytes4[] memory selectors = new bytes4[](1);
        selectors[0] = IZoraLimitOrderBook.setMaxFillCount.selector;
        accessManager.setTargetFunctionRole(address(limitOrderBook), selectors, MAX_FILL_COUNT_ROLE);

        // Grant the role to admin explicitly
        accessManager.grantRole(MAX_FILL_COUNT_ROLE, address(this), 0);

        // Admin (this contract) should be able to set it with the granted role
        limitOrderBook.setMaxFillCount(30);

        assertEq(limitOrderBook.getMaxFillCount(), 30);
    }

    function test_setMaxFillCount_grantAndRevokeRole() public {
        uint64 MAX_FILL_COUNT_ROLE = 2;

        // Set up permissioned mode
        accessManager.labelRole(MAX_FILL_COUNT_ROLE, "MAX_FILL_COUNT_SETTER");

        bytes4[] memory selectors = new bytes4[](1);
        selectors[0] = IZoraLimitOrderBook.setMaxFillCount.selector;
        accessManager.setTargetFunctionRole(address(limitOrderBook), selectors, MAX_FILL_COUNT_ROLE);

        // Initially unauthorized user cannot set
        vm.prank(unauthorizedUser);
        vm.expectRevert(SimpleAccessManaged.AccessManagedUnauthorized.selector);
        limitOrderBook.setMaxFillCount(15);

        // Grant role to user
        accessManager.grantRole(MAX_FILL_COUNT_ROLE, unauthorizedUser, 0);

        // Now user can set
        vm.prank(unauthorizedUser);
        limitOrderBook.setMaxFillCount(15);
        assertEq(limitOrderBook.getMaxFillCount(), 15);

        // Revoke role
        accessManager.revokeRole(MAX_FILL_COUNT_ROLE, unauthorizedUser);

        // Now user cannot set again
        vm.prank(unauthorizedUser);
        vm.expectRevert(SimpleAccessManaged.AccessManagedUnauthorized.selector);
        limitOrderBook.setMaxFillCount(20);

        // Verify value hasn't changed from last successful set
        assertEq(limitOrderBook.getMaxFillCount(), 15);
    }

    function test_setAuthority_revertsForUnauthorizedCaller() public {
        address newAuthority = address(new AccessManager(address(this)));

        vm.prank(unauthorizedUser);
        vm.expectRevert(SimpleAccessManaged.AccessManagedUnauthorized.selector);
        limitOrderBook.setAuthority(newAuthority);
    }

    function test_setAuthority_revertsForNonContractAddress() public {
        // Deploy a simple test contract with test contract as authority
        AuthorityTester tester = new AuthorityTester(address(this));

        address eoaAddress = makeAddr("eoa");

        // Try to set EOA as authority - should revert with AccessManagedInvalidAuthority
        vm.expectRevert(abi.encodeWithSelector(SimpleAccessManaged.AccessManagedInvalidAuthority.selector, eoaAddress));
        tester.setAuthority(eoaAddress);
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

contract AuthorityTester is SimpleAccessManaged {
    constructor(address initialAuthority) SimpleAccessManaged(initialAuthority) {}
}
