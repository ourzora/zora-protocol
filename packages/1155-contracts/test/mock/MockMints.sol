// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import {ERC1155} from "@openzeppelin/contracts/token/ERC1155/ERC1155.sol";
import {TokenConfig, Redemption} from "@zoralabs/mints-contracts/src/ZoraMintsTypes.sol";
import {MintsStorageBase} from "@zoralabs/mints-contracts/src/MintsStorageBase.sol";
import {IZoraMintsManager} from "@zoralabs/mints-contracts/src/interfaces/IZoraMintsManager.sol";
import {IZoraMints1155} from "@zoralabs/mints-contracts/src/interfaces/IZoraMints1155.sol";
import {IZoraCreator1155PremintExecutorV2} from "@zoralabs/shared-contracts/interfaces/IZoraCreator1155PremintExecutorV2.sol";

contract MockMintsManager is IZoraMintsManager {
    IZoraMints1155 public zoraMints1155;
    uint256 public mintableEthToken;

    address constant ETH_ADDRESS = address(0);

    constructor(uint256 initialEthTokenId, uint256 initialEthTokenPrice) {
        TokenConfig memory tokenConfig = TokenConfig({price: initialEthTokenPrice, tokenAddress: ETH_ADDRESS, redeemHandler: address(0)});

        zoraMints1155 = new MockZoraMints1155();
        createToken(initialEthTokenId, tokenConfig, true);
    }

    function getEthPrice() external view override returns (uint256) {
        return zoraMints1155.tokenPrice(mintableEthToken);
    }

    /// This will be moved to the Mints Manager
    function mintWithEth(uint256 quantity, address recipient) external payable override returns (uint256 mintableTokenId) {
        zoraMints1155.mintTokenWithEth{value: msg.value}(mintableEthToken, quantity, recipient, "");
        mintableTokenId = mintableEthToken;
    }

    /// This will be moved to the Mints Manager
    function mintWithERC20(address, uint, address) external pure returns (uint256) {
        revert("Not implemented");
    }

    function createToken(uint256 tokenId, TokenConfig memory tokenConfig, bool defaultMintable) public {
        zoraMints1155.createToken(tokenId, tokenConfig);
        if (defaultMintable) {
            if (tokenConfig.tokenAddress != ETH_ADDRESS) {
                revert("Erc 20 not supported");
            }
            mintableEthToken = tokenId;
        }
    }

    function setDefaultMintable(address, uint256 tokenId) public {
        TokenConfig memory tokenConfig = zoraMints1155.getTokenConfig(tokenId);
        if (tokenConfig.price == 0) {
            revert("Not a token");
        }
        if (tokenConfig.tokenAddress != ETH_ADDRESS) {
            revert("Erc 20 not supported");
        }

        mintableEthToken = tokenId;
    }

    function uri(uint256) external pure returns (string memory) {
        revert("Not implemented");
    }

    function contractURI() external pure returns (string memory) {
        revert("Not implemented");
    }
}

contract MockZoraMints1155 is ERC1155, IZoraMints1155 {
    mapping(uint256 => TokenConfig) tokenConfigs;

    uint256 public constant MINIMUM_ETH_PRICE = 0.000001 ether;
    // todo: what should this be?
    uint256 public constant MINIMUM_ERC20_PRICE = 10_000;

    address constant ETH_ADDRESS = address(0);

    constructor() ERC1155("") {}

    function createToken(uint256 tokenId, TokenConfig calldata tokenConfig) public override {
        if (tokenConfigs[tokenId].price > 0) {
            revert TokenAlreadyCreated();
        }
        uint256 minimumPrice = tokenConfig.tokenAddress == ETH_ADDRESS ? MINIMUM_ETH_PRICE : MINIMUM_ERC20_PRICE;
        if (tokenConfig.price < minimumPrice) {
            revert InvalidTokenPrice();
        }

        emit TokenCreated(tokenId, tokenConfig.price, tokenConfig.tokenAddress);

        tokenConfigs[tokenId] = tokenConfig;
    }

    // called by the mints manager
    function mintTokenWithEth(uint256 tokenId, uint256 quantity, address recipient, bytes memory data) public payable {
        uint256 _tokenPrice = tokenConfigs[tokenId].price;

        if (_tokenPrice == 0) {
            revert("Token Not Created");
        }

        uint256 totalMintPrice = _tokenPrice * quantity;

        if (msg.value != totalMintPrice) {
            revert IncorrectAmountSent();
        }

        _mint(recipient, tokenId, quantity, data);
    }

    // called by the mints manager
    function mintTokenWithERC20(uint256, address, uint, address, bytes memory) external pure {
        revert("Not implemented");
    }

    function redeem(uint256 tokenId, uint256 quantity, address recipient) external override returns (Redemption memory) {
        if (recipient == address(0)) {
            revert InvalidRecipient();
        }

        _burn(msg.sender, tokenId, quantity);

        return _transferBackingBalanceToRecipient(tokenId, quantity, recipient);
    }

    function redeemBatch(
        uint256[] calldata tokenIds,
        uint256[] calldata quantities,
        address recipient
    ) external override returns (Redemption[] memory redemptions) {
        if (recipient == address(0)) {
            revert InvalidRecipient();
        }
        if (tokenIds.length != quantities.length) {
            revert ArrayLengthMismatch(tokenIds.length, quantities.length);
        }

        _burnBatch(msg.sender, tokenIds, quantities);

        redemptions = new Redemption[](tokenIds.length);

        for (uint256 i = 0; i < tokenIds.length; i++) {
            redemptions[i] = _transferBackingBalanceToRecipient(tokenIds[i], quantities[i], recipient);
        }
    }

    function _transferBackingBalanceToRecipient(uint256 tokenId, uint256 quantity, address recipient) private returns (Redemption memory redemption) {
        TokenConfig storage tokenConfig = tokenConfigs[tokenId];

        redemption.valueRedeemed = tokenConfig.price * quantity;
        redemption.tokenAddress = tokenConfig.tokenAddress;

        if (redemption.tokenAddress != ETH_ADDRESS) {
            revert("Only ETH MINTs");
        }

        safeSendETH(recipient, redemption.valueRedeemed);
    }

    function safeSendETH(address to, uint256 value) internal {
        (bool success, ) = to.call{value: value}("");

        if (!success) {
            revert("Failed to send ETH");
        }
    }

    function tokenExists(uint256 tokenId) public view override returns (bool) {
        return tokenPrice(tokenId) > 0;
    }

    function tokenPrice(uint256 tokenId) public view override returns (uint256) {
        return tokenConfigs[tokenId].price;
    }

    function getTokenConfig(uint256 tokenId) external view returns (TokenConfig memory) {
        return tokenConfigs[tokenId];
    }

    function balanceOfAccount(address) external pure override returns (uint256) {
        revert("Not implemented");
    }
}
