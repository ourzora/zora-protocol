// SPDX-License-Identifier: ZORA-DELAYED-OSL-v1
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IAllowanceTransfer} from "permit2/src/interfaces/IAllowanceTransfer.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {IHooks} from "@uniswap/v4-core/src/interfaces/IHooks.sol";
import {Currency} from "@uniswap/v4-core/src/types/Currency.sol";
import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {SwapWithLimitOrders} from "../src/router/SwapWithLimitOrders.sol";
import {IZoraLimitOrderBook} from "../src/IZoraLimitOrderBook.sol";
import {ISwapRouter} from "@zoralabs/shared-contracts/interfaces/uniswap/ISwapRouter.sol";
import {LimitOrderConfig} from "../src/libs/SwapLimitOrders.sol";
import {ZoraLimitOrderBook} from "../src/ZoraLimitOrderBook.sol";
import {IUniversalRouter} from "@uniswap/universal-router/contracts/interfaces/IUniversalRouter.sol";
import {UniV4SwapHelper} from "@zoralabs/coins/src/libs/UniV4SwapHelper.sol";
import {IPermit2} from "permit2/src/interfaces/IPermit2.sol";
import {HooksDeployment} from "@zoralabs/coins/src/libs/HooksDeployment.sol";
import {ITrustedMsgSenderProviderLookup} from "@zoralabs/coins/src/interfaces/ITrustedMsgSenderProviderLookup.sol";

