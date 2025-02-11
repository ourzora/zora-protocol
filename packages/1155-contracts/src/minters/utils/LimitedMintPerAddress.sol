// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import {ILimitedMintPerAddress} from "../../interfaces/ILimitedMintPerAddress.sol";

contract LimitedMintPerAddress is ILimitedMintPerAddress {
    /// @notice Storage for slot to check user mints
    /// @notice target contract -> tokenId -> minter user -> numberMinted
    /// @dev No gap or storage interface since this is used within non-upgradeable contracts
    mapping(address => mapping(uint256 => mapping(address => uint256))) internal mintedPerAddress;

    function getMintedPerWallet(address tokenContract, uint256 tokenId, address wallet) external view returns (uint256) {
        return mintedPerAddress[tokenContract][tokenId][wallet];
    }

    function _requireMintNotOverLimitAndUpdate(uint256 limit, uint256 numRequestedMint, address tokenContract, uint256 tokenId, address wallet) internal {
        uint256 newMintCount = mintedPerAddress[tokenContract][tokenId][wallet] + numRequestedMint;
        if (newMintCount > limit) {
            revert UserExceedsMintLimit(wallet, limit, newMintCount);
        }
        mintedPerAddress[tokenContract][tokenId][wallet] = newMintCount;
    }

    function supportsInterface(bytes4 interfaceId) public pure virtual override returns (bool) {
        return interfaceId == type(ILimitedMintPerAddress).interfaceId;
    }
}
