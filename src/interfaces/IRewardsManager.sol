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
