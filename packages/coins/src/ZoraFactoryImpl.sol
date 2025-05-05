// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {Clones} from "@openzeppelin/contracts/proxy/Clones.sol";
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {ReentrancyGuardUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {ERC1967Utils} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Utils.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {CoinConfigurationVersions} from "./libs/CoinConfigurationVersions.sol";
import {ISwapRouter} from "./interfaces/ISwapRouter.sol";
import {IWETH} from "./interfaces/IWETH.sol";
import {IZoraFactory} from "./interfaces/IZoraFactory.sol";
import {IHasAfterCoinDeploy} from "./hooks/BaseCoinDeployHook.sol";
import {IERC165} from "@openzeppelin/contracts/utils/introspection/IERC165.sol";
import {Coin} from "./Coin.sol";
import {ICoin} from "./interfaces/ICoin.sol";
import {IHasContractName} from "@zoralabs/shared-contracts/interfaces/IContractMetadata.sol";
import {ContractVersionBase} from "./version/ContractVersionBase.sol";

contract ZoraFactoryImpl is IZoraFactory, UUPSUpgradeable, ReentrancyGuardUpgradeable, OwnableUpgradeable, IHasContractName, ContractVersionBase {
    using SafeERC20 for IERC20;

    /// @notice The coin contract implementation address
    address public immutable coinImpl;

    constructor(address _coinImpl) initializer {
        coinImpl = _coinImpl;
    }

    /// @inheritdoc IZoraFactory
    function deploy(
        address payoutRecipient,
        address[] memory owners,
        string memory uri,
        string memory name,
        string memory symbol,
        bytes memory poolConfig,
        address platformReferrer,
        uint256 orderSize
    ) public payable nonReentrant returns (address, uint256) {
        Coin coin = _createAndInitializeCoin(payoutRecipient, owners, uri, name, symbol, poolConfig, platformReferrer);

        uint256 coinsPurchased = _handleFirstOrder(coin, orderSize);

        return (address(coin), coinsPurchased);
    }

    /// @inheritdoc IZoraFactory
    function deployWithHook(
        address payoutRecipient,
        address[] memory owners,
        string memory uri,
        string memory name,
        string memory symbol,
        bytes memory poolConfig,
        address platformReferrer,
        address hook,
        bytes calldata hookData
    ) public payable nonReentrant returns (address coin, bytes memory hookDataOut) {
        coin = address(_createAndInitializeCoin(payoutRecipient, owners, uri, name, symbol, poolConfig, platformReferrer));

        if (hook != address(0)) {
            if (!IERC165(hook).supportsInterface(type(IHasAfterCoinDeploy).interfaceId)) {
                revert InvalidHook();
            }
            hookDataOut = IHasAfterCoinDeploy(hook).afterCoinDeploy{value: msg.value}(msg.sender, ICoin(coin), hookData);
        } else if (msg.value > 0) {
            // cannot send eth without a hook
            revert EthTransferInvalid();
        }
    }

    /// @inheritdoc IZoraFactory
    function deploy(
        address payoutRecipient,
        address[] memory owners,
        string memory uri,
        string memory name,
        string memory symbol,
        address platformReferrer,
        address currency,
        int24 tickLower,
        uint256 orderSize
    ) public payable nonReentrant returns (address, uint256) {
        bytes memory poolConfig = abi.encode(CoinConfigurationVersions.LEGACY_POOL_VERSION, currency, tickLower);

        Coin coin = _createAndInitializeCoin(payoutRecipient, owners, uri, name, symbol, poolConfig, platformReferrer);

        uint256 coinsPurchased = _handleFirstOrder(coin, orderSize);

        return (address(coin), coinsPurchased);
    }

    function _createAndInitializeCoin(
        address payoutRecipient,
        address[] memory owners,
        string memory uri,
        string memory name,
        string memory symbol,
        bytes memory poolConfig,
        address platformReferrer
    ) internal returns (Coin) {
        bytes32 salt = _generateSalt(payoutRecipient, uri);

        Coin coin = Coin(payable(Clones.cloneDeterministic(coinImpl, salt)));

        coin.initialize(payoutRecipient, owners, uri, name, symbol, poolConfig, platformReferrer);

        emit CoinCreated(
            msg.sender,
            payoutRecipient,
            coin.platformReferrer(),
            coin.currency(),
            uri,
            name,
            symbol,
            address(coin),
            coin.poolAddress(),
            coin.contractVersion()
        );

        return coin;
    }

    /// @dev Generates a unique salt for deterministic deployment
    function _generateSalt(address payoutRecipient, string memory uri) internal view returns (bytes32) {
        return
            keccak256(
                abi.encodePacked(
                    msg.sender,
                    payoutRecipient,
                    keccak256(abi.encodePacked(uri)),
                    block.coinbase,
                    block.number,
                    block.prevrandao,
                    block.timestamp,
                    tx.gasprice,
                    tx.origin
                )
            );
    }

    /// @dev Handles the first buy of a newly created coin
    /// @param coin The newly created coin contract
    /// @param orderSize The size of the first buy order; must match msg.value for ETH/WETH pairs
    function _handleFirstOrder(Coin coin, uint256 orderSize) internal returns (uint256 coinsPurchased) {
        if (msg.value > 0 || orderSize > 0) {
            address currency = coin.currency();
            address payoutRecipient = coin.payoutRecipient();

            if (currency != coin.WETH()) {
                if (msg.value != 0) {
                    revert EthTransferInvalid();
                }

                _handleIncomingCurrency(currency, orderSize);

                IERC20(currency).approve(address(coin), orderSize);

                (, coinsPurchased) = coin.buy(payoutRecipient, orderSize, 0, 0, address(0));
            } else {
                (, coinsPurchased) = coin.buy{value: msg.value}(payoutRecipient, orderSize, 0, 0, address(0));
            }
        }
    }

    /// @dev Safely transfers ERC20 tokens from the caller to this contract to be sent to the newly created coin
    /// @param currency The ERC20 token address to transfer
    /// @param orderSize The amount of tokens to transfer for the order
    function _handleIncomingCurrency(address currency, uint256 orderSize) internal {
        uint256 beforeBalance = IERC20(currency).balanceOf(address(this));
        IERC20(currency).safeTransferFrom(msg.sender, address(this), orderSize);
        uint256 afterBalance = IERC20(currency).balanceOf(address(this));

        if ((afterBalance - beforeBalance) != orderSize) {
            revert ERC20TransferAmountMismatch();
        }
    }

    /// @notice Initializes the factory proxy contract
    /// @param initialOwner Address of the contract owner
    /// @dev Can only be called once due to initializer modifier
    function initialize(address initialOwner) external initializer {
        __UUPSUpgradeable_init();
        __ReentrancyGuard_init();
        __Ownable_init(initialOwner);
    }

    /// @notice The implementation address of the factory contract
    function implementation() external view returns (address) {
        return ERC1967Utils.getImplementation();
    }

    /// @inheritdoc IHasContractName
    function contractName() public pure override returns (string memory) {
        return "ZoraCoinFactory";
    }

    /// @dev Authorizes an upgrade to a new implementation
    /// @param newImpl The new implementation address
    function _authorizeUpgrade(address newImpl) internal override onlyOwner {
        // try to get the existing contract name - if it reverts, the existing contract was an older version that didn't have the contract name
        // unfortunately we cannot use supportsInterface here because the existing implementation did not have that function
        try IHasContractName(newImpl).contractName() returns (string memory name) {
            if (!_equals(name, contractName())) {
                revert UpgradeToMismatchedContractName(contractName(), name);
            }
        } catch {}
    }

    function _equals(string memory a, string memory b) internal pure returns (bool) {
        return (keccak256(bytes(a)) == keccak256(bytes(b)));
    }
}
