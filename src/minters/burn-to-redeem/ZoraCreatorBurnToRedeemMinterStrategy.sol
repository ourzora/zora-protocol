// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import {IERC165} from "@openzeppelin/contracts/interfaces/IERC165.sol";
import {IERC1155} from "@openzeppelin/contracts/token/ERC1155/IERC1155.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC721} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import {IMinter1155} from "../../interfaces/IMinter1155.sol";
import {ICreatorCommands} from "../../interfaces/ICreatorCommands.sol";
import {TransferHelperUtils} from "../../utils/TransferHelperUtils.sol";
import {SaleStrategy} from "../SaleStrategy.sol";
import {ICreatorCommands} from "../../interfaces/ICreatorCommands.sol";
import {SaleCommandHelper} from "../SaleCommandHelper.sol";
import {IVersionedContract} from "../../interfaces/IVersionedContract.sol";

contract ZoraCreatorBurnToRedeemMinterStrategy is SaleStrategy {
    using SaleCommandHelper for ICreatorCommands.CommandSet;
    using SafeERC20 for IERC20;

    enum BurnTokenType {
        NULL,
        ERC721,
        ERC1155,
        ERC20
    }

    struct BurnToRedeemSettings {
        uint96 ethAmountPerRedeem;
        uint96 burnAmountPerRedeem;
        uint64 burnToRedeemStart;
        address ethRecipient;
        uint64 burnToRedeemEnd;
        bytes4 burnFunctionSelector;
    }

    struct BurnToken {
        address token;
        uint256 tokenId;
    }

    // mint token id => burn token => burn token id => burn to redeem settings
    mapping(uint256 => mapping(address => mapping(uint256 => BurnToRedeemSettings))) burnToRedeemSettingsForToken;

    // mint tokenId => redemption contract => burn token type
    mapping(address => BurnTokenType) burnTokenTypes;

    // tokenId => array of burn tokens
    mapping(uint256 => BurnToken[]) burnTokensConfiguredForMintTokenId;

    address public immutable dropContract;

    event SaleSet(uint256 tokenId, BurnToken burnToken, BurnToRedeemSettings burnToRedeemSettings);

    error InvalidDropContract();
    error SaleEnded();
    error SaleHasNotStarted();
    error MintedTooManyForAddress();
    error RedeemableTokenTransferFailed();
    error InvalidTokenType();
    error IncorrectNumberOfTokenIdsProvided();
    error WrongValueSent();
    error CallerNotDropContract();
    error NoSaleSet();
    error BurnFailed();

    modifier onlyDropContract() {
        if (msg.sender != dropContract) {
            revert CallerNotDropContract();
        }
        _;
    }

    constructor(address _dropContract) {
        if (_dropContract == address(0)) {
            revert InvalidDropContract();
        }
        dropContract = _dropContract;
    }

    function contractURI() external pure override returns (string memory) {
        return "";
    }

    function contractName() external pure override returns (string memory) {
        return "Burn To Redeem Sale Strategy";
    }

    function contractVersion() external pure override returns (string memory) {
        return "0.0.1";
    }

    function _validateMint(uint256 ethValueSent, uint96 ethAmountPerRedeem, uint256 quantity, uint64 burnToRedeemStart, uint64 burnToRedeemEnd) internal view {
        if (ethValueSent != ethAmountPerRedeem * quantity) {
            revert WrongValueSent();
        }
        if (burnToRedeemStart > block.timestamp) {
            revert SaleHasNotStarted();
        }
        if (burnToRedeemEnd < block.timestamp) {
            revert SaleEnded();
        }
    }

    function requestMint(
        address,
        uint256 tokenId,
        uint256 quantity,
        uint256 ethValueSent,
        bytes calldata minterArguments
    ) external onlyDropContract returns (ICreatorCommands.CommandSet memory commands) {
        (address mintTo, address burnToken, uint256[] memory tokenIds) = abi.decode(minterArguments, (address, address, uint256[]));
        BurnTokenType burnTokenType = burnTokenTypes[burnToken];
        BurnToRedeemSettings memory settings;
        if (burnTokenType == BurnTokenType.ERC1155) {
            settings = burnToRedeemSettingsForToken[tokenId][burnToken][tokenIds[0]];
            if (tokenIds.length != 1) {
                revert IncorrectNumberOfTokenIdsProvided();
            }
            _validateMint(ethValueSent, settings.ethAmountPerRedeem, quantity, settings.burnToRedeemStart, settings.burnToRedeemEnd);
            uint256[] memory amounts = new uint256[](1);
            amounts[0] = quantity * settings.burnAmountPerRedeem;
            (bool burnSuccess, ) = burnToken.call(abi.encodeWithSelector(settings.burnFunctionSelector, mintTo, tokenIds, amounts));
            if (!burnSuccess) {
                revert BurnFailed();
            }
        } else if (burnTokenType == BurnTokenType.ERC20) {
            settings = burnToRedeemSettingsForToken[tokenId][burnToken][uint256(0)];
            if (tokenIds.length != 0) {
                revert IncorrectNumberOfTokenIdsProvided();
            }
            _validateMint(ethValueSent, settings.ethAmountPerRedeem, quantity, settings.burnToRedeemStart, settings.burnToRedeemEnd);
            (bool burnSuccess, ) = burnToken.call(abi.encodeWithSelector(settings.burnFunctionSelector, mintTo, quantity * settings.burnAmountPerRedeem));
            if (!burnSuccess) {
                revert BurnFailed();
            }
        } else if (burnTokenType == BurnTokenType.ERC721) {
            settings = burnToRedeemSettingsForToken[tokenId][burnToken][uint256(0)];
            if (tokenIds.length == 0 || tokenIds.length * settings.burnAmountPerRedeem != quantity) {
                revert IncorrectNumberOfTokenIdsProvided();
            }
            _validateMint(ethValueSent, settings.ethAmountPerRedeem, quantity, settings.burnToRedeemStart, settings.burnToRedeemEnd);
            for (uint256 i = 0; i < tokenIds.length; i++) {
                (bool burnSuccess, ) = burnToken.call(abi.encodeWithSelector(settings.burnFunctionSelector, tokenIds[i]));
                if (!burnSuccess) {
                    revert BurnFailed();
                }
            }
        } else {
            revert NoSaleSet();
        }

        bool shouldTransferFunds = settings.ethRecipient != address(0);
        commands.setSize(shouldTransferFunds ? 2 : 1);
        commands.mint(mintTo, tokenId, quantity);

        if (shouldTransferFunds) {
            commands.transfer(settings.ethRecipient, ethValueSent);
        }
    }

    function setBurnToRedeemForToken(
        uint256 _tokenId,
        BurnToken memory _burnToken,
        BurnToRedeemSettings memory _burnToRedeemSettings,
        BurnTokenType _burnTokenType
    ) external onlyDropContract {
        if (_burnTokenType != BurnTokenType.ERC1155 && _burnToken.tokenId != 0) {
            revert IncorrectNumberOfTokenIdsProvided();
        }

        if (_burnTokenType == BurnTokenType.NULL) {
            revert InvalidTokenType();
        }
        if (_burnToRedeemSettings.burnToRedeemEnd < block.timestamp) {
            revert SaleEnded();
        }

        burnToRedeemSettingsForToken[_tokenId][_burnToken.token][_burnToken.tokenId] = _burnToRedeemSettings;
        burnTokensConfiguredForMintTokenId[_tokenId].push(_burnToken);
        burnTokenTypes[_burnToken.token] = _burnTokenType;

        emit SaleSet(_tokenId, _burnToken, _burnToRedeemSettings);
    }

    function resetSale(uint256 _tokenId) external override onlyDropContract {
        if (burnTokensConfiguredForMintTokenId[_tokenId].length == 0) {
            revert NoSaleSet();
        }
        for (uint256 i = 0; i < burnTokensConfiguredForMintTokenId[_tokenId].length; i++) {
            BurnToken memory _burnToken = burnTokensConfiguredForMintTokenId[_tokenId][i];

            delete burnToRedeemSettingsForToken[_tokenId][_burnToken.token][_burnToken.tokenId];
            delete burnTokenTypes[_burnToken.token];

            emit SaleSet(_tokenId, _burnToken, burnToRedeemSettingsForToken[_tokenId][_burnToken.token][_burnToken.tokenId]);
        }

        delete burnTokensConfiguredForMintTokenId[_tokenId];
    }

    function sale(uint256 _tokenId, address _burnToken, uint256 _erc1155BurnTokenId) external view returns (BurnToRedeemSettings memory) {
        uint256 erc1155BurnTokenId = 0;
        if (burnTokenTypes[_burnToken] == BurnTokenType.ERC1155) {
            erc1155BurnTokenId = _erc1155BurnTokenId;
        }
        return burnToRedeemSettingsForToken[_tokenId][_burnToken][erc1155BurnTokenId];
    }

    function getBurnToRedeemSettings(uint256 _tokenId, address _burnToken, uint256 _erc1155BurnTokenId) external view returns (BurnToRedeemSettings memory) {
        uint256 erc1155BurnTokenId = 0;
        if (burnTokenTypes[_burnToken] == BurnTokenType.ERC1155) {
            erc1155BurnTokenId = _erc1155BurnTokenId;
        }
        return burnToRedeemSettingsForToken[_tokenId][_burnToken][erc1155BurnTokenId];
    }

    function getBurnTokenType(address _burnToken) external view returns (BurnTokenType) {
        return burnTokenTypes[_burnToken];
    }
}
