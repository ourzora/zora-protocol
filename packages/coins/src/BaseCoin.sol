// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC165} from "@openzeppelin/contracts/utils/introspection/IERC165.sol";
import {ICoin} from "./interfaces/ICoin.sol";
import {IHasRewardsRecipients} from "./interfaces/IHasRewardsRecipients.sol";
import {ICoinComments} from "./interfaces/ICoinComments.sol";
import {IERC7572} from "./interfaces/IERC7572.sol";
import {IUniswapV3Factory} from "./interfaces/IUniswapV3Factory.sol";
import {IUniswapV3Pool} from "./interfaces/IUniswapV3Pool.sol";
import {ISwapRouter} from "./interfaces/ISwapRouter.sol";
import {IAirlock} from "./interfaces/IAirlock.sol";
import {IProtocolRewards} from "./interfaces/IProtocolRewards.sol";
import {IWETH} from "./interfaces/IWETH.sol";

import {Address} from "@openzeppelin/contracts/utils/Address.sol";
import {ERC20PermitUpgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/extensions/ERC20PermitUpgradeable.sol";
import {ReentrancyGuardUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ContractVersionBase} from "./version/ContractVersionBase.sol";
import {MultiOwnable} from "./utils/MultiOwnable.sol";
import {FullMath} from "./utils/uniswap/FullMath.sol";
import {TickMath} from "./utils/uniswap/TickMath.sol";
import {LiquidityAmounts} from "./utils/uniswap/LiquidityAmounts.sol";
import {CoinConstants} from "./libs/CoinConstants.sol";
import {MarketConstants} from "./libs/MarketConstants.sol";
import {LpPosition} from "./types/LpPosition.sol";
import {PoolState} from "./types/PoolState.sol";
import {CoinSetupV3, UniV3Config, CoinV3Config} from "./libs/CoinSetupV3.sol";
import {UniV3BuySell, CoinConfig} from "./libs/UniV3BuySell.sol";

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

    /// @notice The name of the token
    string private _name;
    /// @notice The symbol of the token
    string private _symbol;

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

        _setNameAndSymbol(name_, symbol_);

        // Set base contract state, leave name and symbol empty to save space.
        __ERC20_init("", "");

        // Set permit support without name later overriding name to match contract name.
        __ERC20Permit_init("");

        __MultiOwnable_init(owners_);
        __ReentrancyGuard_init();

        // Set mutable state
        _setPayoutRecipient(payoutRecipient_);
        _setContractURI(tokenURI_);

        // Store the referrer or use the protocol reward recipient if not set
        platformReferrer = platformReferrer_ == address(0) ? protocolRewardRecipient : platformReferrer_;

        // Distribute the initial supply
        _handleInitialDistribution();
    }

    /// @dev The initial mint and distribution of the coin supply.
    function _handleInitialDistribution() internal virtual {
        // Mint the total supply to the coin contract
        _mint(address(this), CoinConstants.MAX_TOTAL_SUPPLY);

        // Distribute the creator launch reward to the payout recipient
        _transfer(address(this), payoutRecipient, CoinConstants.CREATOR_LAUNCH_REWARD);
    }

    /// @notice Returns the name of the token for EIP712 domain.
    /// @notice This can change when the user changes the "name" of the token.
    /// @dev Overrides the default implementation to align name getter with Permit support.
    function _EIP712Name() internal view override returns (string memory) {
        return "Coin";
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

    /**
     * @dev Returns the name of the token.
     */
    function name() public view override returns (string memory) {
        return _name;
    }

    function setNameAndSymbol(string memory newName, string memory newSymbol) external onlyOwner {
        _setNameAndSymbol(newName, newSymbol);
    }

    function _setNameAndSymbol(string memory newName, string memory newSymbol) internal {
        if (bytes(newName).length == 0) {
            revert NameIsRequired();
        }
        _name = newName;
        _symbol = newSymbol;
        emit NameAndSymbolUpdated(msg.sender, newName, newSymbol);
    }

    /**
     * @dev Returns the symbol of the token, usually a shorter version of the
     * name.
     */
    function symbol() public view override returns (string memory) {
        return _symbol;
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

    /// @notice Returns the address of the Doppler protocol fee recipient
    function dopplerFeeRecipient() public view returns (address) {
        return IAirlock(airlock).owner();
    }
}
