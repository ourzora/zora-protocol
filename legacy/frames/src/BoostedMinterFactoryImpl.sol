// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import {CREATE3} from "solmate/src/utils/CREATE3.sol";
import {Initializable} from "@zoralabs/openzeppelin-contracts-upgradeable/contracts/proxy/utils/Initializable.sol";
import {UUPSUpgradeable} from "@zoralabs/openzeppelin-contracts-upgradeable/contracts/proxy/utils/UUPSUpgradeable.sol";
import {Ownable2StepUpgradeable} from
    "@zoralabs/openzeppelin-contracts-upgradeable/contracts/access/Ownable2StepUpgradeable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import {BoostedMinterImpl} from "./BoostedMinterImpl.sol";
import {BoostedMinter} from "./BoostedMinter.sol";
import {BoostedMinterFactoryStorageV1} from "./BoostedMinterFactoryStorageV1.sol";

contract BoostedMinterFactoryImpl is Ownable2StepUpgradeable, UUPSUpgradeable, BoostedMinterFactoryStorageV1 {
    address public immutable boostedMinterImpl;

    event BoostedMinterDeployed(address indexed tokenContract, uint256 indexed tokenId, address indexed minter);

    constructor() initializer {
        boostedMinterImpl = address(new BoostedMinterImpl());
    }

    function initialize(address _owner) public initializer {
        __Ownable2Step_init();
        _transferOwnership(_owner);
    }

    function deployBoostedMinter(address _tokenContract, uint256 _tokenId) external returns (address) {
        // use create3 to deploy the minter
        bytes32 digest = _hashContract(_tokenContract, _tokenId);

        address createdBoostedMinter =
            CREATE3.deploy(digest, abi.encodePacked(type(BoostedMinter).creationCode, abi.encode(boostedMinterImpl)), 0);

        BoostedMinterImpl(payable(createdBoostedMinter)).initialize(owner(), _tokenContract, _tokenId);

        boostedMinterForCollection[_tokenContract][_tokenId] = createdBoostedMinter;

        emit BoostedMinterDeployed(_tokenContract, _tokenId, createdBoostedMinter);

        return createdBoostedMinter;
    }

    function _hashContract(address _tokenContract, uint256 _tokenId) internal pure returns (bytes32) {
        return keccak256(abi.encodePacked(_tokenContract, _tokenId));
    }

    ///                                                          ///
    ///                         MANAGER UPGRADE                  ///
    ///                                                          ///

    /// @notice Ensures the caller is authorized to upgrade the contract
    /// @dev This function is called in `upgradeTo` & `upgradeToAndCall`
    /// @param _newImpl The new implementation address
    function _authorizeUpgrade(address _newImpl) internal view override onlyOwner {
        require(_newImpl != address(0), "BoostedMinterFactoryImpl: Cannot upgrade to the zero address");
        require(_newImpl != boostedMinterImpl, "BoostedMinterFactoryImpl: Cannot upgrade to the same implementation");
    }

    /// @notice Returns the current implementation address
    // function implementation() external view returns (address) {
    //     return _getImplementation();
    // }

    function _equals(string memory a, string memory b) internal pure returns (bool) {
        return (keccak256(bytes(a)) == keccak256(bytes(b)));
    }
}
