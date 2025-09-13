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

    function _deployCoin(
        address currency,
        address creator,
        string memory name,
        string memory symbol,
        string memory uri,
        address createReferral,
        bytes32 salt
    ) internal returns (ICoin coin) {
        CoinsDeployment memory deployment = readDeployment();
        address[] memory owners = new address[](1);
        owners[0] = creator;

        bytes memory poolConfig = CoinConfigurationVersions.defaultDopplerMultiCurveUniV4(address(currency));

        (address coinAddress, ) = IZoraFactory(deployment.zoraFactory).deploy(
            creator,
            owners,
            uri,
            name,
            symbol,
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

        require(block.chainid == 8453, "only on base");

        address zora = 0x1111111111166b7FE7bd91427724B487980aFc69;

        vm.startBroadcast(trader);

        address createReferral = 0xC077e4cC02fa01A5b7fAca1acE9BBe9f5ac5Af9F;

        ICoin backingCoin = _deployCoin(zora, trader, "Backing Coin", "BACK", "https://testc.com", createReferral, bytes32("creator"));
        ICoin contentCoin = _deployCoin(
            address(backingCoin),
            trader,
            "Content Coin",
            "CONTENT",
            "https://content.com",
            createReferral,
            bytes32("content coin")
        );
        // ICoin backingCoin = ICoin(0xeA734b5997F35cD469921cCa7BB9A03C104f2f64);
        // ICoin contentCoin = ICoin(0x72218BFEEc7D556BD3Dd8eFf2a317CEd49533769);

        console.log("backingCoin", address(backingCoin));
        console.log("contentCoin", address(contentCoin));
        // console.log("currency", address(currency));

        // (MockERC20 currency, address coinAddress) = _deployMockCurrencyAndCoin(trader, createReferral);

        // address coinAddress = vm.parseAddress("0x58c0d8803Ae97bEF212EdFA8ba2FE303670cca9D");
        // console.log("currency", address(currency));
        // console.log("coinAddress", coinAddress);

        // // swap in 2 ether of currency into the coin
        // uint128 amountIn = uint128(IERC20(zora).balanceOf(trader));
        // // currency.mint(trader, amountIn);

        // // // swap some currency into the backing coin
        // uint256 backingCoinReceived = _swap(zora, amountIn, backingCoin, trader, tradeReferral);

        // // // swap balance of backing coin into the content coin
        // uint256 contentCoinReceived = _swap(address(backingCoin), uint128(backingCoinReceived), contentCoin, trader, tradeReferral);

        // // swap balance of content coin into the currency
        // _swap(address(contentCoin), uint128(contentCoinReceived), contentCoin, trader, tradeReferral);

        vm.stopBroadcast();
    }
}
