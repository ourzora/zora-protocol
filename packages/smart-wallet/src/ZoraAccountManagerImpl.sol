// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {UUPSUpgradeable, ERC1967Utils} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";

import {IEntryPoint} from "./interfaces/IEntryPoint.sol";
import {ICoinbaseSmartWalletFactory} from "./interfaces/ICoinbaseSmartWalletFactory.sol";

contract ZoraAccountManagerImpl is UUPSUpgradeable, OwnableUpgradeable {
    IEntryPoint public constant entryPoint = IEntryPoint(0x5FF137D4b0FDCD49DcA30c7CF57E578a026d2789);
    ICoinbaseSmartWalletFactory public constant smartWalletFactory = ICoinbaseSmartWalletFactory(0x0BA5ED0c6AA8c49038F819E587E2633c4A9F428a);

    constructor() initializer {}

    function initialize(address initialOwner) public initializer {
        __Ownable_init(initialOwner);
    }

    event ZoraSmartWalletCreated(address indexed smartWallet, address indexed baseOwner, address[] owners, uint256 nonce);

    function createSmartWallet(bytes[] calldata encodedOwners, uint256 nonce) external returns (address) {
        smartWalletFactory.createAccount(encodedOwners, nonce);

        address[] memory owners = new address[](encodedOwners.length);

        for (uint256 i; i < encodedOwners.length; ++i) {
            owners[i] = abi.decode(encodedOwners[i], (address));
        }

        address smartWallet = smartWalletFactory.getAddress(encodedOwners, nonce);

        emit ZoraSmartWalletCreated(smartWallet, owners[0], owners, nonce);

        return smartWallet;
    }

    function getAddress(bytes[] calldata encodedOwners, uint256 nonce) external view returns (address) {
        return smartWalletFactory.getAddress(encodedOwners, nonce);
    }

    function getNonce(address smartWallet) external view returns (uint256) {
        return entryPoint.getNonce(smartWallet, 0);
    }

    function getKeyNonce(address smartWallet, uint192 key) external view returns (uint256) {
        return entryPoint.getNonce(smartWallet, key);
    }

    function implementation() external view returns (address) {
        return ERC1967Utils.getImplementation();
    }

    function _authorizeUpgrade(address) internal override onlyOwner {}
}