/// @notice Standalone fork test to reproduce a failing swapWithLimitOrders call on Base mainnet.
/// Uses deployCodeTo to etch the modified SwapWithLimitOrders (with console.log) onto the deployed router address.
contract DebugSwapWithLimitOrders is Test {
    address constant PERMIT2 = 0x000000000022D473030F116dDEE9F6B43aC78BA3;
    address payable constant ZORA_ROUTER = payable(0x77777777Eb762Cf86F634763e79d17dE44330887);
    address constant UNIVERSAL_ROUTER = 0x6fF5693b99212Da76ad316178A184AB56D299b43;

    // Constructor args read from deployed contract
    address constant POOL_MANAGER = 0x498581fF718922c3f8e6A244956aF099B2652b2b;
    address constant LIMIT_ORDER_BOOK = 0x7777777C783bAD88daCaf9A19E04238341E4497B;
    address constant SWAP_ROUTER = 0x2626664c2603336E57B271c5C0b26F421741e481;
    address constant OWNER = 0x004d6611884B4A661749B64b2ADc78505c3e1AB3;

    // Limit order book constructor args
    address constant ZORA_COIN_VERSION_LOOKUP = 0x777777751622c0d3258f214F9DF38E35BF45baF3;
    address constant ZORA_HOOK_REGISTRY = 0x777777C4c14b133858c3982D41Dbf02509fc18d7;
    address constant LOB_OWNER = 0x004d6611884B4A661749B64b2ADc78505c3e1AB3;
    address constant WETH = 0x4200000000000000000000000000000000000006;

    address constant CALLER = 0x67dc68F5d1b9d48fdA1784b309d7d3d609876196;
    address constant INPUT_CURRENCY = 0xdD9B9E272b8812D441eB15da566DEB6b86816E6a;

    // Pool key addresses
    address constant CURRENCY0 = 0x63c4AcFADEcd03F30874a95868d895891DB9a4FE;
    address constant CURRENCY1_POOL1 = 0xdD9B9E272b8812D441eB15da566DEB6b86816E6a;
    address constant CURRENCY1_POOL2 = 0xD05f95b389bbe3679A4F0D77caEFf265422Af2cb;
    address constant HOOKS = 0xC8d077444625eB300A427a6dfB2b1DBf9b159040;
    address constant HOOK_UPGRADE_GATE = 0xD88f6BdD765313CaFA5888C177c325E2C3AbF2D2;
    address constant TRUSTED_MSG_SENDER_LOOKUP = 0x2183ECF857Ade81c7fAcE1dbAa98C381520619c4;

    uint256 constant INPUT_AMOUNT = 58189250000000000000000000;
    uint256 constant MIN_AMOUNT_OUT = 52576599598595138086707355;

    function setUp() public {
        vm.createSelectFork("base", 41766928);

        // Etch the modified SwapWithLimitOrders (with console.log) onto the deployed router address
        deployCodeTo(
            "SwapWithLimitOrders.sol:SwapWithLimitOrders",
            abi.encode(
                IPoolManager(POOL_MANAGER),
                IZoraLimitOrderBook(LIMIT_ORDER_BOOK),
                ISwapRouter(SWAP_ROUTER),
                PERMIT2,
                OWNER
            ),
            ZORA_ROUTER
        );

        // Etch the modified ZoraLimitOrderBook (with console.log) onto the deployed LOB address
        deployCodeTo(
            "ZoraLimitOrderBook.sol:ZoraLimitOrderBook",
            abi.encode(POOL_MANAGER, ZORA_COIN_VERSION_LOOKUP, ZORA_HOOK_REGISTRY, LOB_OWNER, WETH),
            LIMIT_ORDER_BOOK
        );

        // Deploy new hook from current source and etch onto the existing hook address
        bytes memory hookCreationCode = HooksDeployment.makeHookCreationCode(
            POOL_MANAGER,
            ZORA_COIN_VERSION_LOOKUP, // ZoraFactory implements IDeployedCoinVersionLookup
            ITrustedMsgSenderProviderLookup(TRUSTED_MSG_SENDER_LOOKUP),
            HOOK_UPGRADE_GATE,
            LIMIT_ORDER_BOOK,
            ZORA_HOOK_REGISTRY
        );
        (IHooks newHook,) = HooksDeployment.deployHookWithExistingOrNewSalt(address(this), hookCreationCode, bytes32(0));
        vm.etch(HOOKS, address(newHook).code);

        // Also etch onto the hook used by intermediate pools in the payout swap path
        // (coinA/creator pool uses a different hook address on-chain)
        vm.etch(0xd61A675F8a0c67A73DC3B54FB7318B4D91409040, address(newHook).code);
    }

    function test_debugFailingSwapWithLimitOrders() public {
        // Fund caller to original INPUT_AMOUNT by transferring from PoolManager (holds V4 liquidity)
        // Cannot use deal() as it corrupts proxy coin storage
        uint256 callerBalance = IERC20(INPUT_CURRENCY).balanceOf(CALLER);
        if (callerBalance < INPUT_AMOUNT) {
            uint256 needed = INPUT_AMOUNT - callerBalance;
            vm.prank(POOL_MANAGER);
            IERC20(INPUT_CURRENCY).transfer(CALLER, needed);
        }
        uint256 inputAmount = INPUT_AMOUNT;

        vm.startPrank(CALLER);

        // Set up Permit2 approvals
        IERC20(INPUT_CURRENCY).approve(PERMIT2, type(uint256).max);
        IAllowanceTransfer(PERMIT2).approve(INPUT_CURRENCY, ZORA_ROUTER, type(uint160).max, type(uint48).max);

        // Build V4 route: 2 pools (multi-hop)
        PoolKey[] memory v4Route = new PoolKey[](2);

        v4Route[0] = PoolKey({
            currency0: Currency.wrap(CURRENCY0),
            currency1: Currency.wrap(CURRENCY1_POOL1),
            fee: 10000,
            tickSpacing: int24(200),
            hooks: IHooks(HOOKS)
        });

        v4Route[1] = PoolKey({
            currency0: Currency.wrap(CURRENCY0),
            currency1: Currency.wrap(CURRENCY1_POOL2),
            fee: 10000,
            tickSpacing: int24(200),
            hooks: IHooks(HOOKS)
        });

        uint256[] memory multiples = new uint256[](5);
        multiples[0] = 2e18;
        multiples[1] = 4e18;
        multiples[2] = 8e18;
        multiples[3] = 16e18;
        multiples[4] = 32e18;

        uint256[] memory percentages = new uint256[](5);
        for (uint256 i = 0; i < 5; i++) {
            percentages[i] = 2000;
        }

        LimitOrderConfig memory limitOrderConfig = LimitOrderConfig({multiples: multiples, percentages: percentages});

        SwapWithLimitOrders.SwapWithLimitOrdersParams memory params = SwapWithLimitOrders.SwapWithLimitOrdersParams({
            recipient: CALLER,
            limitOrderConfig: limitOrderConfig,
            inputCurrency: INPUT_CURRENCY,
            inputAmount: inputAmount,
            v3Route: "", // empty V3 route
            v4Route: v4Route,
            minAmountOut: 0 // no slippage check for debugging
        });

        // Execute the swap
        SwapWithLimitOrders(ZORA_ROUTER).swapWithLimitOrders(params);

        vm.stopPrank();
    }

    /// @notice Test a vanilla single-hop swap through pool 0 via the universal router
    /// to see if the hook's afterSwap works correctly when used normally
    function test_vanillaUniversalRouterSwapPool0() public {
        // Fund caller to original INPUT_AMOUNT
        uint256 callerBalance = IERC20(INPUT_CURRENCY).balanceOf(CALLER);
        if (callerBalance < INPUT_AMOUNT) {
            uint256 needed = INPUT_AMOUNT - callerBalance;
            vm.prank(POOL_MANAGER);
            IERC20(INPUT_CURRENCY).transfer(CALLER, needed);
        }

        vm.startPrank(CALLER);

        // Approve Permit2 for universal router
        UniV4SwapHelper.approveTokenWithPermit2(
            IPermit2(PERMIT2), UNIVERSAL_ROUTER, INPUT_CURRENCY, type(uint160).max, type(uint48).max
        );

        // Build pool key for pool 0
        PoolKey memory pool0 = PoolKey({
            currency0: Currency.wrap(CURRENCY0),
            currency1: Currency.wrap(CURRENCY1_POOL1),
            fee: 10000,
            tickSpacing: int24(200),
            hooks: IHooks(HOOKS)
        });

        uint128 swapAmount = uint128(INPUT_AMOUNT);

        // Single-hop swap: INPUT_CURRENCY (currency1) -> CURRENCY0
        (bytes memory commands, bytes[] memory inputs) = UniV4SwapHelper.buildExactInputSingleSwapCommand(
            INPUT_CURRENCY, // currencyIn
            swapAmount, // amountIn
            CURRENCY0, // currencyOut
            0, // minAmountOut
            pool0,
            "" // hookData
        );

        IUniversalRouter(UNIVERSAL_ROUTER).execute(commands, inputs, block.timestamp + 1 days);

        vm.stopPrank();
    }
}
