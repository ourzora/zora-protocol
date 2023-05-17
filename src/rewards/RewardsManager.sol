// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

interface IRewardsManager {
    event RewardsAdded(address indexed recipient1, uint256 amount1, address indexed recipient2, uint256 amount2, address indexed recipient3, uint256 amount3);
    event RewardsAdded(
        address indexed recipient1,
        uint256 amount1,
        address indexed recipient2,
        uint256 amount2,
        address indexed recipient3,
        uint256 amount3,
        address recipient4,
        uint256 amount4
    );

    error INVALID_AMOUNT();
    error FAILED_WITHDRAW();

    function addReward(address recipient1, uint256 amount1, address recipient2, uint256 amount2, address recipient3, uint256 amount3) external payable;

    function addReward(
        address recipient1,
        uint256 amount1,
        address recipient2,
        uint256 amount2,
        address recipient3,
        uint256 amount3,
        address recipient4,
        uint256 amount4
    ) external payable;

    function withdrawReward() external;
}

/** TODO
- variants of addReward params and events
- withdraw w/ recipient
- withdraw w/ sig?
 */
contract RewardsManager is IRewardsManager {
    mapping(address => uint256) public ethBalance;

    function addReward(address recipient1, uint256 amount1, address recipient2, uint256 amount2, address recipient3, uint256 amount3) external payable {
        if (msg.value != (amount1 + amount2 + amount3)) {
            revert INVALID_AMOUNT();
        }

        ethBalance[recipient1] += amount1;
        ethBalance[recipient2] += amount2;
        ethBalance[recipient3] += amount3;

        emit RewardsAdded(recipient1, amount1, recipient2, amount2, recipient3, amount3);
    }

    function addReward(
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

        ethBalance[recipient1] += amount1;
        ethBalance[recipient2] += amount2;
        ethBalance[recipient3] += amount3;
        ethBalance[recipient4] += amount4;

        emit RewardsAdded(recipient1, amount1, recipient2, amount2, recipient3, amount3, recipient4, amount4);
    }

    function withdrawReward() external {
        address user = msg.sender;

        uint256 amount = ethBalance[user];

        delete ethBalance[user];

        (bool success, ) = user.call{value: amount, gas: 110_000}("");

        if (!success) {
            revert FAILED_WITHDRAW();
        }
    }
}
