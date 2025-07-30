// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

interface IRewardsErrors {
    error CREATOR_FUNDS_RECIPIENT_NOT_SET();
    error INVALID_ADDRESS_ZERO();
    error INVALID_ETH_AMOUNT();
    error ONLY_CREATE_REFERRAL();
}
