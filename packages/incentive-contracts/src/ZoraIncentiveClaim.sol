// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {IZoraIncentiveClaim} from "./IZoraIncentiveClaim.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import {EIP712} from "@openzeppelin/contracts/utils/cryptography/EIP712.sol";
import {Ownable2Step, Ownable} from "@openzeppelin/contracts/access/Ownable2Step.sol";

/// @title ZoraIncentiveClaim
/// @notice Implementation for allocation claiming with backend-signed KYC verification
/// @author taayyohh
contract ZoraIncentiveClaim is IZoraIncentiveClaim, EIP712, Ownable2Step {
    using SafeERC20 for IERC20;

    /// @notice Thrown when caller is not the allocation setter
    error OnlyAllocationSetter();

    /// @notice Thrown when referencing a period that doesn't exist
    /// @param periodId The invalid period ID
    error PeriodDoesNotExist(uint256 periodId);

    /// @notice Thrown when a signature has expired
    /// @param deadline The signature deadline
    /// @param currentTime The current block timestamp
    error SignatureExpired(uint256 deadline, uint256 currentTime);

    /// @notice Thrown when signature verification fails
    /// @param expected The expected signer address
    /// @param actual The actual recovered signer address
    error InvalidSignature(address expected, address actual);

    /// @notice Thrown when trying to claim from a period that hasn't started
    /// @param periodId The period ID that hasn't started
    /// @param startTime The period's start timestamp
    error PeriodNotStarted(uint256 periodId, uint256 startTime);

    /// @notice Thrown when trying to claim from an expired period
    /// @param periodId The expired period ID
    /// @param expiry The period's expiry timestamp
    error PeriodExpired(uint256 periodId, uint256 expiry);

    /// @notice Thrown when user has already claimed from a period
    /// @param account The account that already claimed
    /// @param periodId The period already claimed from
    error AlreadyClaimed(address account, uint256 periodId);

    /// @notice Thrown when user has no allocation for a period
    /// @param account The account with no allocation
    /// @param periodId The period with no allocation
    error NoAllocation(address account, uint256 periodId);

    /// @notice Thrown when zero address is provided
    error ZeroAddress();

    /// @notice Thrown when zero amount is provided
    error ZeroAmount();

    /// @notice Thrown when period ID doesn't match expected next ID
    error InvalidPeriodId();

    /// @notice Thrown when start time is not before end time
    error InvalidTimeRange();

    /// @notice Thrown when start time is not in the future
    error StartTimeInPast();

    /// @notice Thrown when trying to modify allocations after period has started
    /// @param periodId The period that has already started
    /// @param startTime The period's start timestamp
    error PeriodAlreadyStarted(uint256 periodId, uint256 startTime);

    /// @notice Allocations per user per period
    mapping(uint256 => mapping(address => uint256)) public periodAllocations;

    /// @notice Tracks whether a user has claimed a period
    mapping(uint256 => mapping(address => bool)) public hasClaimed;

    /// @notice Period information for each period
    mapping(uint256 => PeriodInfo) public periods;

    /// @notice Start timestamps for each period (backward compatibility)
    function periodStart(uint256 periodId) public view returns (uint256) {
        return periods[periodId].start;
    }

    /// @notice Expiry timestamps for each period (backward compatibility)
    function periodExpiry(uint256 periodId) public view returns (uint256) {
        return periods[periodId].expiry;
    }

    /// @notice Labels for each period (backward compatibility)
    function periodLabels(uint256 periodId) public view returns (string memory) {
        return periods[periodId].label;
    }

    /// @notice Auto-incrementing period counter
    uint256 public nextPeriodId = 1;

    /// @notice Packed roles
    Roles public roles;

    /// @notice ERC20 token reference
    IERC20 public immutable TOKEN;

    /// @notice Typehash for claim signature verification
    bytes32 private constant CLAIM_TYPEHASH = keccak256("Claim(address account,address claimTo,uint256 periodId,uint256 deadline)");

    modifier onlyAllocationSetter() {
        _requireAllocationSetter();
        _;
    }

    function _requireAllocationSetter() internal view {
        require(msg.sender == roles.allocationSetter, OnlyAllocationSetter());
    }

    constructor(
        address _token,
        address _allocationSetter,
        address _kycVerifier,
        address _owner,
        address _fundingWallet
    ) EIP712("ZoraIncentiveClaim", "0.1.0") Ownable(_owner) {
        require(_token != address(0), ZeroAddress());
        require(_allocationSetter != address(0), ZeroAddress());
        require(_kycVerifier != address(0), ZeroAddress());
        require(_fundingWallet != address(0), ZeroAddress());

        TOKEN = IERC20(_token);
        _setRoles(_allocationSetter, _kycVerifier, _fundingWallet);
    }

    /// @notice Set allocations for a new period
    /// @param periodId Period identifier (must equal nextPeriodId for new periods)
    /// @param label Human-readable label for this allocation period
    /// @param allocations Array of allocation data
    /// @param startTime Period start timestamp
    /// @param endTime Period end timestamp
    function setAllocations(
        uint256 periodId,
        string calldata label,
        Allocation[] calldata allocations,
        uint256 startTime,
        uint256 endTime
    ) external onlyAllocationSetter {
        require(periodId == nextPeriodId, InvalidPeriodId());
        nextPeriodId++;

        require(startTime < endTime, InvalidTimeRange());
        require(startTime > block.timestamp, StartTimeInPast());

        periods[periodId] = PeriodInfo({start: startTime, expiry: endTime, label: label});

        _processAllocations(periodId, allocations);

        emit AllocationsSet(periodId, label, allocations, startTime, endTime);
    }

    /// @notice Update allocations for an existing period
    /// @param periodId Period identifier (must be existing period)
    /// @param allocations Array of allocation data
    function updateAllocations(uint256 periodId, Allocation[] calldata allocations) external onlyAllocationSetter {
        require(periodId < nextPeriodId, PeriodDoesNotExist(periodId));
        PeriodInfo storage periodInfo = periods[periodId];
        require(block.timestamp < periodInfo.start, PeriodAlreadyStarted(periodId, periodInfo.start));

        _processAllocations(periodId, allocations);

        emit AllocationsUpdated(periodId, allocations);
    }

    /// @notice Claim allocated tokens using backend signature
    /// @param account Address earning rewards
    /// @param claimTo Address receiving tokens
    /// @param periodId Period to claim
    /// @param deadline Signature expiration timestamp
    /// @param signature Backend signature authorizing claim
    function claim(address account, address claimTo, uint256 periodId, uint256 deadline, bytes calldata signature) external {
        require(block.timestamp <= deadline, SignatureExpired(deadline, block.timestamp));

        // Verify signature
        _verifySignedByKycVerifier(account, claimTo, periodId, deadline, signature);

        uint256 amount = _processClaim(account, periodId);

        emit Claimed(account, claimTo, periodId, amount);
        TOKEN.safeTransferFrom(roles.fundingWallet, claimTo, amount);
    }

    function _verifySignedByKycVerifier(address account, address claimTo, uint256 periodId, uint256 deadline, bytes calldata signature) internal view {
        bytes32 structHash = keccak256(abi.encode(CLAIM_TYPEHASH, account, claimTo, periodId, deadline));
        bytes32 hash = _hashTypedDataV4(structHash);
        address signer = ECDSA.recover(hash, signature);
        require(signer == roles.kycVerifier, InvalidSignature(roles.kycVerifier, signer));
    }

    function _processClaim(address account, uint256 periodId) internal returns (uint256) {
        PeriodInfo storage periodInfo = periods[periodId];
        require(block.timestamp >= periodInfo.start, PeriodNotStarted(periodId, periodInfo.start));
        require(block.timestamp < periodInfo.expiry, PeriodExpired(periodId, periodInfo.expiry));
        require(!hasClaimed[periodId][account], AlreadyClaimed(account, periodId));

        uint256 allocation = periodAllocations[periodId][account];
        require(allocation != 0, NoAllocation(account, periodId));

        hasClaimed[periodId][account] = true;
        return allocation;
    }

    /// @notice Get all roles
    /// @return The complete roles structure
    function getRoles() external view returns (Roles memory) {
        return roles;
    }

    /// @notice Set roles (owner only) - pass current address to keep unchanged
    /// @param newAllocationSetter New allocation setter address (or current to keep unchanged)
    /// @param newKycVerifier New KYC verifier address (or current to keep unchanged)
    /// @param newFundingWallet New funding wallet address (or current to keep unchanged)
    function setRoles(address newAllocationSetter, address newKycVerifier, address newFundingWallet) external onlyOwner {
        _setRoles(newAllocationSetter, newKycVerifier, newFundingWallet);
    }

    /// @notice Internal function to set roles and emit events
    function _setRoles(address newAllocationSetter, address newKycVerifier, address newFundingWallet) internal {
        require(newAllocationSetter != address(0), ZeroAddress());
        require(newKycVerifier != address(0), ZeroAddress());
        require(newFundingWallet != address(0), ZeroAddress());

        roles = Roles({allocationSetter: newAllocationSetter, kycVerifier: newKycVerifier, fundingWallet: newFundingWallet});

        emit RolesUpdated(newAllocationSetter, newKycVerifier, newFundingWallet);
    }

    /// @notice Helper function to process and validate allocations
    /// @param periodId Period identifier
    /// @param allocations Array of allocation data
    function _processAllocations(uint256 periodId, Allocation[] calldata allocations) internal {
        for (uint256 i = 0; i < allocations.length; i++) {
            address user = allocations[i].user;
            uint256 amount = allocations[i].amount;

            require(user != address(0), ZeroAddress());

            periodAllocations[periodId][user] = amount;
        }
    }
}
