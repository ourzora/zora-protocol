// SPDX-License-Identifier: MIT
pragma solidity >=0.8.17;

/// @title IProtocolRewards
/// @notice The interface for deposits & withdrawals for Protocol Rewards
interface IProtocolRewards {
    /// @notice Rewards Deposit Event
    /// @param creator Creator for NFT rewards
    /// @param createReferral Creator referral
    /// @param mintReferral Mint referral user
    /// @param firstMinter First minter reward recipient
    /// @param zora ZORA recipient
    /// @param from The caller of the deposit
    /// @param creatorReward Creator reward amount
    /// @param createReferralReward Creator referral reward
    /// @param mintReferralReward Mint referral amount
    /// @param firstMinterReward First minter reward amount
    /// @param zoraReward ZORA amount
    event RewardsDeposit(
        address indexed creator,
        address indexed createReferral,
        address indexed mintReferral,
        address firstMinter,
        address zora,
        address from,
        uint256 creatorReward,
        uint256 createReferralReward,
        uint256 mintReferralReward,
        uint256 firstMinterReward,
        uint256 zoraReward
    );

    /// @notice Deposit Event
    /// @param from From user
    /// @param to To user (within contract)
    /// @param reason Optional bytes4 reason for indexing
    /// @param amount Amount of deposit
    /// @param comment Optional user comment
    event Deposit(address indexed from, address indexed to, bytes4 indexed reason, uint256 amount, string comment);

    /// @notice Withdraw Event
    /// @param from From user
    /// @param to To user (within contract)
    /// @param amount Amount of deposit
    event Withdraw(address indexed from, address indexed to, uint256 amount);

    /// @notice Cannot send to address zero
    error ADDRESS_ZERO();

    /// @notice Function argument array length mismatch
    error ARRAY_LENGTH_MISMATCH();

    /// @notice Invalid deposit
    error INVALID_DEPOSIT();

    /// @notice Invalid signature for deposit
    error INVALID_SIGNATURE();

    /// @notice Invalid withdraw
    error INVALID_WITHDRAW();

    /// @notice Signature for withdraw is too old and has expired
    error SIGNATURE_DEADLINE_EXPIRED();

    /// @notice Low-level ETH transfer has failed
    error TRANSFER_FAILED();

    /// @notice Generic function to deposit ETH for a recipient, with an optional comment
    /// @param to Address to deposit to
    /// @param to Reason system reason for deposit (used for indexing)
    /// @param comment Optional comment as reason for deposit
    function deposit(address to, bytes4 why, string calldata comment) external payable;

    /// @notice Generic function to deposit ETH for multiple recipients, with an optional comment
    /// @param recipients recipients to send the amount to, array aligns with amounts
    /// @param amounts amounts to send to each recipient, array aligns with recipients
    /// @param reasons optional bytes4 hash for indexing
    /// @param comment Optional comment to include with mint
    function depositBatch(address[] calldata recipients, uint256[] calldata amounts, bytes4[] calldata reasons, string calldata comment) external payable;

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
    ) external payable;

    /// @notice Withdraw protocol rewards
    /// @param to Withdraws from msg.sender to this address
    /// @param amount amount to withdraw
    function withdraw(address to, uint256 amount) external;

    /// @notice Withdraw rewards on behalf of an address
    /// @param to The address to withdraw for
    /// @param amount The amount to withdraw (0 for total balance)
    function withdrawFor(address to, uint256 amount) external;

    /// @notice Execute a withdraw of protocol rewards via signature
    /// @param from Withdraw from this address
    /// @param to Withdraw to this address
    /// @param amount Amount to withdraw
    /// @param deadline Deadline for the signature to be valid
    /// @param v V component of signature
    /// @param r R component of signature
    /// @param s S component of signature
    function withdrawWithSig(address from, address to, uint256 amount, uint256 deadline, uint8 v, bytes32 r, bytes32 s) external;

    /// @notice Get the balance of an account
    /// @param account The account to get the balance of
    function balanceOf(address account) external view returns (uint256);
}
