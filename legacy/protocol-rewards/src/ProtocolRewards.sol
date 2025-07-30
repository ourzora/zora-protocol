// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import {Enjoy} from "../_imagine/Enjoy.sol";
import {EIP712} from "./lib/EIP712.sol";
import {IProtocolRewards} from "@zoralabs/shared-contracts/interfaces/IProtocolRewards.sol";

/// @title ProtocolRewards
/// @notice Manager of deposits & withdrawals for protocol rewards
contract ProtocolRewards is Enjoy, IProtocolRewards, EIP712 {
    /// @notice The EIP-712 typehash for gasless withdraws
    bytes32 public constant WITHDRAW_TYPEHASH = keccak256("Withdraw(address from,address to,uint256 amount,uint256 nonce,uint256 deadline)");

    /// @notice An account's balance
    mapping(address => uint256) public balanceOf;

    /// @notice An account's nonce for gasless withdraws
    mapping(address => uint256) public nonces;

    constructor() payable EIP712("ProtocolRewards", "1") {}

    /// @notice The total amount of ETH held in the contract
    function totalSupply() external view returns (uint256) {
        return address(this).balance;
    }

    /// @notice Generic function to deposit ETH for a recipient, with an optional comment
    /// @param to Address to deposit to
    /// @param to Reason system reason for deposit (used for indexing)
    /// @param comment Optional comment as reason for deposit
    function deposit(address to, bytes4 reason, string calldata comment) external payable {
        if (to == address(0)) {
            revert ADDRESS_ZERO();
        }

        balanceOf[to] += msg.value;

        emit Deposit(msg.sender, to, reason, msg.value, comment);
    }

    /// @notice Generic function to deposit ETH for multiple recipients, with an optional comment
    /// @param recipients recipients to send the amount to, array aligns with amounts
    /// @param amounts amounts to send to each recipient, array aligns with recipients
    /// @param reasons optional bytes4 hash for indexing
    /// @param comment Optional comment to include with mint
    function depositBatch(address[] calldata recipients, uint256[] calldata amounts, bytes4[] calldata reasons, string calldata comment) external payable {
        uint256 numRecipients = recipients.length;

        if (numRecipients != amounts.length || numRecipients != reasons.length) {
            revert ARRAY_LENGTH_MISMATCH();
        }

        uint256 expectedTotalValue;

        for (uint256 i; i < numRecipients; ) {
            expectedTotalValue += amounts[i];

            unchecked {
                ++i;
            }
        }

        if (msg.value != expectedTotalValue) {
            revert INVALID_DEPOSIT();
        }

        address currentRecipient;
        uint256 currentAmount;

        for (uint256 i; i < numRecipients; ) {
            currentRecipient = recipients[i];
            currentAmount = amounts[i];

            if (currentRecipient == address(0)) {
                revert ADDRESS_ZERO();
            }

            balanceOf[currentRecipient] += currentAmount;

            emit Deposit(msg.sender, currentRecipient, reasons[i], currentAmount, comment);

            unchecked {
                ++i;
            }
        }
    }

    /// @notice Used by Zora ERC-721 & ERC-1155 contracts to deposit protocol rewards
    /// @param creator Creator for NFT rewards
    /// @param creatorReward Creator reward amount
    /// @param createReferral Creator referral
    /// @param createReferralReward Creator referral reward
    /// @param mintReferral Mint referral user
    /// @param mintReferralReward Mint referral amount
    /// @param firstMinter First minter reward
    /// @param firstMinterReward First minter reward amount
    /// @param zora ZORA recipient
    /// @param zoraReward ZORA amount
    function depositRewards(
        address creator,
        uint256 creatorReward,
        address createReferral,
        uint256 createReferralReward,
        address mintReferral,
        uint256 mintReferralReward,
        address firstMinter,
        uint256 firstMinterReward,
        address zora,
        uint256 zoraReward
    ) external payable {
        if (msg.value != (creatorReward + createReferralReward + mintReferralReward + firstMinterReward + zoraReward)) {
            revert INVALID_DEPOSIT();
        }

        unchecked {
            if (creator != address(0)) {
                balanceOf[creator] += creatorReward;
            }
            if (createReferral != address(0)) {
                balanceOf[createReferral] += createReferralReward;
            }
            if (mintReferral != address(0)) {
                balanceOf[mintReferral] += mintReferralReward;
            }
            if (firstMinter != address(0)) {
                balanceOf[firstMinter] += firstMinterReward;
            }
            if (zora != address(0)) {
                balanceOf[zora] += zoraReward;
            }
        }

        emit RewardsDeposit(
            creator,
            createReferral,
            mintReferral,
            firstMinter,
            zora,
            msg.sender,
            creatorReward,
            createReferralReward,
            mintReferralReward,
            firstMinterReward,
            zoraReward
        );
    }

    /// @notice Withdraw protocol rewards
    /// @param to Withdraws from msg.sender to this address
    /// @param amount Amount to withdraw (0 for total balance)
    function withdraw(address to, uint256 amount) external {
        if (to == address(0)) {
            revert ADDRESS_ZERO();
        }

        address owner = msg.sender;

        if (amount > balanceOf[owner]) {
            revert INVALID_WITHDRAW();
        }

        if (amount == 0) {
            amount = balanceOf[owner];
        }

        balanceOf[owner] -= amount;

        emit Withdraw(owner, to, amount);

        (bool success, ) = to.call{value: amount}("");

        if (!success) {
            revert TRANSFER_FAILED();
        }
    }

    /// @notice Withdraw rewards on behalf of an address
    /// @param to The address to withdraw for
    /// @param amount The amount to withdraw (0 for total balance)
    function withdrawFor(address to, uint256 amount) external {
        if (to == address(0)) {
            revert ADDRESS_ZERO();
        }

        if (amount > balanceOf[to]) {
            revert INVALID_WITHDRAW();
        }

        if (amount == 0) {
            amount = balanceOf[to];
        }

        balanceOf[to] -= amount;

        emit Withdraw(to, to, amount);

        (bool success, ) = to.call{value: amount}("");

        if (!success) {
            revert TRANSFER_FAILED();
        }
    }

    /// @notice Execute a withdraw of protocol rewards via signature
    /// @param from Withdraw from this address
    /// @param to Withdraw to this address
    /// @param amount Amount to withdraw (0 for total balance)
    /// @param deadline Deadline for the signature to be valid
    /// @param v V component of signature
    /// @param r R component of signature
    /// @param s S component of signature
    function withdrawWithSig(address from, address to, uint256 amount, uint256 deadline, uint8 v, bytes32 r, bytes32 s) external {
        if (block.timestamp > deadline) {
            revert SIGNATURE_DEADLINE_EXPIRED();
        }

        bytes32 withdrawHash;

        unchecked {
            withdrawHash = keccak256(abi.encode(WITHDRAW_TYPEHASH, from, to, amount, nonces[from]++, deadline));
        }

        bytes32 digest = _hashTypedDataV4(withdrawHash);

        address recoveredAddress = ecrecover(digest, v, r, s);

        if (recoveredAddress == address(0) || recoveredAddress != from) {
            revert INVALID_SIGNATURE();
        }

        if (to == address(0)) {
            revert ADDRESS_ZERO();
        }

        if (amount > balanceOf[from]) {
            revert INVALID_WITHDRAW();
        }

        if (amount == 0) {
            amount = balanceOf[from];
        }

        balanceOf[from] -= amount;

        emit Withdraw(from, to, amount);

        (bool success, ) = to.call{value: amount}("");

        if (!success) {
            revert TRANSFER_FAILED();
        }
    }
}
