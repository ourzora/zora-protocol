// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import {UUPSUpgradeable, ERC1967Utils} from "@openzeppelin/contracts/proxy/utils/UUPSUpgradeable.sol";
import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import {MessageHashUtils} from "@openzeppelin/contracts/utils/cryptography/MessageHashUtils.sol";
import {SignatureChecker} from "@openzeppelin/contracts/utils/cryptography/SignatureChecker.sol";

import {IEntryPoint} from "account-abstraction/contracts/interfaces/IEntryPoint.sol";
import {UserOperation} from "account-abstraction/contracts/interfaces/UserOperation.sol";
import {BaseAccount} from "account-abstraction/contracts/core/BaseAccount.sol";
import {TokenCallbackHandler} from "../utils/TokenCallbackHandler.sol";

import {IZoraAccount} from "../interfaces/IZoraAccount.sol";
import {ZoraAccountOwnership} from "../ownership/ZoraAccountOwnership.sol";
import {IZoraAccountUpgradeGate} from "../interfaces/IZoraAccountUpgradeGate.sol";

import {Magic} from "../../_imagine/Magic.sol";

contract ZoraAccountImpl is Magic, BaseAccount, TokenCallbackHandler, UUPSUpgradeable, ZoraAccountOwnership, IZoraAccount {
    using ECDSA for bytes32;

    /// @dev keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)");
    bytes32 private immutable DOMAIN_SEPARATOR_TYPEHASH = 0x8b73c3c69bb8fe3d512ecc4cf759cc79239f7b179b0ffacaa9a75d522b39400f;
    bytes32 private immutable ZA_MSG_TYPEHASH = keccak256("ZoraAccountMessage(bytes message)");
    bytes4 private immutable _1271_MAGIC_VALUE = bytes4(keccak256("isValidSignature(bytes32,bytes)"));

    /// @dev The entry point contract that can execute transactions
    IEntryPoint private immutable _entryPoint;

    /// @notice The Zora Account Upgrade Gate contract
    IZoraAccountUpgradeGate public immutable upgradeGate;

    constructor(IEntryPoint anEntryPoint, address _upgradeGate) initializer {
        _entryPoint = anEntryPoint;
        upgradeGate = IZoraAccountUpgradeGate(_upgradeGate);
    }

    function initialize(address defaultOwner) public virtual initializer {
        _setupWithAdmin(defaultOwner);

        emit ZoraAccountInitialized(_entryPoint, defaultOwner, msg.sender);
    }

    // Allows receiving native ETH
    receive() external payable {
        emit ZoraAccountReceivedEth(msg.sender, msg.value);
    }

    function entryPoint() public view override returns (IEntryPoint) {
        return _entryPoint;
    }

    function _requireFromEntryPointOrOwner() internal view {
        if (!isApprovedOwner(msg.sender) && msg.sender != address(_entryPoint)) {
            revert NotAuthorized(msg.sender);
        }
    }

    /**
     * @notice Execute a transaction. This may only be called directly by the
     * owner or by the entry point via a user operation signed by the owner.
     * @param dest The target of the transaction
     * @param value The amount of wei sent in the transaction
     * @param func The transaction's calldata
     */
    function execute(address dest, uint256 value, bytes calldata func) external {
        _requireFromEntryPointOrOwner();
        _call(dest, value, func);
    }

    function _call(address target, uint256 value, bytes memory data) internal {
        (bool success, bytes memory result) = target.call{value: value}(data);
        if (!success) {
            assembly {
                revert(add(result, 32), mload(result))
            }
        }
    }

    /**
     * @notice Execute a sequence of transactions
     * @param dest An array of the targets for each transaction in the sequence
     * @param func An array of calldata for each transaction in the sequence.
     * Must be the same length as dest, with corresponding elements representing
     * the parameters for each transaction.
     */
    function executeBatch(address[] calldata dest, bytes[] calldata func) external {
        _requireFromEntryPointOrOwner();
        if (dest.length != func.length) {
            revert ArrayLengthMismatch();
        }
        uint256 length = dest.length;
        for (uint256 i; i < length; ++i) {
            _call(dest[i], 0, func[i]);
        }
    }

    /**
     * @notice Execute a sequence of transactions
     * @param dest An array of the targets for each transaction in the sequence
     * @param value An array of value for each transaction in the sequence
     * @param func An array of calldata for each transaction in the sequence.
     * Must be the same length as dest, with corresponding elements representing
     * the parameters for each transaction.
     */
    function executeBatch(address[] calldata dest, uint256[] calldata value, bytes[] calldata func) external {
        _requireFromEntryPointOrOwner();
        if (dest.length != func.length || dest.length != value.length) {
            revert ArrayLengthMismatch();
        }
        uint256 length = dest.length;
        for (uint256 i; i < length; ++i) {
            _call(dest[i], value[i], func[i]);
        }
    }

    /*
     * Implement template method of BaseAccount.
     *
     * Uses a modified version of `SignatureChecker.isValidSignatureNow` in
     * which the digest is wrapped with an "Ethereum Signed Message" envelope
     * for the EOA-owner case but not in the ERC-1271 contract-owner case.
     */
    function _validateSignature(UserOperation calldata userOp, bytes32 userOpHash) internal view override returns (uint256 validationData) {
        bytes32 signedHash = MessageHashUtils.toEthSignedMessageHash(userOpHash);

        (address recoveredAddress, ECDSA.RecoverError error, ) = signedHash.tryRecover(userOp.signature);

        if (
            (error == ECDSA.RecoverError.NoError && isApprovedOwner(recoveredAddress)) ||
            (isApprovedOwner(recoveredAddress) && SignatureChecker.isValidERC1271SignatureNow(recoveredAddress, userOpHash, userOp.signature))
        ) {
            return 0;
        }

        return SIG_VALIDATION_FAILED;
    }

    function isValidSignature(bytes32 digest, bytes memory signature) public view override returns (bytes4) {
        // TODO these two lines can be optimized
        bytes memory messageData = encodeMessageData(abi.encode(digest));
        bytes32 messageHash = keccak256(messageData);

        address recoveredAddress = recoverSigner(messageHash, signature);

        if (isApprovedOwner(recoveredAddress)) {
            return _1271_MAGIC_VALUE;
        }

        return 0xffffffff;
    }

    function recoverSigner(bytes32 digest, bytes memory signature) private pure returns (address) {
        (uint8 v, bytes32 r, bytes32 s) = splitSignature(signature);

        address signer = ecrecover(digest, v, r, s);
        require(signer != address(0), "INVALID_SIGNATURE"); // TODO custom error & add to IZoraAccount

        return signer;
    }

    function splitSignature(bytes memory signature) private pure returns (uint8 v, bytes32 r, bytes32 s) {
        assembly {
            r := mload(add(signature, 0x20))
            s := mload(add(signature, 0x40))
            v := byte(0, mload(add(signature, 0x60)))
        }
    }

    /**
     * @notice Returns the domain separator for this contract, as defined in the EIP-712 standard.
     * @return bytes32 The domain separator hash.
     */
    function domainSeparator() public view returns (bytes32) {
        return
            keccak256(
                abi.encode(
                    DOMAIN_SEPARATOR_TYPEHASH,
                    abi.encode("ZoraAccount"), // name
                    abi.encode("1"), // version
                    block.chainid, // chainId
                    address(this) // verifying contract
                )
            );
    }

    /**
     * @notice Returns the pre-image of the message hash
     * @param message Message that should be encoded.
     * @return Encoded message.
     */
    function encodeMessageData(bytes memory message) public view returns (bytes memory) {
        bytes32 messageHash = keccak256(abi.encode(ZA_MSG_TYPEHASH, keccak256(message)));
        return abi.encodePacked("\x19\x01", domainSeparator(), messageHash);
    }

    /**
     * @notice Returns hash of a message that can be signed by owners.
     * @param message Message that should be hashed.
     * @return Message hash.
     */
    function getMessageHash(bytes memory message) public view returns (bytes32) {
        return keccak256(encodeMessageData(message));
    }

    function implementation() external view returns (address) {
        return ERC1967Utils.getImplementation();
    }

    function supportsInterface(bytes4 interfaceId) public view virtual override(ZoraAccountOwnership, TokenCallbackHandler) returns (bool) {
        return interfaceId == type(IZoraAccount).interfaceId || super.supportsInterface(interfaceId);
    }

    /// @notice Ensures the caller is authorized to upgrade the contract
    /// @dev This function is called in `upgradeTo` & `upgradeToAndCall`
    /// @param newImplementation The new implementation address
    function _authorizeUpgrade(address newImplementation) internal view override onlyOwner(msg.sender) {
        if (!upgradeGate.isRegisteredUpgradePath(ERC1967Utils.getImplementation(), newImplementation)) {
            revert();
        }
    }
}
