// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {CointagsDeployerBase} from "./CointagsDeployerBase.sol";
import {IProtocolRewards} from "@zoralabs/shared-contracts/interfaces/IProtocolRewards.sol";
import {CointagFactoryImpl} from "../src/CointagFactoryImpl.sol";
import {ICointag} from "../src/interfaces/ICointag.sol";

contract ExecuteTestCointagTransaction is CointagsDeployerBase {
    function run() public {
        CointagsDeployment memory deployment = readDeployment();
        vm.startBroadcast();

        // should be run only on base sepolia
        if (block.chainid != 84532) {
            revert("This script should only be run on base sepolia");
        }

        // this is a known pool with some liquidity
        address pool = vm.parseAddress("0x1c251dc66d5259fd1e2d1cf151a83191ca4898d9");
        address creator = 0xf69fEc6d858c77e969509843852178bd24CAd2B6;

        // set percentage to be 5, considering basis of 10_000
        uint256 percentageToBuyBurn = 500;

        // get cointag factory
        CointagFactoryImpl cointagFactory = CointagFactoryImpl(deployment.cointagFactoryImpl);

        // create cointag
        ICointag cointag = cointagFactory.getOrCreateCointag(creator, pool, percentageToBuyBurn, bytes(""));

        // deposit rewards into protocol rewards, setting cointag as reward recipient
        IProtocolRewards(PROTOCOL_REWARDS).deposit{value: 0.001 ether}(address(cointag), 0, "Cointag test setup");

        // get cointag factory
        cointag.pull();

        vm.stopBroadcast();
    }
}
