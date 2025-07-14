// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

/// @notice Signed message struct for executing a sponsored mint from MINTs
/// @dev A part of the ZORA MINTs contracts
struct SponsoredMintBatch {
    address verifier;
    address from;
    address payable destination;
    bytes data;
    uint256 expectedRedeemAmount;
    uint256 totalAmount;
    uint256[] ids;
    uint256[] quantities;
    uint256 nonce;
    uint256 deadline;
}

struct SponsoredSpend {
    address verifier;
    address from;
    address payable destination;
    bytes data;
    uint256 expectedInputAmount;
    uint256 totalAmount;
    uint256 nonce;
    uint256 deadline;
}

/// @notice External interface for this function
interface ISponsoredSparksSpender {
    error NoMoreFundsToSponsor();
    error NotZoraSparks1155();
    error NotExpectingReceive();
    error ERC20NotSupported(uint256 tokenId);
    error TransferFailed(bytes data);
    error UnknownUserAction();
    error CallFailed(bytes data);
    error WithdrawFailed();
    error SingleTransferNotSupported();
    error IdsMismatch();
    error ValuesMismatch();
    error UnknownAction();
    error RedeemAmountIsIncorrect(uint256 expectedRedeemAmount, uint256 transientReceivedAmount);
    error VerifierNotAllowed(address verifier);
    error NonceUsed();
    error LengthMismatch();
    error SignatureExpired();
    error InvalidSignature();
    error SenderNotAllowedInSignature();

    event ContractFunded(address indexed sender, uint256 indexed amount);
    event SetVerifierStatus(address indexed verifier, bool indexed enabled);
    event SentSponsoredCallFromMintBalances(address indexed verifier, address indexed from, uint256 amountSpent, uint256 contractValue);

    /// @notice Hashes the signature for a sponsored mint sponsorship
    function hashSponsoredMint(SponsoredMintBatch calldata sponsorship) external view returns (bytes32);

    /// @notice Hashes the signature for a sponsored spend operation
    /// @param sponsoredSpend Sponsored spend operation to hash
    /// @return the hash of the sponsoredSpend operation
    function hashSponsoredSpend(SponsoredSpend memory sponsoredSpend) external view returns (bytes32);

    /// @notice Sponsored ETH operation execution function, this is payable to provide the base value and the rest is provided via a the signed amount
    /// @param sponsoredSpend parameters for a sponsored spend operation
    /// @param signature signature bytes from the signed sponsored spend
    function sponsoredExecute(SponsoredSpend memory sponsoredSpend, bytes memory signature) external payable;

    /// @notice Withdraws a given amount from the contract's gas tank
    /// @param amount amount to withdraw, set to full amount if 0
    function withdraw(uint256 amount) external;

    /// @notice Funds a given amount from the sender to the gas tank
    function fund() external payable;

    /// @notice Admin function to set verifier status.
    function setVerifierStatus(address verifier, bool enabled) external;
}
