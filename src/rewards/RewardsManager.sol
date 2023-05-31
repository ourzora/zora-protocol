// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import {IRewardsManager} from "../interfaces/IRewardsManager.sol";

contract RewardsManager is IRewardsManager {
    bytes4 public constant ZORA_FREE_MINT_REWARD_TYPE = bytes4(keccak256("ZORA_FREE_MINT_REWARDS"));
    bytes4 public constant ZORA_PAID_MINT_REWARD_TYPE = bytes4(keccak256("ZORA_PAID_MINT_REWARDS"));

    mapping(address => uint256) public balanceOf;

    function addReward(bytes4 rewardType, address recipient, uint256 amount) external payable {
        if (msg.value != amount) {
            revert INVALID_AMOUNT();
        }

        balanceOf[recipient] += amount;

        emit RewardsAdded(rewardType, recipient, amount);
    }

    function addReward(bytes4 rewardType, address recipient1, uint256 amount1, address recipient2, uint256 amount2) external payable {
        if (msg.value != (amount1 + amount2)) {
            revert INVALID_AMOUNT();
        }

        balanceOf[recipient1] += amount1;
        balanceOf[recipient2] += amount2;

        emit RewardsAdded(rewardType, recipient1, amount1, recipient2, amount2);
    }

    function addReward(
        bytes4 rewardType,
        address recipient1,
        uint256 amount1,
        address recipient2,
        uint256 amount2,
        address recipient3,
        uint256 amount3
    ) external payable {
        if (msg.value != (amount1 + amount2 + amount3)) {
            revert INVALID_AMOUNT();
        }

        balanceOf[recipient1] += amount1;
        balanceOf[recipient2] += amount2;
        balanceOf[recipient3] += amount3;

        emit RewardsAdded(rewardType, recipient1, amount1, recipient2, amount2, recipient3, amount3);
    }

    function addReward(
        bytes4 rewardType,
        address recipient1,
        uint256 amount1,
        address recipient2,
        uint256 amount2,
        address recipient3,
        uint256 amount3,
        address recipient4,
        uint256 amount4
    ) external payable {
        if (msg.value != (amount1 + amount2 + amount3 + amount4)) {
            revert INVALID_AMOUNT();
        }

        balanceOf[recipient1] += amount1;
        balanceOf[recipient2] += amount2;
        balanceOf[recipient3] += amount3;
        balanceOf[recipient4] += amount4;

        emit RewardsAdded(rewardType, recipient1, amount1, recipient2, amount2, recipient3, amount3, recipient4, amount4);
    }

    function addReward(
        bytes4 rewardType,
        address recipient1,
        uint256 amount1,
        address recipient2,
        uint256 amount2,
        address recipient3,
        uint256 amount3,
        address recipient4,
        uint256 amount4,
        address recipient5,
        uint256 amount5
    ) external payable {
        if (msg.value != (amount1 + amount2 + amount3 + amount4 + amount5)) {
            revert INVALID_AMOUNT();
        }

        balanceOf[recipient1] += amount1;
        balanceOf[recipient2] += amount2;
        balanceOf[recipient3] += amount3;
        balanceOf[recipient4] += amount4;
        balanceOf[recipient5] += amount5;

        emit RewardsAdded(rewardType, recipient1, amount1, recipient2, amount2, recipient3, amount3, recipient4, amount4, recipient5, amount5);
    }

    function withdrawReward() external {
        address user = msg.sender;

        uint256 amount = balanceOf[user];

        delete balanceOf[user];

        (bool success, ) = user.call{value: amount, gas: 110_000}("");

        if (!success) {
            revert FAILED_WITHDRAW();
        }
    }

    function withdrawReward(address recipient) external {
        address user = msg.sender;

        uint256 amount = balanceOf[user];

        delete balanceOf[user];

        (bool success, ) = recipient.call{value: amount, gas: 110_000}("");

        if (!success) {
            revert FAILED_WITHDRAW();
        }
    }
}
