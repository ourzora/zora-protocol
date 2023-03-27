// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import {IERC1155} from "@openzeppelin/contracts/token/ERC1155/IERC1155.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC721} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import {Enjoy} from "_imagine/mint/Enjoy.sol";
import {ICreatorCommands} from "../../interfaces/ICreatorCommands.sol";
import {SaleStrategy} from "../SaleStrategy.sol";
import {SaleCommandHelper} from "../utils/SaleCommandHelper.sol";

contract ZoraCreatorRedemptionMinterStrategy is Enjoy, SaleStrategy {
    using SaleCommandHelper for ICreatorCommands.CommandSet;
    using SafeERC20 for IERC20;

    enum TokenType {
        NULL,
        ERC721,
        ERC1155,
        ERC20
    }

    struct RedemptionToken {
        address tokenContract;
        uint256 tokenId;
        uint256 amount;
        TokenType tokenType;
    }

    struct RedemptionInstruction {
        TokenType tokenType;
        uint256 amount;
        uint256 tokenIdStart;
        uint256 tokenIdEnd;
        address tokenContractAddress;
        address transferRecipient;
        bytes4 burnFunction;
    }

    struct RedemptionInstructions {
        RedemptionToken redemptionToken;
        RedemptionInstruction[] instructions;
        uint64 saleStart;
        uint64 saleEnd;
        uint256 ethAmount;
        address ethRecipient;
    }

    struct RedemptionArgs {
        uint256 tokenId;
        uint256 tokenIdRangeEnd;
    }

    event RedemptionInstructionSet(address indexed target, RedemptionInstructions data);
    event RedemptionProcessed(address indexed target, RedemptionToken redeemed, RedemptionArgs[] args);

    error RedemptionInstructionAlreadySet();
    error RedemptionInstructionNotSet();
    error IncorrectNumberOfRedemptionArgs();
    error ExternalCallFailed();
    error InvalidTokenIdsForTokenType();
    error InvalidSaleEndOrStart();
    error EthRecipientCannotBeZero();
    error EmptyRedemptionInstructions();
    error RedemptionTokeMustBeDropContract();
    error MustBurnOrTransfer();
    error IncorrectAmount();
    error InvalidDropContract();
    error SaleEnded();
    error SaleHasNotStarted();
    error InvalidTokenType();
    error WrongValueSent();
    error CallerNotDropContract();
    error BurnFailed();
    error MustCallClearRedemption();

    mapping(bytes32 => bool) redemptionInstructionsSet;

    address public immutable dropContract;

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
        return "Redemption Minter Sale Strategy";
    }

    function contractVersion() external pure override returns (string memory) {
        return "0.0.1";
    }

    function hashRedemptionInstructions(RedemptionInstructions memory _redemptionInstructions) public pure returns (bytes32) {
        return keccak256(abi.encode(_redemptionInstructions));
    }

    function validateRedemptionInstruction(RedemptionInstruction memory _redemptionInstruction) public pure {
        if (_redemptionInstruction.tokenType == TokenType.ERC20) {
            if (_redemptionInstruction.tokenIdStart != 0 && _redemptionInstruction.tokenIdEnd != 0) {
                revert InvalidTokenIdsForTokenType();
            }
        } else if (_redemptionInstruction.tokenType == TokenType.ERC721) {
            if (_redemptionInstruction.tokenIdStart != _redemptionInstruction.tokenIdEnd) {
                revert InvalidTokenIdsForTokenType();
            }
        } else if (_redemptionInstruction.tokenType == TokenType.ERC1155) {
            if (_redemptionInstruction.tokenIdStart > _redemptionInstruction.tokenIdEnd) {
                revert InvalidTokenIdsForTokenType();
            }
        } else {
            revert InvalidTokenType();
        }
        if (_redemptionInstruction.burnFunction != 0 && _redemptionInstruction.transferRecipient != address(0)) {
            revert MustBurnOrTransfer();
        }
        if (_redemptionInstruction.burnFunction == 0 && _redemptionInstruction.transferRecipient == address(0)) {
            revert MustBurnOrTransfer();
        }
        if (_redemptionInstruction.amount == 0) {
            revert IncorrectAmount();
        }
    }

    function validateRedemptionInstructions(RedemptionInstructions memory _redemptionInstructions) public view {
        if (_redemptionInstructions.saleEnd <= _redemptionInstructions.saleStart || _redemptionInstructions.saleEnd <= block.timestamp) {
            revert InvalidSaleEndOrStart();
        }
        if (_redemptionInstructions.ethAmount > 0 && _redemptionInstructions.ethRecipient == address(0)) {
            revert EthRecipientCannotBeZero();
        }
        if (_redemptionInstructions.instructions.length == 0) {
            revert EmptyRedemptionInstructions();
        }
        if (_redemptionInstructions.redemptionToken.tokenContract != dropContract) {
            revert InvalidTokenType();
        }
        if (_redemptionInstructions.redemptionToken.tokenType != TokenType.ERC1155) {
            revert RedemptionTokeMustBeDropContract();
        }
    }

    function setRedemption(RedemptionInstructions calldata _redemptionInstructions) external onlyDropContract {
        validateRedemptionInstructions(_redemptionInstructions);
        for (uint256 i = 0; i < _redemptionInstructions.instructions.length; i++) {
            validateRedemptionInstruction(_redemptionInstructions.instructions[i]);
        }
        bytes32 hash = hashRedemptionInstructions(_redemptionInstructions);
        if (redemptionInstructionsSet[hash]) {
            revert RedemptionInstructionAlreadySet();
        }

        redemptionInstructionsSet[hashRedemptionInstructions(_redemptionInstructions)] = true;
        emit RedemptionInstructionSet(dropContract, _redemptionInstructions);
    }

    function clearRedemption(bytes32 hash) external onlyDropContract {
        redemptionInstructionsSet[hash] = false;
    }

    function redemptionIsSet(bytes32 hash) external view returns (bool) {
        return redemptionInstructionsSet[hash];
    }

    function requestMint(
        address,
        uint256 tokenId,
        uint256 amount,
        uint256 ethValueSent,
        bytes calldata minterArguments
    ) external onlyDropContract returns (ICreatorCommands.CommandSet memory commands) {
        (address mintTo, RedemptionInstructions memory redemptionInstructions, RedemptionArgs[] memory redemptionArgs) = abi.decode(
            minterArguments,
            (address, RedemptionInstructions, RedemptionArgs[])
        );
        if (!redemptionInstructionsSet[hashRedemptionInstructions(redemptionInstructions)]) {
            revert RedemptionInstructionNotSet();
        }
        if (redemptionInstructions.saleStart > block.timestamp) {
            revert SaleHasNotStarted();
        }
        if (redemptionInstructions.saleEnd < block.timestamp) {
            revert SaleEnded();
        }
        if (redemptionInstructions.instructions.length != redemptionArgs.length) {
            revert IncorrectNumberOfRedemptionArgs();
        }
        if (ethValueSent != redemptionInstructions.ethAmount) {
            revert WrongValueSent();
        }
        for (uint256 i = 0; i < redemptionInstructions.instructions.length; i++) {
            RedemptionInstruction memory instruction = redemptionInstructions.instructions[i];
            RedemptionArgs memory args = redemptionArgs[i];
            if (instruction.tokenType == TokenType.ERC1155) {
                uint256[] memory tokenIds = new uint256[](1);
                tokenIds[0] = args.tokenId;
                uint256[] memory amounts = new uint256[](1);
                amounts[0] = instruction.amount;
                if (instruction.transferRecipient == address(0)) {
                    (bool success, ) = instruction.tokenContractAddress.call(abi.encodeWithSelector(instruction.burnFunction, mintTo, tokenIds, amounts));
                    if (!success) {
                        revert BurnFailed();
                    }
                } else {
                    IERC1155(instruction.tokenContractAddress).safeTransferFrom(
                        mintTo,
                        instruction.transferRecipient,
                        args.tokenId,
                        instruction.amount,
                        bytes("")
                    );
                }
            } else if (instruction.tokenType == TokenType.ERC721) {
                if (args.tokenId > args.tokenIdRangeEnd) {
                    revert InvalidTokenIdsForTokenType();
                }
                if (1 + args.tokenIdRangeEnd - args.tokenId != amount) {
                    revert IncorrectAmount();
                }
                for (uint256 j = args.tokenId; j <= args.tokenIdRangeEnd; j++) {
                    if (instruction.transferRecipient == address(0)) {
                        (bool success, ) = instruction.tokenContractAddress.call(abi.encodeWithSelector(instruction.burnFunction, j));
                        if (!success) {
                            revert BurnFailed();
                        }
                    } else {
                        IERC721(instruction.tokenContractAddress).safeTransferFrom(mintTo, instruction.transferRecipient, j);
                    }
                }
            } else if (instruction.tokenType == TokenType.ERC20) {
                if (instruction.transferRecipient == address(0)) {
                    (bool success, ) = instruction.tokenContractAddress.call(abi.encodeWithSelector(instruction.burnFunction, mintTo, instruction.amount));
                    if (!success) {
                        revert BurnFailed();
                    }
                } else {
                    IERC20(instruction.tokenContractAddress).transferFrom(mintTo, instruction.transferRecipient, instruction.amount);
                }
            }
        }

        bool shouldTransferFunds = redemptionInstructions.ethRecipient != address(0);
        commands.setSize(shouldTransferFunds ? 2 : 1);
        commands.mint(mintTo, tokenId, amount);

        if (shouldTransferFunds) {
            commands.transfer(redemptionInstructions.ethRecipient, ethValueSent);
        }

        emit RedemptionProcessed(dropContract, redemptionInstructions.redemptionToken, redemptionArgs);
    }

    function resetSale(uint256) external view override onlyDropContract {
        revert MustCallClearRedemption();
    }
}
