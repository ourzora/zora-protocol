// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

/// @title IZoraIncentiveClaim
/// @notice allocation claiming with backend-signed KYC verification and configurable expiry
/// @dev Auto-generates period IDs while supporting multiple concurrent periods and single-period claiming
interface IZoraIncentiveClaim {
    /// @notice Allocation data structure
    struct Allocation {
        address user;
        uint256 amount;
    }

    /// @notice Period information structure
    struct PeriodInfo {
        uint256 start;
        uint256 expiry;
        string label;
    }

    /// @notice Roles structure
    struct Roles {
        address allocationSetter;
        address kycVerifier;
        address fundingWallet;
    }

    /// @notice Emitted when a new period allocation is set
    /// @param periodId Period identifier
    /// @param label Human-readable label for this allocation period
    /// @param allocations Array of allocation data
    /// @param startTime When this period starts
    /// @param endTime When this period expires
    event AllocationsSet(uint256 indexed periodId, string indexed label, Allocation[] allocations, uint256 startTime, uint256 endTime);

    /// @notice Emitted when allocations are updated for an existing period
    /// @param periodId Period identifier
    /// @param allocations Array of allocation data
    event AllocationsUpdated(uint256 indexed periodId, Allocation[] allocations);

    /// @notice Emitted when a user claims tokens
    /// @param account Address earning rewards
    /// @param claimTo Address receiving tokens
    /// @param periodId Period claimed
    /// @param amount Tokens claimed
    event Claimed(address indexed account, address indexed claimTo, uint256 periodId, uint256 amount);

    /// @notice Emitted when roles are updated (owner managed separately by Ownable2Step)
    /// @param newAllocationSetter New allocation setter address
    /// @param newKycVerifier New KYC verifier address
    /// @param newFundingWallet New funding wallet address
    event RolesUpdated(address indexed newAllocationSetter, address indexed newKycVerifier, address indexed newFundingWallet);

    /// @notice Get start timestamp for a specific period
    /// @param periodId The period identifier
    /// @return The start timestamp for the period
    function periodStart(uint256 periodId) external view returns (uint256);

    /// @notice Get expiry timestamp for a specific period
    /// @param periodId The period identifier
    /// @return The expiry timestamp for the period
    function periodExpiry(uint256 periodId) external view returns (uint256);

    /// @notice Get the label for a specific period
    /// @param periodId The period identifier
    /// @return The human-readable label for the period
    function periodLabels(uint256 periodId) external view returns (string memory);

    /// @notice Get allocation for a user for a specific period
    function periodAllocations(uint256 periodId, address user) external view returns (uint256);

    /// @notice Get the next period ID that will be assigned
    function nextPeriodId() external view returns (uint256);

    /// @notice Get all roles
    /// @return The complete roles structure
    function getRoles() external view returns (Roles memory);

    /// @notice Set allocations for a new period
    /// @param periodId Period identifier (must equal nextPeriodId for new periods)
    /// @param label Human-readable label for this allocation period
    /// @param allocations Array of allocation data
    /// @param startTime Period start timestamp
    /// @param endTime Period end timestamp
    function setAllocations(uint256 periodId, string calldata label, Allocation[] calldata allocations, uint256 startTime, uint256 endTime) external;

    /// @notice Update allocations for an existing period
    /// @param periodId Period identifier (must be existing period)
    /// @param allocations Array of allocation data
    function updateAllocations(uint256 periodId, Allocation[] calldata allocations) external;

    /// @notice Claim allocated tokens using backend signature
    /// @param account Address earning rewards
    /// @param claimTo Address receiving tokens
    /// @param periodId Period to claim
    /// @param deadline Signature expiration timestamp
    /// @param signature Backend signature authorizing claim
    function claim(address account, address claimTo, uint256 periodId, uint256 deadline, bytes calldata signature) external;
}
