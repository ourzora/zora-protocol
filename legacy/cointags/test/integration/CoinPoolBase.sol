// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import "forge-std/Test.sol";

import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";
import {CointagFactoryImpl} from "../../src/CointagFactoryImpl.sol";
import {CointagImpl} from "../../src/CointagImpl.sol";
import {IWETH} from "@zoralabs/shared-contracts/interfaces/IWETH.sol";
import {IProtocolRewards} from "@zoralabs/shared-contracts/interfaces/IProtocolRewards.sol";
import {IUniswapV3Pool} from "@zoralabs/shared-contracts/interfaces/uniswap/IUniswapV3Pool.sol";
import {ICointag} from "../../src/interfaces/ICointag.sol";
import {BaseTest} from "../BaseTest.sol";
import {IBurnableERC20} from "../../src/interfaces/IBurnableERC20.sol";

abstract contract CoinPoolBase is Test {
    CointagFactoryImpl immutable cointagFactory = CointagFactoryImpl(payable(address(0x7777777BbD0b88aD5F3b5f4c89C6B60D74b9774F)));
    IProtocolRewards immutable protocolRewards = IProtocolRewards(address(0x7777777F279eba3d3Ad8F4E708545291A6fDBA8B));

    function _testDeployedCointagCreateAndBurn(address pool, string memory tokenName, string memory uniswapVersion) internal {
        console2.log("Testing ", tokenName, " at ", vm.toString(pool));

        address creatorRewardRecipient = makeAddr("creatorRewardRecipient");
        uint256 percentageToBuyBurn = 1000;

        if (!Strings.equal(uniswapVersion, "v3")) {
            vm.expectRevert(ICointag.NotUniswapV3Pool.selector);
            ICointag coinTag = cointagFactory.getOrCreateCointag(creatorRewardRecipient, pool, percentageToBuyBurn, bytes(tokenName));
        } else {
            ICointag coinTag = cointagFactory.getOrCreateCointag(creatorRewardRecipient, pool, percentageToBuyBurn, bytes(tokenName));
            protocolRewards.deposit{value: 0.1 ether}(address(coinTag), bytes4(0), "");

            coinTag.pull();
        }
    }

    function _testNewCointagCreateAndBurn(address pool, string memory tokenName, string memory uniswapVersion) internal {
        address creatorRewardRecipient = makeAddr("creatorRewardRecipient");
        uint256 percentageToBuyBurn = 1000;

        // update code
        address newImpl = address(new CointagImpl(address(protocolRewards), address(0x4200000000000000000000000000000000000006), address(0x1)));
        vm.etch(cointagFactory.cointagImplementation(), newImpl.code);

        if (!Strings.equal(uniswapVersion, "v3")) {
            vm.expectRevert(ICointag.NotUniswapV3Pool.selector);
            ICointag coinTag = cointagFactory.getOrCreateCointag(creatorRewardRecipient, pool, percentageToBuyBurn, bytes(tokenName));
        } else {
            ICointag coinTag = cointagFactory.getOrCreateCointag(creatorRewardRecipient, pool, percentageToBuyBurn, bytes(tokenName));

            protocolRewards.deposit{value: 0.1 ether}(address(coinTag), bytes4(0), "");

            coinTag.pull();
        }
    }
}
