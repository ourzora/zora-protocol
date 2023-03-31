// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import {IERC165} from "@openzeppelin/contracts/interfaces/IERC165.sol";
import {Initializable} from "@openzeppelin/contracts/proxy/utils/Initializable.sol";
import {IERC1155} from "@openzeppelin/contracts/token/ERC1155/IERC1155.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC721} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import {Enjoy} from "_imagine/mint/Enjoy.sol";
import {ICreatorCommands} from "../../interfaces/ICreatorCommands.sol";
import {SaleStrategy} from "../SaleStrategy.sol";
import {SaleCommandHelper} from "../utils/SaleCommandHelper.sol";
import {IZoraCreator1155} from "../../interfaces/IZoraCreator1155.sol";

contract ZoraCreatorRedeemMinterStrategy is Enjoy, SaleStrategy, Initializable {
    using SaleCommandHelper for ICreatorCommands.CommandSet;
    using SafeERC20 for IERC20;

    enum TokenType {
        NULL,
        ERC721,
        ERC1155,
        ERC20
    }

    struct RedeemToken {
        address tokenContract;
        uint256 tokenId;
        uint256 amount;
        TokenType tokenType;
    }

    struct RedeemInstruction {
        TokenType tokenType;
        uint256 amount;
        uint256 tokenIdStart;
        uint256 tokenIdEnd;
        address tokenContract;
        address transferRecipient;
        bytes4 burnFunction;
    }

    struct RedeemInstructions {
        RedeemToken redeemToken;
        RedeemInstruction[] instructions;
        uint64 saleStart;
        uint64 saleEnd;
        uint256 ethAmount;
        address ethRecipient;
    }

    event RedeemSet(address indexed target, bytes32 indexed redeemsInstructionsHash, RedeemInstructions data);
    event RedeemProcessed(address indexed target, bytes32 indexed redeemsInstructionsHash);
    event RedeemsCleared(address indexed target, bytes32[] indexed redeemInstructionsHashes);

    error RedeemInstructionAlreadySet();
    error RedeemInstructionNotAllowed();
    error IncorrectNumberOfTokenIds();
    error InvalidTokenIdsForTokenType();
    error InvalidSaleEndOrStart();
    error EmptyRedeemInstructions();
    error RedeemTokenTypeMustBeERC1155();
    error MustBurnOrTransfer();
    error IncorrectMintAmount();
    error IncorrectBurnOrTransferAmount();
    error InvalidDropContract();
    error SaleEnded();
    error SaleHasNotStarted();
    error InvalidTokenType();
    error WrongValueSent();
    error CallerNotDropContract();
    error BurnFailed();
    error MustCallClearRedeem();
    error TokenIdOutOfRange();
    error RedeemTokenContractMustBeDropContract();

    mapping(bytes32 => bool) public redeemInstructionsHashIsAllowed;

    address public dropContract;

    modifier onlyDropContract() {
        if (msg.sender != dropContract) {
            revert CallerNotDropContract();
        }
        _;
    }

    function initialize(address _dropContract) public initializer {
        if (_dropContract == address(0)) {
            revert InvalidDropContract();
        }
        dropContract = _dropContract;
    }

    function contractURI() external pure override returns (string memory) {
        return "https://github.com/ourzora/zora-1155-contracts/";
    }

    function contractName() external pure override returns (string memory) {
        return "Redeem Minter Sale Strategy";
    }

    function contractVersion() external pure override returns (string memory) {
        return "0.0.1";
    }

    function redeemInstructionsHash(RedeemInstructions memory _redeemInstructions) public pure returns (bytes32) {
        return keccak256(abi.encode(_redeemInstructions));
    }

    function validateSingleRedeemInstruction(RedeemInstruction memory _redeemInstruction) internal pure {
        if (_redeemInstruction.tokenType == TokenType.ERC20) {
            if (_redeemInstruction.tokenIdStart != 0 || _redeemInstruction.tokenIdEnd != 0) {
                revert InvalidTokenIdsForTokenType();
            }
        } else if (_redeemInstruction.tokenType == TokenType.ERC721 || _redeemInstruction.tokenType == TokenType.ERC1155) {
            if (_redeemInstruction.tokenIdStart > _redeemInstruction.tokenIdEnd) {
                revert InvalidTokenIdsForTokenType();
            }
        } else {
            revert InvalidTokenType();
        }
        if (_redeemInstruction.burnFunction != 0 && _redeemInstruction.transferRecipient != address(0)) {
            revert MustBurnOrTransfer();
        }
        if (_redeemInstruction.burnFunction == 0 && _redeemInstruction.transferRecipient == address(0)) {
            revert MustBurnOrTransfer();
        }
        if (_redeemInstruction.amount == 0) {
            revert IncorrectMintAmount();
        }
    }

    function validateRedeemInstructions(RedeemInstructions memory _redeemInstructions) public view {
        if (_redeemInstructions.saleEnd <= _redeemInstructions.saleStart || _redeemInstructions.saleEnd <= block.timestamp) {
            revert InvalidSaleEndOrStart();
        }
        if (_redeemInstructions.instructions.length == 0) {
            revert EmptyRedeemInstructions();
        }
        if (_redeemInstructions.redeemToken.tokenContract != dropContract) {
            revert RedeemTokenContractMustBeDropContract();
        }
        if (_redeemInstructions.redeemToken.tokenType != TokenType.ERC1155) {
            revert RedeemTokenTypeMustBeERC1155();
        }
        for (uint256 i = 0; i < _redeemInstructions.instructions.length; i++) {
            validateSingleRedeemInstruction(_redeemInstructions.instructions[i]);
        }
    }

    function setRedeem(RedeemInstructions calldata _redeemInstructions) external onlyDropContract {
        validateRedeemInstructions(_redeemInstructions);

        bytes32 hash = redeemInstructionsHash(_redeemInstructions);
        if (redeemInstructionsHashIsAllowed[hash]) {
            revert RedeemInstructionAlreadySet();
        }
        redeemInstructionsHashIsAllowed[redeemInstructionsHash(_redeemInstructions)] = true;

        emit RedeemSet(dropContract, hash, _redeemInstructions);
    }

    function clearRedeem(bytes32[] calldata hashes) external onlyDropContract {
        for (uint256 i = 0; i < hashes.length; i++) {
            redeemInstructionsHashIsAllowed[hashes[i]] = false;
        }
        emit RedeemsCleared(dropContract, hashes);
    }

    function requestMint(
        address,
        uint256 tokenId,
        uint256 amount,
        uint256 ethValueSent,
        bytes calldata minterArguments
    ) external onlyDropContract returns (ICreatorCommands.CommandSet memory commands) {
        (address mintTo, RedeemInstructions memory redeemInstructions, uint256[][] memory tokenIds, uint256[][] memory amounts) = abi.decode(
            minterArguments,
            (address, RedeemInstructions, uint256[][], uint256[][])
        );
        bytes32 hash = redeemInstructionsHash(redeemInstructions);
        if (!redeemInstructionsHashIsAllowed[hash]) {
            revert RedeemInstructionNotAllowed();
        }
        if (redeemInstructions.saleStart > block.timestamp) {
            revert SaleHasNotStarted();
        }
        if (redeemInstructions.saleEnd < block.timestamp) {
            revert SaleEnded();
        }
        if (redeemInstructions.instructions.length != tokenIds.length) {
            revert IncorrectNumberOfTokenIds();
        }
        if (ethValueSent != redeemInstructions.ethAmount) {
            revert WrongValueSent();
        }
        if (amount != redeemInstructions.redeemToken.amount) {
            revert IncorrectMintAmount();
        }
        for (uint256 i = 0; i < redeemInstructions.instructions.length; i++) {
            RedeemInstruction memory instruction = redeemInstructions.instructions[i];
            if (instruction.tokenType == TokenType.ERC1155) {
                _handleErc1155Redeem(instruction, mintTo, tokenIds[i], amounts[i]);
            } else if (instruction.tokenType == TokenType.ERC721) {
                _handleErc721Redeem(instruction, mintTo, tokenIds[i]);
            } else if (instruction.tokenType == TokenType.ERC20) {
                _handleErc20Redeem(instruction, mintTo);
            }
        }

        bool shouldTransferFunds = redeemInstructions.ethRecipient != address(0);
        commands.setSize(shouldTransferFunds ? 2 : 1);
        commands.mint(mintTo, tokenId, amount);

        if (shouldTransferFunds) {
            commands.transfer(redeemInstructions.ethRecipient, ethValueSent);
        }

        emit RedeemProcessed(dropContract, hash);
    }

    function _handleErc721Redeem(RedeemInstruction memory instruction, address mintTo, uint256[] memory tokenIds) internal {
        if (tokenIds.length != instruction.amount) {
            revert IncorrectBurnOrTransferAmount();
        }
        for (uint256 j = 0; j < tokenIds.length; j++) {
            if (tokenIds[j] < instruction.tokenIdStart || tokenIds[j] > instruction.tokenIdEnd) {
                revert TokenIdOutOfRange();
            }
            if (instruction.burnFunction != 0) {
                (bool success, ) = instruction.tokenContract.call(abi.encodeWithSelector(instruction.burnFunction, tokenIds[j]));
                if (!success) {
                    revert BurnFailed();
                }
            } else {
                IERC721(instruction.tokenContract).safeTransferFrom(mintTo, instruction.transferRecipient, tokenIds[j]);
            }
        }
    }

    function _handleErc1155Redeem(RedeemInstruction memory instruction, address mintTo, uint256[] memory tokenIds, uint256[] memory amounts) internal {
        if (amounts.length != tokenIds.length) {
            revert IncorrectNumberOfTokenIds();
        }
        uint256 sum;
        for (uint256 j = 0; j < tokenIds.length; j++) {
            sum += amounts[j];
            if (tokenIds[j] < instruction.tokenIdStart || tokenIds[j] > instruction.tokenIdEnd) {
                revert TokenIdOutOfRange();
            }
        }
        if (sum != instruction.amount) {
            revert IncorrectBurnOrTransferAmount();
        }
        if (instruction.burnFunction != 0) {
            (bool success, ) = instruction.tokenContract.call(abi.encodeWithSelector(instruction.burnFunction, mintTo, tokenIds, amounts));
            if (!success) {
                revert BurnFailed();
            }
        } else {
            IERC1155(instruction.tokenContract).safeBatchTransferFrom(mintTo, instruction.transferRecipient, tokenIds, amounts, bytes(""));
        }
    }

    function _handleErc20Redeem(RedeemInstruction memory instruction, address mintTo) internal {
        if (instruction.burnFunction != 0) {
            (bool success, ) = instruction.tokenContract.call(abi.encodeWithSelector(instruction.burnFunction, mintTo, instruction.amount));
            if (!success) {
                revert BurnFailed();
            }
        } else {
            IERC20(instruction.tokenContract).transferFrom(mintTo, instruction.transferRecipient, instruction.amount);
        }
    }

    function resetSale(uint256) external view override onlyDropContract {
        revert MustCallClearRedeem();
    }
}
