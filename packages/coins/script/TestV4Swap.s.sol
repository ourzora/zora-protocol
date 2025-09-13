// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {ProxyDeployerScript, DeterministicDeployerAndCaller} from "@zoralabs/shared-contracts/deployment/ProxyDeployerScript.sol";
import {CoinsDeployerBase} from "../src/deployment/CoinsDeployerBase.sol";

import {IZoraFactory} from "../src/interfaces/IZoraFactory.sol";
import {CoinConfigurationVersions} from "../src/libs/CoinConfigurationVersions.sol";
import {MarketConstants} from "../src/libs/MarketConstants.sol";
import {UniV4SwapHelper} from "../src/libs/UniV4SwapHelper.sol";
import {ContentCoin} from "../src/ContentCoin.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {IUniversalRouter} from "@uniswap/universal-router/contracts/interfaces/IUniversalRouter.sol";
import {IPermit2} from "permit2/src/interfaces/IPermit2.sol";
import {MockERC20} from "../test/mocks/MockERC20.sol";
import {MarketConstants} from "../src/libs/MarketConstants.sol";
import {Currency} from "@uniswap/v4-core/src/types/Currency.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ICoin} from "../src/interfaces/ICoin.sol";

import {console} from "forge-std/console.sol";

contract TestV4Swap is CoinsDeployerBase {
    int24 internal constant DEFAULT_DISCOVERY_TICK_LOWER = -777000;
    int24 internal constant DEFAULT_DISCOVERY_TICK_UPPER = 222000;
    uint16 internal constant DEFAULT_NUM_DISCOVERY_POSITIONS = 10; // will be 11 total with tail position
    uint256 internal constant DEFAULT_DISCOVERY_SUPPLY_SHARE = 0.495e18; //

    function _deployMockCurrency() internal returns (MockERC20 currency) {
        currency = new MockERC20("Testcoin", "TEST");
        currency.mint(getUniswapV4PoolManager(), 1000000 ether);
    }

    function _deployMockCoin(address currency, address creator, address createReferral, bytes32 salt) internal returns (ICoin coin) {
        CoinsDeployment memory deployment = readDeployment();
        address[] memory owners = new address[](1);
        owners[0] = creator;

        bytes memory poolConfig = CoinConfigurationVersions.defaultDopplerMultiCurveUniV4(address(currency));

        (address coinAddress, ) = IZoraFactory(deployment.zoraFactory).deploy(
            creator,
            owners,
            "https://test.com",
            "Testcoin",
            "TEST",
            poolConfig,
            createReferral,
            address(0),
            "",
            salt
        );

        coin = ICoin(coinAddress);
    }

    function _swap(address currencyIn, uint128 amountIn, ICoin coin, address trader, address tradeReferral) internal returns (uint256 amountOut) {
        uint128 minAmountOut = 0;

        PoolKey memory poolKey = coin.getPoolKey();

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

        address tradeReferral = 0xC077e4cC02fa01A5b7fAca1acE9BBe9f5ac5Af9F;

        // MockERC20 currency = _deployMockCurrency();

        // ICoin backingCoin = _deployMockCoin(address(currency), trader, createReferral, bytes32("backing coin"));
        // ICoin contentCoin = _deployMockCoin(address(backingCoin), trader, createReferral, bytes32("content coin"));

        MockERC20 currency = MockERC20(0x1b183Bd0E2c03Fc830F4d813bA37E82F9F97cA21);
        ICoin backingCoin = ICoin(0x7D74416C4c295A592Fc6F9232911C945354b253C);
        ICoin contentCoin = ICoin(0xf6d6660bcdA588F7f99e2961f279f500fB501730);

        console.log("currency", address(currency));
        console.log("backingCoin", address(backingCoin));
        console.log("contentCoin", address(contentCoin));

        // (MockERC20 currency, address coinAddress) = _deployMockCurrencyAndCoin(trader, createReferral);

        // address coinAddress = vm.parseAddress("0x58c0d8803Ae97bEF212EdFA8ba2FE303670cca9D");
        // console.log("currency", address(currency));
        // console.log("coinAddress", coinAddress);

        // swap in 2 ether of currency into the coin
        uint128 amountIn = 2 ether;
        currency.mint(trader, amountIn);

        // swap some currency into the backing coin
        uint256 backingCoinReceived = _swap(address(currency), amountIn, backingCoin, trader, tradeReferral);

        // swap balance of backing coin into the content coin
        uint256 contentCoinReceived = _swap(address(backingCoin), uint128(backingCoinReceived), contentCoin, trader, tradeReferral);

        // swap balance of content coin into the currency
        _swap(address(contentCoin), uint128(contentCoinReceived), contentCoin, trader, tradeReferral);

        vm.stopBroadcast();
    }
}
