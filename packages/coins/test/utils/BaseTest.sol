// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import "forge-std/Test.sol";

import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {Address} from "@openzeppelin/contracts/utils/Address.sol";
import {ERC1967Utils} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Utils.sol";
import {IERC165} from "@openzeppelin/contracts/utils/introspection/IERC165.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";

import {ZoraFactoryImpl} from "../../src/ZoraFactoryImpl.sol";
import {ZoraFactory} from "../../src/proxy/ZoraFactory.sol";
import {Coin} from "../../src/Coin.sol";
import {CoinConstants} from "../../src/utils/CoinConstants.sol";
import {MultiOwnable} from "../../src/utils/MultiOwnable.sol";
import {ICoin} from "../../src/interfaces/ICoin.sol";
import {IERC7572} from "../../src/interfaces/IERC7572.sol";
import {IWETH} from "../../src/interfaces/IWETH.sol";
import {IAirlock} from "../../src/interfaces/IAirlock.sol";
import {INonfungiblePositionManager} from "../../src/interfaces/INonfungiblePositionManager.sol";
import {ISwapRouter} from "../../src/interfaces/ISwapRouter.sol";
import {IUniswapV3Factory} from "../../src/interfaces/IUniswapV3Factory.sol";
import {IUniswapV3Pool} from "../../src/interfaces/IUniswapV3Pool.sol";
import {IProtocolRewards} from "../../src/interfaces/IProtocolRewards.sol";
import {ProtocolRewards} from "../utils/ProtocolRewards.sol";
import {MarketConstants} from "../../src/libs/MarketConstants.sol";
contract BaseTest is Test, CoinConstants {
    using stdStorage for StdStorage;

    address internal constant PROTOCOL_REWARDS = 0x7777777F279eba3d3Ad8F4E708545291A6fDBA8B;
    address internal constant WETH_ADDRESS = 0x4200000000000000000000000000000000000006;
    address internal constant V3_FACTORY = 0x33128a8fC17869897dcE68Ed026d694621f6FDfD;
    address internal constant NONFUNGIBLE_POSITION_MANAGER = 0x03a520b32C04BF3bEEf7BEb72E919cf822Ed34f1;
    address internal constant SWAP_ROUTER = 0x2626664c2603336E57B271c5C0b26F421741e481;
    address internal constant DOPPLER_AIRLOCK = 0x660eAaEdEBc968f8f3694354FA8EC0b4c5Ba8D12;
    address internal constant USDC_ADDRESS = 0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913;
    int24 internal constant USDC_TICK_LOWER = 57200;

    struct Users {
        address factoryOwner;
        address feeRecipient;
        address creator;
        address platformReferrer;
        address buyer;
        address seller;
        address coinRecipient;
        address tradeReferrer;
    }

    uint256 internal forkId;
    IERC20Metadata internal usdc;
    IWETH internal weth;
    ProtocolRewards internal protocolRewards;
    IUniswapV3Factory internal v3Factory;
    INonfungiblePositionManager internal nonfungiblePositionManager;
    ISwapRouter internal swapRouter;
    IAirlock internal airlock;
    Users internal users;

    Coin internal coinImpl;
    ZoraFactoryImpl internal factoryImpl;
    ZoraFactoryImpl internal factory;
    Coin internal coin;
    IUniswapV3Pool internal pool;

    function setUp() public virtual {
        forkId = vm.createSelectFork("base", 28415528);

        weth = IWETH(WETH_ADDRESS);
        usdc = IERC20Metadata(USDC_ADDRESS);
        v3Factory = IUniswapV3Factory(V3_FACTORY);
        nonfungiblePositionManager = INonfungiblePositionManager(NONFUNGIBLE_POSITION_MANAGER);
        swapRouter = ISwapRouter(SWAP_ROUTER);
        airlock = IAirlock(DOPPLER_AIRLOCK);
        protocolRewards = new ProtocolRewards();

        users = Users({
            factoryOwner: makeAddr("factoryOwner"),
            feeRecipient: makeAddr("feeRecipient"),
            creator: makeAddr("creator"),
            platformReferrer: makeAddr("platformReferrer"),
            buyer: makeAddr("buyer"),
            seller: makeAddr("seller"),
            coinRecipient: makeAddr("coinRecipient"),
            tradeReferrer: makeAddr("tradeReferrer")
        });

        coinImpl = new Coin(users.feeRecipient, address(protocolRewards), WETH_ADDRESS, V3_FACTORY, SWAP_ROUTER, DOPPLER_AIRLOCK);
        factoryImpl = new ZoraFactoryImpl(address(coinImpl));
        factory = ZoraFactoryImpl(address(new ZoraFactory(address(factoryImpl))));

        ZoraFactoryImpl(factory).initialize(users.factoryOwner);

        vm.label(address(factory), "ZORA_FACTORY");
        vm.label(address(protocolRewards), "PROTOCOL_REWARDS");
        vm.label(address(nonfungiblePositionManager), "NONFUNGIBLE_POSITION_MANAGER");
        vm.label(address(v3Factory), "V3_FACTORY");
        vm.label(address(swapRouter), "SWAP_ROUTER");
        vm.label(address(weth), "WETH");
        vm.label(address(usdc), "USDC");
        vm.label(address(airlock), "AIRLOCK");
    }

    struct TradeRewards {
        uint256 creator;
        uint256 platformReferrer;
        uint256 tradeReferrer;
        uint256 protocol;
    }

    struct MarketRewards {
        uint256 creator;
        uint256 platformReferrer;
        uint256 doppler;
        uint256 protocol;
    }

    function _deployCoin() internal {
        address[] memory owners = new address[](1);
        owners[0] = users.creator;

        vm.prank(users.creator);
        (address coinAddress, ) = factory.deploy(
            users.creator,
            owners,
            "https://test.com",
            "Testcoin",
            "TEST",
            users.platformReferrer,
            address(weth),
            MarketConstants.LP_TICK_LOWER_WETH,
            0
        );

        coin = Coin(payable(coinAddress));
        pool = IUniswapV3Pool(coin.poolAddress());

        vm.label(address(coin), "COIN");
        vm.label(address(pool), "POOL");
    }

    function _deployCoinUSDCPair() internal {
        address[] memory owners = new address[](1);
        owners[0] = users.creator;

        vm.prank(users.creator);
        (address coinAddress, ) = factory.deploy(
            users.creator,
            owners,
            "https://testusdccoin.com",
            "Testusdccoin",
            "TESTUSDCCOIN",
            users.platformReferrer,
            USDC_ADDRESS,
            USDC_TICK_LOWER,
            0
        );

        coin = Coin(payable(coinAddress));
        pool = IUniswapV3Pool(coin.poolAddress());

        vm.label(address(coin), "COIN");
        vm.label(address(pool), "POOL");
    }

    function _calculateTradeRewards(uint256 ethAmount) internal pure returns (TradeRewards memory) {
        return
            TradeRewards({
                creator: (ethAmount * 5000) / 10_000,
                platformReferrer: (ethAmount * 1500) / 10_000,
                tradeReferrer: (ethAmount * 1500) / 10_000,
                protocol: (ethAmount * 2000) / 10_000
            });
    }

    function _calculateExpectedFee(uint256 ethAmount) internal pure returns (uint256) {
        uint256 feeBps = 100; // 1%
        return (ethAmount * feeBps) / 10_000;
    }

    function _calculateMarketRewards(uint256 ethAmount) internal pure returns (MarketRewards memory) {
        uint256 creator = (ethAmount * 5000) / 10_000;
        uint256 platformReferrer = (ethAmount * 2500) / 10_000;
        uint256 doppler = (ethAmount * 500) / 10_000;
        uint256 protocol = ethAmount - creator - platformReferrer - doppler;

        return MarketRewards({creator: creator, platformReferrer: platformReferrer, doppler: doppler, protocol: protocol});
    }

    function dealUSDC(address to, uint256 numUSDC) internal returns (uint256) {
        uint256 amount = numUSDC * 1e6;
        deal(address(usdc), to, amount);
        return amount;
    }

    function _getDefaultOwners() internal view returns (address[] memory owners) {
        owners = new address[](1);
        owners[0] = users.creator;
    }

    function dopplerFeeRecipient() internal view returns (address) {
        return airlock.owner();
    }
}
