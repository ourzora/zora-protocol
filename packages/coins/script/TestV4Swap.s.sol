// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {ProxyDeployerScript, DeterministicDeployerAndCaller} from "@zoralabs/shared-contracts/deployment/ProxyDeployerScript.sol";
import {CoinsDeployerBase} from "./CoinsDeployerBase.sol";

import {IZoraFactory} from "../src/interfaces/IZoraFactory.sol";
import {CoinConfigurationVersions} from "../src/libs/CoinConfigurationVersions.sol";
import {MarketConstants} from "../src/libs/MarketConstants.sol";
import {UniV4SwapHelper} from "../src/libs/UniV4SwapHelper.sol";
import {CoinV4} from "../src/CoinV4.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {IUniversalRouter} from "@uniswap/universal-router/contracts/interfaces/IUniversalRouter.sol";
import {IPermit2} from "permit2/src/interfaces/IPermit2.sol";
import {MockERC20} from "../test/mocks/MockERC20.sol";
import {MarketConstants} from "../src/libs/MarketConstants.sol";
import {Currency} from "@uniswap/v4-core/src/types/Currency.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import {console} from "forge-std/console.sol";

contract TestV4Swap is CoinsDeployerBase {
    int24 internal constant DEFAULT_DISCOVERY_TICK_LOWER = -777000;
    int24 internal constant DEFAULT_DISCOVERY_TICK_UPPER = 222000;
    uint16 internal constant DEFAULT_NUM_DISCOVERY_POSITIONS = 10; // will be 11 total with tail position
    uint256 internal constant DEFAULT_DISCOVERY_SUPPLY_SHARE = 0.495e18; //

    function _deployMockCurrencyAndCoin(address trader, address createReferral) internal returns (MockERC20 currency, address coinAddress) {
        CoinsDeployment memory deployment = readDeployment();
        address[] memory owners = new address[](1);
        owners[0] = trader;
        currency = new MockERC20("Testcoin", "TEST");

        // mint some currency to the pool manager so that a swap can be executed
        // and fees withdrawn
        currency.mint(getUniswapV4PoolManager(), 1000000 ether);

        bytes memory poolConfig = CoinConfigurationVersions.defaultDopplerMultiCurveUniV4(address(currency));

        (coinAddress, ) = IZoraFactory(deployment.zoraFactory).deploy(trader, owners, "https://test.com", "Testcoin", "TEST", poolConfig, createReferral, 0);
    }

    function _swap(address currencyIn, uint128 amountIn, address coinAddress, address trader, address tradeReferral) internal returns (uint256 amountOut) {
        uint128 minAmountOut = 0;

        PoolKey memory poolKey = CoinV4(payable(coinAddress)).getPoolKey();

        bytes memory hookData = tradeReferral != address(0) ? abi.encode(tradeReferral) : bytes("");

        address currencyOut = Currency.unwrap(Currency.unwrap(poolKey.currency0) == currencyIn ? poolKey.currency1 : poolKey.currency0);

        // now we need to swap some currency into the coin
        // first let
        (bytes memory commands, bytes[] memory inputs) = UniV4SwapHelper.buildExactInputSingleSwapCommand(
            currencyIn,
            amountIn,
            currencyOut,
            minAmountOut,
            poolKey,
            hookData
        );

        UniV4SwapHelper.approveTokenWithPermit2(
            IPermit2(getUniswapPermit2()),
            getUniswapUniversalRouter(),
            currencyIn,
            amountIn,
            uint48(block.timestamp + 1 days)
        );

        uint256 balanceBefore = IERC20(currencyOut).balanceOf(trader);

        // Execute the swap
        uint256 deadline = block.timestamp + 1 days;
        IUniversalRouter(getUniswapUniversalRouter()).execute(commands, inputs, deadline);

        amountOut = IERC20(currencyOut).balanceOf(trader) - balanceBefore;
    }

    function run() public {
        address trader = vm.envAddress("TRADER");

        vm.startBroadcast(trader);

        address createReferral = 0x735c587Ad79Dc3284f391A8daA40F1a90eA53D17;
        address tradeReferral = 0x571304F485AdcDbaD098495A9C14C42528D6E01E;

        // (MockERC20 currency, address coinAddress) = _deployMockCurrencyAndCoin(trader, createReferral);

        MockERC20 currency = MockERC20(vm.parseAddress("0x551c6b1406a228998EF23E279A25644A2659F6e4"));
        address coinAddress = vm.parseAddress("0x58c0d8803Ae97bEF212EdFA8ba2FE303670cca9D");
        // console.log("currency", address(currency));
        // console.log("coinAddress", coinAddress);

        // swap in 2 ether of currency into the coin
        uint128 amountIn = 2 ether;

        currency.mint(trader, amountIn);

        uint256 amountOut = _swap(address(currency), amountIn, coinAddress, trader, tradeReferral);

        // now swap the coin back to the currency
        _swap(coinAddress, uint128(amountOut), coinAddress, trader, tradeReferral);

        vm.stopBroadcast();
    }
}
