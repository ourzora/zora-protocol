// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

interface IRewardsManager {
    event RewardsAdded(bytes4 indexed rewardType, address recipient, uint256 amount);
    event RewardsAdded(bytes4 indexed rewardType, address recipient1, uint256 amount1, address recipient2, uint256 amount2);
    event RewardsAdded(
        bytes4 indexed rewardType,
        address recipient1,
        uint256 amount1,
        address recipient2,
        uint256 amount2,
        address recipient3,
        uint256 amount3
    );
    event RewardsAdded(
        bytes4 indexed rewardType,
        address recipient1,
        uint256 amount1,
        address recipient2,
        uint256 amount2,
        address recipient3,
        uint256 amount3,
        address recipient4,
        uint256 amount4
    );
    event RewardsAdded(
        bytes4 indexed rewardType,
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
    );

    error INVALID_AMOUNT();
    error FAILED_WITHDRAW();

    function addReward(bytes4 rewardType, address recipient, uint256 amount) external payable;

    function addReward(bytes4 rewardType, address recipient1, uint256 amount1, address recipient2, uint256 amount2) external payable;

    function addReward(
        bytes4 rewardType,
        address recipient1,
        uint256 amount1,
        address recipient2,
        uint256 amount2,
        address recipient3,
        uint256 amount3
    ) external payable;

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
    ) external payable;

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
    ) external payable;

    function withdrawReward() external;

    function withdrawReward(address recipient) external;
}
