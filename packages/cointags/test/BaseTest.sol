// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "forge-std/Test.sol";

import {CointagFactoryImpl} from "../src/CointagFactoryImpl.sol";
import {CointagImpl} from "../src/CointagImpl.sol";
import {CointagFactory} from "../src/proxy/CointagFactory.sol";
import {IWETH} from "@zoralabs/shared-contracts/interfaces/IWETH.sol";
import {IProtocolRewards} from "@zoralabs/shared-contracts/interfaces/IProtocolRewards.sol";
import {IUniswapV3Pool} from "@zoralabs/shared-contracts/interfaces/uniswap/IUniswapV3Pool.sol";
import {IERC20} from "@openzeppelin/contracts/interfaces/IERC20.sol";
import {ISwapRouter} from "@zoralabs/shared-contracts/interfaces/uniswap/ISwapRouter.sol";
import {ICointag} from "../src/interfaces/ICointag.sol";
import {ERC1967Utils} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {IUpgradeGate} from "@zoralabs/shared-contracts/interfaces/IUpgradeGate.sol";
import {UpgradeGate} from "../src/upgrades/UpgradeGate.sol";

contract BaseTest is Test {
    address admin = makeAddr("admin");
    address creatorRewardRecipient = makeAddr("creatorRewardRecipient");
    IWETH public weth;

    CointagFactoryImpl public factory;
    CointagFactoryImpl public factoryImpl;
    IProtocolRewards public protocolRewards;
    ISwapRouter public swapRouter;
    CointagImpl public cointag;

    IUpgradeGate public upgradeGate;

    bytes emptyBytes = new bytes(0);

    function setUp() public {
        vm.createSelectFork("base_sepolia", 19061534);
        weth = IWETH(0x4200000000000000000000000000000000000006);
        protocolRewards = IProtocolRewards(0x7777777F279eba3d3Ad8F4E708545291A6fDBA8B);
        swapRouter = ISwapRouter(0x94cC0AaC535CCDB3C01d6787D6413C739ae12bc4);

        vm.prank(admin);
        upgradeGate = new UpgradeGate("Cointags Upgrade Gate", "https://github.com/ourzora/zora-protocol");

        cointag = new CointagImpl(address(protocolRewards), address(weth), address(upgradeGate));

        factoryImpl = new CointagFactoryImpl(address(cointag));
        factory = CointagFactoryImpl(address(new CointagFactory(address(factoryImpl))));

        factory.initialize(admin);
    }

    function setupBaseFork() internal {
        vm.createSelectFork("base", 23917288);

        swapRouter = ISwapRouter(0x2626664c2603336E57B271c5C0b26F421741e481);

        vm.prank(admin);
        upgradeGate = new UpgradeGate("Cointags Upgrade Gate", "https://github.com/ourzora/zora-protocol");
        cointag = new CointagImpl(address(protocolRewards), address(weth), address(upgradeGate));

        factoryImpl = new CointagFactoryImpl(address(cointag));
        factory = CointagFactoryImpl(address(new CointagFactory(address(factoryImpl))));

        factory.initialize(admin);
    }
}
