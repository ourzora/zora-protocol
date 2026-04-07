// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {IDeployedCoinVersionLookup} from "../interfaces/IDeployedCoinVersionLookup.sol";

/**
 * @title DeployedCoinVersionLookup
 * @notice Contract for storing and retrieving version information for deployed coins
 * @dev Uses the ERC-7201 static storage slot pattern for upgradeable storage
 */
contract DeployedCoinVersionLookup is IDeployedCoinVersionLookup {
    struct DeployedCoinVersion {
        uint8 version;
    }

    /// @custom:storage-location erc7201:zora.coins.deployedcoinversionlookup.storage
    struct DeployedCoinVersionStorage {
        mapping(address => DeployedCoinVersion) deployedCoinWithVersion;
    }

    // keccak256(abi.encode(uint256(keccak256("zora.coins.deployedcoinversionlookup.storage")) - 1)) & ~bytes32(uint256(0xff))
    bytes32 private constant DEPLOYED_COIN_VERSION_STORAGE_LOCATION = 0x9a79df0b86f39d0543c14aee714123562f798115071e932933bcc3e29cc86f00;

    /**
     * @dev Returns the storage slot struct for deployed coin versions
     * @return $ Storage struct containing the deployedCoinWithVersion mapping
     */
    function _getDeployedCoinVersionStorage() private pure returns (DeployedCoinVersionStorage storage $) {
        assembly {
            $.slot := DEPLOYED_COIN_VERSION_STORAGE_LOCATION
        }
    }

    /**
     * @notice Gets the version for a deployed coin
     * @param coin The address of the coin
     * @return version The version of the coin (0 if not found)
     */
    function getVersionForDeployedCoin(address coin) public view returns (uint8) {
        return _getDeployedCoinVersionStorage().deployedCoinWithVersion[coin].version;
    }

    /**
     * @notice Sets the version for a deployed coin
     * @dev Only callable internally
     * @param coin The address of the coin
     * @param version The version to set
     */
    function _setVersionForDeployedCoin(address coin, uint8 version) internal {
        _getDeployedCoinVersionStorage().deployedCoinWithVersion[coin] = DeployedCoinVersion({version: version});
    }
}
