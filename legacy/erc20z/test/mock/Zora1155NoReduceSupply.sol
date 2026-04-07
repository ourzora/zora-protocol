// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import {ERC1155} from "@openzeppelin/contracts/token/ERC1155/ERC1155.sol";
import {ERC1155Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC1155/ERC1155Upgradeable.sol";
import {IMinter1155} from "../../src/interfaces/IMinter1155.sol";
import {IReduceSupply} from "@zoralabs/shared-contracts/interfaces/IReduceSupply.sol";

// Does not have reduceSupply function

contract Zora1155 is ERC1155 {
    ///                                                          ///
    ///                                                          ///
    ///                                                          ///

    event SetupNewToken(uint256 indexed tokenId, address indexed sender, string newURI, uint256 maxSupply);
    event UpdatedToken(address indexed from, uint256 indexed tokenId, TokenData tokenData);
    event UpdatedPermissions(uint256 indexed tokenId, address indexed user, uint256 indexed permissions);

    error UserMissingRoleForToken(address user, uint256 tokenId, uint256 role);

    ///                                                          ///
    ///                                                          ///
    ///                                                          ///

    uint256 public constant CONTRACT_BASE_ID = 0;
    /// @notice This user role allows for any action to be performed
    uint256 public constant PERMISSION_BIT_ADMIN = 2 ** 1;
    /// @notice This user role allows for only mint actions to be performed
    uint256 public constant PERMISSION_BIT_MINTER = 2 ** 2;
    /// @notice This user role allows for only managing sales configurations
    uint256 public constant PERMISSION_BIT_SALES = 2 ** 3;
    /// @notice This user role allows for only managing metadata configuration
    uint256 public constant PERMISSION_BIT_METADATA = 2 ** 4;
    /// @notice This user role allows for only withdrawing funds and setting funds withdraw address
    uint256 public constant PERMISSION_BIT_FUNDS_MANAGER = 2 ** 5;

    ///                                                          ///
    ///                                                          ///
    ///                                                          ///

    constructor(address _creator) ERC1155("") {
        creator = _creator;
    }

    ///                                                          ///
    ///                                                          ///
    ///                                                          ///

    address internal creator;

    uint256 public nextTokenId;

    mapping(uint256 => TokenData) internal tokens;

    mapping(uint256 => mapping(address => uint256)) public permissions;

    mapping(uint256 => address) public createReferrals;

    ///                                                          ///
    ///                                                          ///
    ///                                                          ///

    struct TokenData {
        string uri;
        uint256 maxSupply;
        uint256 totalMinted;
    }

    function getTokenInfo(uint256 tokenId) external view returns (TokenData memory) {
        return tokens[tokenId];
    }

    function getCreatorRewardRecipient(uint256) external view returns (address) {
        return creator;
    }

    ///                                                          ///
    ///                                                          ///
    ///                                                          ///

    function setupNewToken(string calldata newURI, uint256 maxSupply) public returns (uint256) {
        uint256 tokenId = _setupNewTokenAndPermission(newURI, maxSupply, msg.sender, PERMISSION_BIT_ADMIN);

        return tokenId;
    }

    function setupNewTokenWithCreateReferral(string calldata newURI, uint256 maxSupply, address createReferral) public returns (uint256) {
        uint256 tokenId = _setupNewTokenAndPermission(newURI, maxSupply, msg.sender, PERMISSION_BIT_ADMIN);

        _setCreateReferral(tokenId, createReferral);

        return tokenId;
    }

    function _setCreateReferral(uint256 tokenId, address recipient) internal {
        createReferrals[tokenId] = recipient;
    }

    function addPermission(uint256 tokenId, address user, uint256 permissionBits) external onlyAdmin(tokenId) {
        _addPermission(tokenId, user, permissionBits);
    }

    function adminMint(address recipient, uint256 tokenId, uint256 quantity, bytes memory data) external onlyAdminOrRole(tokenId, PERMISSION_BIT_MINTER) {
        // Mint the specified tokens
        _mint(recipient, tokenId, quantity, data);
    }

    error CallFailed(bytes reason);

    function callSale(uint256, IMinter1155 salesConfig, bytes calldata data) external {
        (bool success, bytes memory err) = address(salesConfig).call(data);

        if (!success) {
            revert CallFailed(err);
        }
    }

    ///                                                          ///
    ///                                                          ///
    ///                                                          ///

    ///                                                          ///
    ///                                                          ///
    ///                                                          ///

    modifier onlyAdminOrRole(uint256 tokenId, uint256 role) {
        _requireAdminOrRole(msg.sender, tokenId, role);
        _;
    }

    modifier onlyAdmin(uint256 tokenId) {
        _requireAdmin(msg.sender, tokenId);
        _;
    }

    function _requireAdminOrRole(address user, uint256 tokenId, uint256 role) internal view {
        if (!(_hasAnyPermission(tokenId, user, PERMISSION_BIT_ADMIN | role) || _hasAnyPermission(CONTRACT_BASE_ID, user, PERMISSION_BIT_ADMIN | role))) {
            revert UserMissingRoleForToken(user, tokenId, role);
        }
    }

    function _requireAdmin(address user, uint256 tokenId) internal view {
        if (!(_hasAnyPermission(tokenId, user, PERMISSION_BIT_ADMIN) || _hasAnyPermission(CONTRACT_BASE_ID, user, PERMISSION_BIT_ADMIN))) {
            revert UserMissingRoleForToken(user, tokenId, PERMISSION_BIT_ADMIN);
        }
    }

    function _hasAnyPermission(uint256 tokenId, address user, uint256 permissionBits) internal view returns (bool) {
        // Does a bitwise and and checks if any of those permissions match
        return permissions[tokenId][user] & permissionBits > 0;
    }

    function _addPermission(uint256 tokenId, address user, uint256 permissionBits) internal {
        uint256 tokenPermissions = permissions[tokenId][user];
        tokenPermissions |= permissionBits;
        permissions[tokenId][user] = tokenPermissions;
        emit UpdatedPermissions(tokenId, user, tokenPermissions);
    }

    ///                                                          ///
    ///                                                          ///
    ///                                                          ///

    function _setupNewTokenAndPermission(string memory newURI, uint256 maxSupply, address user, uint256 permission) internal returns (uint256) {
        uint256 tokenId = _setupNewToken(newURI, maxSupply);

        _addPermission(tokenId, user, permission);

        if (bytes(newURI).length > 0) {
            emit URI(newURI, tokenId);
        }

        emit SetupNewToken(tokenId, user, newURI, maxSupply);

        return tokenId;
    }

    function _setupNewToken(string memory newURI, uint256 maxSupply) internal returns (uint256 tokenId) {
        tokenId = _getAndUpdateNextTokenId();

        TokenData memory tokenData = TokenData({uri: newURI, maxSupply: maxSupply, totalMinted: 0});

        tokens[tokenId] = tokenData;

        emit UpdatedToken(msg.sender, tokenId, tokenData);
    }

    function _getAndUpdateNextTokenId() internal returns (uint256) {
        unchecked {
            return nextTokenId++;
        }
    }
}
