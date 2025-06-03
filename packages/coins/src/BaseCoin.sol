// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC165} from "@openzeppelin/contracts/utils/introspection/IERC165.sol";
import {ICoin, IHasRewardsRecipients} from "./interfaces/ICoin.sol";
import {ICoinComments} from "./interfaces/ICoinComments.sol";
import {IERC7572} from "./interfaces/IERC7572.sol";
import {IAirlock} from "./interfaces/IAirlock.sol";

import {ERC20PermitUpgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/extensions/ERC20PermitUpgradeable.sol";
import {ReentrancyGuardUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ContractVersionBase} from "./version/ContractVersionBase.sol";
import {MultiOwnable} from "./utils/MultiOwnable.sol";
import {CoinConstants} from "./libs/CoinConstants.sol";

/*
     $$$$$$\   $$$$$$\  $$$$$$\ $$\   $$\ 
    $$  __$$\ $$  __$$\ \_$$  _|$$$\  $$ |
    $$ /  \__|$$ /  $$ |  $$ |  $$$$\ $$ |
    $$ |      $$ |  $$ |  $$ |  $$ $$\$$ |
    $$ |      $$ |  $$ |  $$ |  $$ \$$$$ |
    $$ |  $$\ $$ |  $$ |  $$ |  $$ |\$$$ |
    \$$$$$$  | $$$$$$  |$$$$$$\ $$ | \$$ |
     \______/  \______/ \______|\__|  \__|
*/
abstract contract BaseCoin is ICoin, ContractVersionBase, ERC20PermitUpgradeable, MultiOwnable, ReentrancyGuardUpgradeable {
    using SafeERC20 for IERC20;

    /// @notice The address of the protocol rewards contract
    address public immutable protocolRewards;
    /// @notice The address of the protocol reward recipient
    address public immutable protocolRewardRecipient;
    /// @notice The address of the Airlock contract, ownership is used for a protocol fee split.
    address public immutable airlock;

    /// @notice The metadata URI
    string public tokenURI;
    /// @notice The address of the coin creator
    address public payoutRecipient;
    /// @notice The address of the platform referrer
    address public platformReferrer;
    /// @notice The address of the currency
    address public currency;

    /**
     * @notice The constructor for the static Coin contract deployment shared across all Coins.
     * @param _protocolRewardRecipient The address of the protocol reward recipient
     * @param _protocolRewards The address of the protocol rewards contract
     * @param _airlock The address of the Airlock contract
     */
    constructor(address _protocolRewardRecipient, address _protocolRewards, address _airlock) initializer {
        if (_protocolRewardRecipient == address(0)) {
            revert AddressZero();
        }
        if (_protocolRewards == address(0)) {
            revert AddressZero();
        }

        if (_airlock == address(0)) {
            revert AddressZero();
        }

        protocolRewardRecipient = _protocolRewardRecipient;
        protocolRewards = _protocolRewards;
        airlock = _airlock;
    }

    /// @notice Initializes a new coin
    /// @param payoutRecipient_ The address of the coin creator
    /// @param tokenURI_ The metadata URI
    /// @param name_ The coin name
    /// @param symbol_ The coin symbol
    /// @param platformReferrer_ The address of the platform referrer
    function _initialize(
        address payoutRecipient_,
        address[] memory owners_,
        string memory tokenURI_,
        string memory name_,
        string memory symbol_,
        address platformReferrer_
    ) internal {
        // Validate the creation parameters
        if (payoutRecipient_ == address(0)) {
            revert AddressZero();
        }

        // Set base contract state
        __ERC20_init(name_, symbol_);
        __ERC20Permit_init(name_);
        __MultiOwnable_init(owners_);
        __ReentrancyGuard_init();

        // Set mutable state
        _setPayoutRecipient(payoutRecipient_);
        _setContractURI(tokenURI_);

        // Store the referrer or use the protocol reward recipient if not set
        platformReferrer = platformReferrer_ == address(0) ? protocolRewardRecipient : platformReferrer_;

        // Mint the total supply to the coin contract
        _mint(address(this), CoinConstants.MAX_TOTAL_SUPPLY);

        // Distribute the creator launch reward to the payout recipient
        _transfer(address(this), payoutRecipient, CoinConstants.CREATOR_LAUNCH_REWARD);
    }

    /// @notice Enables a user to burn their tokens
    /// @param amount The amount of tokens to burn
    function burn(uint256 amount) external {
        // This burn function sets the from as msg.sender, so having an unauthed call is safe.
        _burn(msg.sender, amount);
    }

    /// @notice Set the creator's payout address
    /// @param newPayoutRecipient The new recipient address
    function setPayoutRecipient(address newPayoutRecipient) external onlyOwner {
        _setPayoutRecipient(newPayoutRecipient);
    }

    /// @notice Set the contract URI
    /// @param newURI The new URI
    function setContractURI(string memory newURI) external onlyOwner {
        _setContractURI(newURI);
    }

    /// @notice The contract metadata
    function contractURI() external view returns (string memory) {
        return tokenURI;
    }

    /// @notice ERC165 interface support
    /// @param interfaceId The interface ID to check
    function supportsInterface(bytes4 interfaceId) public pure virtual returns (bool) {
        return
            interfaceId == type(ICoin).interfaceId ||
            interfaceId == type(ICoinComments).interfaceId ||
            interfaceId == type(IERC7572).interfaceId ||
            interfaceId == type(IERC165).interfaceId ||
            interfaceId == type(IHasRewardsRecipients).interfaceId;
    }

    /// @dev Overrides ERC20's _update function to emit a superset `CoinTransfer` event
    function _update(address from, address to, uint256 value) internal virtual override {
        super._update(from, to, value);

        emit CoinTransfer(from, to, value, balanceOf(from), balanceOf(to));
    }

    /// @dev Used to set the payout recipient on coin creation and updates
    /// @param newPayoutRecipient The new recipient address
    function _setPayoutRecipient(address newPayoutRecipient) internal {
        if (newPayoutRecipient == address(0)) {
            revert AddressZero();
        }

        emit CoinPayoutRecipientUpdated(msg.sender, payoutRecipient, newPayoutRecipient);

        payoutRecipient = newPayoutRecipient;
    }

    /// @dev Used to set the contract URI on coin creation and updates
    /// @param newURI The new URI
    function _setContractURI(string memory newURI) internal {
        emit ContractMetadataUpdated(msg.sender, newURI, name());
        emit ContractURIUpdated();

        tokenURI = newURI;
    }

    /// @notice Returns the owner of the Airlock contract
    function doppler() external view returns (address) {
        return IAirlock(airlock).owner();
    }
}
