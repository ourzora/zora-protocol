// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import {IERC165} from "@openzeppelin/contracts/interfaces/IERC165.sol";
import {IERC1155} from "@openzeppelin/contracts/token/ERC1155/IERC1155.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC721} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";

import {IMinter1155} from "../../interfaces/IMinter1155.sol";
import {ICreatorCommands} from "../../interfaces/ICreatorCommands.sol";
import {TransferHelperUtils} from "../../utils/TransferHelperUtils.sol";
import {SaleStrategy} from "../SaleStrategy.sol";
import {ICreatorCommands} from "../../interfaces/ICreatorCommands.sol";
import {SaleCommandHelper} from "../SaleCommandHelper.sol";

contract ZoraCreatorTokenRedemptionMinterStrategy is SaleStrategy {
    using SaleCommandHelper for ICreatorCommands.CommandSet;

    enum RedemptionTokenType {
        NULL,
        ERC721,
        ERC1155,
        ERC20
    }

    // info about one single redemption
    struct RedemptionSettings {
        uint256 ethAmountPerMint;
        uint256 redemptionAmountPerMint;
        uint64 redemptionStart;
        uint64 redemptionEnd;
        address redemptionRecipient;
        address fundsRecipient;
    }

    struct RedemptionToken {
        address token;
        uint256 tokenId;
    }

    // redemption key (tokenId, redemptionContract, redemptionTokenId) => sale settings
    mapping(bytes32 => RedemptionSettings) redemptionSettings;

    // redemption contract key (tokenId, redemptionContract) => redemption token type
    mapping(bytes32 => RedemptionTokenType) redemptionTokenTypes;

    // tokenId => array of redemption tokens
    mapping(uint256 => RedemptionToken[]) redemptionTokens;

    address public immutable dropContract;

    event SaleSet(uint256 tokenId, RedemptionToken redemptionToken, RedemptionSettings redemptionSettings);

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
        return "Token Redemption Sale Strategy";
    }

    function contractVersion() external pure override returns (string memory) {
        return "0.0.1";
    }

    function _validateMint(uint256 ethValueSent, uint256 ethAmountPerMint, uint256 quantity, uint64 redemptionStart, uint64 redemptionEnd) internal view {
        if (ethValueSent != ethAmountPerMint * quantity) {
            revert WrongValueSent();
        }
        if (redemptionStart > block.timestamp) {
            revert SaleHasNotStarted();
        }
        if (redemptionEnd < block.timestamp) {
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
        (address mintTo, address redemptionToken, uint256[] memory tokenIds) = abi.decode(minterArguments, (address, address, uint256[]));
        RedemptionTokenType redemptionTokenType = redemptionTokenTypes[keccak256(abi.encodePacked(tokenId, redemptionToken))];
        RedemptionSettings memory settings;
        if (redemptionTokenType == RedemptionTokenType.ERC1155) {
            settings = redemptionSettings[keccak256(abi.encodePacked(tokenId, redemptionToken, tokenIds[0]))];
            if (tokenIds.length != 1) {
                revert IncorrectNumberOfTokenIdsProvided();
            }
            _validateMint(ethValueSent, settings.ethAmountPerMint, quantity, settings.redemptionStart, settings.redemptionEnd);
            IERC1155(redemptionToken).safeTransferFrom(mintTo, settings.redemptionRecipient, tokenIds[0], quantity * settings.redemptionAmountPerMint, "");
        } else if (redemptionTokenType == RedemptionTokenType.ERC20) {
            settings = redemptionSettings[keccak256(abi.encodePacked(tokenId, redemptionToken, uint256(0)))];
            if (tokenIds.length != 0) {
                revert IncorrectNumberOfTokenIdsProvided();
            }
            _validateMint(ethValueSent, settings.ethAmountPerMint, quantity, settings.redemptionStart, settings.redemptionEnd);
            IERC20(redemptionToken).transferFrom(mintTo, settings.redemptionRecipient, quantity * settings.redemptionAmountPerMint);
        } else if (redemptionTokenType == RedemptionTokenType.ERC721) {
            settings = redemptionSettings[keccak256(abi.encodePacked(tokenId, redemptionToken, uint256(0)))];
            if (tokenIds.length == 0 || tokenIds.length * settings.redemptionAmountPerMint != quantity) {
                revert IncorrectNumberOfTokenIdsProvided();
            }
            _validateMint(ethValueSent, settings.ethAmountPerMint, quantity, settings.redemptionStart, settings.redemptionEnd);
            for (uint256 i = 0; i < tokenIds.length; i++) {
                IERC721(redemptionToken).safeTransferFrom(mintTo, settings.redemptionRecipient, tokenIds[i]);
            }
        } else {
            revert NoSaleSet();
        }

        bool shouldTransferFunds = settings.fundsRecipient != address(0);
        commands.setSize(shouldTransferFunds ? 2 : 1);
        commands.mint(mintTo, tokenId, quantity);

        if (shouldTransferFunds) {
            commands.transfer(settings.fundsRecipient, ethValueSent);
        }
    }

    function setTokenRedemption(
        uint256 _tokenId,
        RedemptionToken memory _redemptionToken,
        RedemptionSettings memory _redemptionSettings,
        RedemptionTokenType _redemptionTokenType
    ) external onlyDropContract {
        if (_redemptionTokenType != RedemptionTokenType.ERC1155 && _redemptionToken.tokenId != 0) {
            revert IncorrectNumberOfTokenIdsProvided();
        }
        if (_redemptionTokenType == RedemptionTokenType.NULL) {
            revert InvalidTokenType();
        }
        if (_redemptionSettings.redemptionEnd < block.timestamp) {
            revert SaleEnded();
        }

        redemptionSettings[keccak256(abi.encodePacked(_tokenId, _redemptionToken.token, _redemptionToken.tokenId))] = _redemptionSettings;
        redemptionTokens[_tokenId].push(_redemptionToken);
        redemptionTokenTypes[keccak256(abi.encodePacked(_tokenId, _redemptionToken.token))] = _redemptionTokenType;

        emit SaleSet(_tokenId, _redemptionToken, _redemptionSettings);
    }

    function resetSale(uint256 _tokenId) external override onlyDropContract {
        if (redemptionTokens[_tokenId].length == 0) {
            revert NoSaleSet();
        }
        for (uint256 i = 0; i < redemptionTokens[_tokenId].length; i++) {
            RedemptionToken memory _redemptionToken = redemptionTokens[_tokenId][i];
            bytes32 redemptionKey = keccak256(abi.encodePacked(_tokenId, _redemptionToken.token, _redemptionToken.tokenId));

            delete redemptionSettings[redemptionKey];
            delete redemptionTokenTypes[keccak256(abi.encodePacked(_tokenId, _redemptionToken.token))];

            emit SaleSet(_tokenId, _redemptionToken, redemptionSettings[redemptionKey]);
        }

        delete redemptionTokens[_tokenId];
    }

    function sale(uint256 _tokenId, address _redemptionToken, uint256 _erc1155RedemptionTokenTokenId) external view returns (RedemptionSettings memory) {
        return redemptionSettings[keccak256(abi.encodePacked(_tokenId, _redemptionToken, _erc1155RedemptionTokenTokenId))];
    }
}
