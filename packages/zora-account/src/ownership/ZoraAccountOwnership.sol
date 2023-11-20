// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import {EnumerableSet} from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";

contract ZoraAccountOwnership is Initializable, IZoraAccountOwnership {
    using EnumerableSet for EnumerableSet.AddressSet;

    // @custom:storage-location erc7201:zora.storage.OwnerEnumerable
    struct ZoraAccountOwnershipStorage {
        EnumerableSet.AddressSet _owners;
    }

    bytes32 private immutable ZoraAccountOwnershipStorageLocation = keccak256(abi.encode(uint256(keccak256("zora.storage.OwnerEnumerable")) - 1)) & ~bytes32(uint256(0xff));

    function _getZoraAccountOwnershipStorage() private pure returns (ZoraAccountOwnershipStorage storage $) {
        assembly {
            $.slot := ZoraAccountOwnershipStorageLocation
        }
    }

    modifier onlyOwner(address check) {
        if (!_getZoraAccountOwnershipStorage()._owners[check]) {
            revert UserNotOwner(check);
        }
    }

    function getOwners() external view returns (address[] memory) {
        return _getZoraAccountOwnershipStorage()._owners.values();
    }

    function _setupWithAdmin(address initialAdmin) onlyInitializing internal {
        // todo emit event
        _getZoraAccountOwnershipStorage()._owners.add(initialAdmin);
    }

    function changeOwnership(address previousOwner, address newOwner) onlyOwner external {
        // todo emit event
        _getZoraAccountOwnershipStorage()._owners.remove(previousOwner);
        _getZoraAccountOwnershipStorage()._owners.add(newOwner);
    }

    function addOwner(address newOwner) onlyOwner external {
        // todo emit event
        _getZoraAccountOwnershipStorage()._owners.add(newOwner);
    }

    function removeOwner(address ownerToRemove) onlyOwner external {
        // todo emit event
        _getZoraAccountOwnershipStorage()._owners.remove(ownerToRemove);
    }

    function supportsInterface(bytes4 interfaceId) public view virtual override returns (bool) {
        return interfaceId == type(IZoraAccountOwnership).interfaceId || super.supportsInterface(interfaceId);
    }
    
}