// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Ownable2StepUpgradeable} from "@openzeppelin/contracts-upgradeable/access/Ownable2StepUpgradeable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {ERC1967Utils} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";
import {IHasContractName} from "@zoralabs/shared-contracts/interfaces/IContractMetadata.sol";
import {CointagImpl} from "./CointagImpl.sol";
import {Cointag} from "./proxy/Cointag.sol";
import {ICointag} from "./interfaces/ICointag.sol";
import {ICointagFactory} from "./interfaces/ICointagFactory.sol";
import {Clones} from "@openzeppelin/contracts/proxy/Clones.sol";
import {Create2} from "@openzeppelin/contracts/utils/Create2.sol";
import {ContractVersionBase} from "./version/ContractVersionBase.sol";
import {IUpgradeGate} from "@zoralabs/shared-contracts/interfaces/IUpgradeGate.sol";
import {CREATE3} from "solmate/src/utils/CREATE3.sol";

/// @title CointagFactoryImpl - Factory for deploying Cointag contracts
/// @notice This factory enables deterministic deployment of Cointag contracts
/// @dev Uses CREATE3 for deterministic deployments and handles proxy initialization
contract CointagFactoryImpl is Ownable2StepUpgradeable, UUPSUpgradeable, ContractVersionBase, ICointagFactory {
    address public immutable cointagImplementation;
    IUpgradeGate public immutable upgradeGate;

    /// @notice Creates a new factory instance
    /// @param _cointagImplementation The implementation contract address for Cointag
    constructor(address _cointagImplementation) {
        _requireNotAddressZero(_cointagImplementation);
        cointagImplementation = _cointagImplementation;

        _disableInitializers();
    }

    /// @notice Initializes the factory contract
    /// @param _defaultOwner The default owner address for the factory
    function initialize(address _defaultOwner) external initializer {
        _requireNotAddressZero(_defaultOwner);

        __Ownable_init(_defaultOwner);
        __UUPSUpgradeable_init();
    }

    /// @notice Getter to return the proxy implementation easily for scripts / front-end
    function implementation() public view returns (address) {
        return ERC1967Utils.getImplementation();
    }

    /// @notice Returns the contract name
    function contractName() external pure returns (string memory) {
        return "Cointags Factory";
    }

    /// @notice The URI of the contract
    function contractURI() external pure returns (string memory) {
        return "https://github.com/ourzora/zora-protocol/";
    }

    function _requireNotAddressZero(address _address) internal pure {
        if (_address == address(0)) {
            revert AddressZero();
        }
    }

    function _authorizeUpgrade(address newImplementation) internal override onlyOwner {
        // check that new implementation's contract name matches the current contract name
        if (!Strings.equal(IHasContractName(newImplementation).contractName(), this.contractName())) {
            revert UpgradeToMismatchedContractName(this.contractName(), IHasContractName(newImplementation).contractName());
        }
    }

    /// @notice Creates or retrieves an existing Cointag contract
    /// @param _creatorRewardRecipient Address that will receive creator rewards
    /// @param _pool Address of the pool contract
    /// @param _percentageToBuyBurn Percentage of tokens to buy and burn
    /// @param saltSource Additional data used to generate the deterministic address
    /// @return The Cointag contract instance
    function getOrCreateCointag(
        address _creatorRewardRecipient,
        address _pool,
        uint256 _percentageToBuyBurn,
        bytes calldata saltSource
    ) public returns (ICointag) {
        bytes32 salt = _makeSalt(_creatorRewardRecipient, _pool, _percentageToBuyBurn, saltSource);

        bytes memory creationCode = _getCreationCode();

        address cointagAddress = CREATE3.getDeployed(salt);

        if (cointagAddress.code.length > 0) {
            return ICointag(cointagAddress);
        }

        address deployed = CREATE3.deploy(salt, creationCode, 0);

        ICointag cointag = ICointag(deployed);
        cointag.initialize(_creatorRewardRecipient, _pool, _percentageToBuyBurn);

        emit SetupNewCointag(address(cointag), _creatorRewardRecipient, address(cointag.erc20()), _pool, _percentageToBuyBurn, saltSource);

        return ICointag(address(cointag));
    }

    /// @notice Predicts the address where a Cointag contract would be deployed
    /// @param _creatorRewardRecipient Address that will receive creator rewards
    /// @param _pool Address of the pool contract
    /// @param _percentageToBuyBurn Percentage of tokens to buy and burn
    /// @param saltSource Additional data used to generate the deterministic address
    /// @return The predicted address where the Cointag contract will be deployed
    function getCointagAddress(
        address _creatorRewardRecipient,
        address _pool,
        uint256 _percentageToBuyBurn,
        bytes calldata saltSource
    ) external view returns (address) {
        return CREATE3.getDeployed(_makeSalt(_creatorRewardRecipient, _pool, _percentageToBuyBurn, saltSource));
    }

    function _getCreationCode() internal view returns (bytes memory) {
        return abi.encodePacked(type(Cointag).creationCode, abi.encode(cointagImplementation, ""));
    }

    function _getInitializeCall(address _creatorRewardRecipient, address _pool, uint256 _percentageToBuyBurn) internal pure returns (bytes memory) {
        return abi.encodeWithSelector(CointagImpl.initialize.selector, _creatorRewardRecipient, _pool, _percentageToBuyBurn);
    }

    function _makeDigest(
        address _creatorRewardRecipient,
        address _pool,
        uint256 _percentageToBuyBurn,
        bytes calldata saltSource
    ) internal pure returns (bytes memory) {
        return abi.encodePacked(_creatorRewardRecipient, _pool, _percentageToBuyBurn, saltSource);
    }

    function _makeSalt(
        address _creatorRewardRecipient,
        address _pool,
        uint256 _percentageToBuyBurn,
        bytes calldata saltSource
    ) internal pure returns (bytes32) {
        return keccak256(abi.encodePacked(_creatorRewardRecipient, _pool, _percentageToBuyBurn, saltSource));
    }

    function getOrCreateCointagAtExpectedAddress(
        address _creatorRewardRecipient,
        address _pool,
        uint256 _percentageToBuyBurn,
        bytes calldata saltSource,
        address expectedAddress
    ) external returns (ICointag) {
        ICointag cointag = getOrCreateCointag(_creatorRewardRecipient, _pool, _percentageToBuyBurn, saltSource);

        if (address(cointag) != expectedAddress) {
            revert UnexpectedCointagAddress(expectedAddress, address(cointag));
        }

        return cointag;
    }
}
