// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import {EnumerableSet} from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";

import {IZoraAccountOwnership} from "../interfaces/IZoraAccountOwnership.sol";

contract ZoraAccountOwnership is Initializable, IZoraAccountOwnership {
    using EnumerableSet for EnumerableSet.AddressSet;

    // @custom:storage-location erc7201:zora.storage.OwnerEnumerable
    struct ZoraAccountOwnershipStorage {
        EnumerableSet.AddressSet _owners;
    }

    bytes32 private immutable ZoraAccountOwnershipStorageLocation = keccak256(abi.encode(uint256(keccak256("zora.storage.OwnerEnumerable")) - 1)) & ~bytes32(uint256(0xff));

    function _getZoraAccountOwnershipStorage() private view returns (ZoraAccountOwnershipStorage storage $) {
        bytes32 position = ZoraAccountOwnershipStorageLocation;

        assembly {
            $.slot := position
        }
    }

    modifier onlyOwner(address check) {
        if (!_getZoraAccountOwnershipStorage()._owners.contains(check)) {
            revert UserNotOwner(check);
        }
        _;
    }

    function getOwners() external view returns (address[] memory) {
        return _getZoraAccountOwnershipStorage()._owners.values();
    }

    function isApprovedOwner(address owner) public view returns (bool) {
        return _getZoraAccountOwnershipStorage()._owners.contains(owner);
    }

    function _setupWithAdmin(address initialAdmin) onlyInitializing internal {
        // todo emit event
        _getZoraAccountOwnershipStorage()._owners.add(initialAdmin);
    }

    // TODO verify intent was to pass msg.sender with onlyOwner modifier
    function changeOwnership(address previousOwner, address newOwner) onlyOwner(msg.sender) external {
        // todo emit event
        // TODO verify newOwner != address(0) && previousOwner != owner? 
        _getZoraAccountOwnershipStorage()._owners.remove(previousOwner);
        _getZoraAccountOwnershipStorage()._owners.add(newOwner);
    }

    // TODO verify intent was to pass msg.sender with onlyOwner modifier
    function addOwner(address newOwner) onlyOwner(msg.sender) external {
        // todo emit event
        _getZoraAccountOwnershipStorage()._owners.add(newOwner);
    }

    // TODO verify intent was to pass msg.sender with onlyOwner modifier
    function removeOwner(address ownerToRemove) onlyOwner(msg.sender) external {
        // todo emit event
        _getZoraAccountOwnershipStorage()._owners.remove(ownerToRemove);
    }

    function supportsInterface(bytes4 interfaceId) public view virtual returns (bool) {
        return interfaceId == type(IZoraAccountOwnership).interfaceId;
    }
}