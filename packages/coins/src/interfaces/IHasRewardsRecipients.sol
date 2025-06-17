// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

interface IHasRewardsRecipients {
    function payoutRecipient() external view returns (address);

    function platformReferrer() external view returns (address);

    function protocolRewardRecipient() external view returns (address);

    function dopplerFeeRecipient() external view returns (address);
}
