// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import {Initializable} from "@openzeppelin/contracts/proxy/utils/Initializable.sol";
import {IERC1155} from "@openzeppelin/contracts/token/ERC1155/IERC1155.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC721} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Enjoy} from "_imagine/mint/Enjoy.sol";

import {ICreatorCommands} from "../../interfaces/ICreatorCommands.sol";
import {SaleStrategy} from "../SaleStrategy.sol";
import {SaleCommandHelper} from "../utils/SaleCommandHelper.sol";

/*


             ░░░░░░░░░░░░░░              
        ░░▒▒░░░░░░░░░░░░░░░░░░░░        
      ░░▒▒▒▒░░░░░░░░░░░░░░░░░░░░░░      
    ░░▒▒▒▒░░░░░░░░░░░░░░    ░░░░░░░░    
   ░▓▓▒▒▒▒░░░░░░░░░░░░        ░░░░░░░    
  ░▓▓▓▒▒▒▒░░░░░░░░░░░░        ░░░░░░░░  
  ░▓▓▓▒▒▒▒░░░░░░░░░░░░░░    ░░░░░░░░░░  
  ░▓▓▓▒▒▒▒▒▒░░░░░░░░░░░░░░░░░░░░░░░░░░░  
  ░▓▓▓▓▓▒▒▒▒░░░░░░░░░░░░░░░░░░░░░░░░░░  
   ░▓▓▓▓▒▒▒▒▒▒░░░░░░░░░░░░░░░░░░░░░░░  
    ░░▓▓▓▓▒▒▒▒▒▒░░░░░░░░░░░░░░░░░░░░    
    ░░▓▓▓▓▓▓▒▒▒▒▒▒▒▒░░░░░░░░░▒▒▒▒▒░░    
      ░░▓▓▓▓▓▓▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒░░      
          ░░▓▓▓▓▓▓▓▓▓▓▓▓▒▒░░░          

               OURS TRULY,


    github.com/ourzora/zora-1155-contracts

*/

/// @title ZoraCreatorRedeemMinterStrategy
/// @notice A strategy that allows minting by redeeming other (ERC20/721/1155) tokens
/// @author @jgeary
contract ZoraCreatorRedeemMinterStrategy is Enjoy, SaleStrategy, Initializable {
    using SaleCommandHelper for ICreatorCommands.CommandSet;
    using SafeERC20 for IERC20;

    enum TokenType {
        NULL,
        ERC721,
        ERC1155,
        ERC20
    }

    struct MintToken {
        /// @notice The address of the minting token contract (always creatorContract)
        address tokenContract;
        /// @notice The mint tokenId
        uint256 tokenId;
        /// @notice The amount of tokens that can be minted
        uint256 amount;
        /// @notice The mint token type (always ERC1155)
        TokenType tokenType;
    }

    struct RedeemInstruction {
        /// @notice The type of token to be redeemed
        TokenType tokenType;
        /// @notice The amount of tokens to be redeemed
        uint256 amount;
        /// @notice The start of the range of token ids to be redeemed
        uint256 tokenIdStart;
        /// @notice The end of the range of token ids to be redeemed
        uint256 tokenIdEnd;
        /// @notice The address of the token contract to be redeemed
        address tokenContract;
        /// @notice The address to transfer the redeemed tokens to
        address transferRecipient;
        /// @notice The function to call on the token contract to burn the tokens
        bytes4 burnFunction;
    }

    struct RedeemInstructions {
        /// @notice The token to be minted
        MintToken mintToken;
        /// @notice The instructions for redeeming tokens
        RedeemInstruction[] instructions;
        /// @notice The start of the sale
        uint64 saleStart;
        /// @notice The end of the sale
        uint64 saleEnd;
        /// @notice The amount of ETH to send to the recipient
        uint256 ethAmount;
        /// @notice The address to send the ETH to (0x0 for the creator contract)
        address ethRecipient;
    }

    event RedeemSet(address indexed target, bytes32 indexed redeemsInstructionsHash, RedeemInstructions data);
    event RedeemProcessed(address indexed target, bytes32 indexed redeemsInstructionsHash, address sender, uint256[][] tokenIds, uint256[][] amounts);
    event RedeemsCleared(address indexed target, bytes32[] indexed redeemInstructionsHashes);

    error RedeemInstructionAlreadySet();
    error RedeemInstructionNotAllowed();
    error IncorrectNumberOfTokenIds();
    error InvalidTokenIdsForTokenType();
    error InvalidSaleEndOrStart();
    error EmptyRedeemInstructions();
    error MintTokenTypeMustBeERC1155();
    error MustBurnOrTransfer();
    error IncorrectMintAmount();
    error IncorrectBurnOrTransferAmount();
    error InvalidCreatorContract();
    error SaleEnded();
    error SaleHasNotStarted();
    error InvalidTokenType();
    error WrongValueSent();
    error CallerNotCreatorContract();
    error BurnFailed();
    error MustCallClearRedeem();
    error TokenIdOutOfRange();
    error MintTokenContractMustBeCreatorContract();
    error SenderIsNotTokenOwner();

    /// @notice tokenId, keccak256(abi.encode(RedeemInstructions)) => redeem instructions are allowed
    mapping(uint256 => mapping(bytes32 => bool)) public redeemInstructionsHashIsAllowed;

    /// @notice Zora creator contract
    address public creatorContract;

    modifier onlyCreatorContract() {
        if (msg.sender != creatorContract) {
            revert CallerNotCreatorContract();
        }
        _;
    }

    function initialize(address _creatorContract) public initializer {
        if (_creatorContract == address(0)) {
            revert InvalidCreatorContract();
        }
        creatorContract = _creatorContract;
    }

    /// @notice Redeem Minter Strategy contract URI
    function contractURI() external pure override returns (string memory) {
        return "https://github.com/ourzora/zora-1155-contracts/";
    }

    /// @notice Redeem Minter Strategy contract name
    function contractName() external pure override returns (string memory) {
        return "Redeem Minter Sale Strategy";
    }

    /// @notice Redeem Minter Strategy contract version
    function contractVersion() external pure override returns (string memory) {
        return "1.1.0";
    }

    /// @notice Redeem instructions object hash
    /// @param _redeemInstructions The redeem instructions object
    function redeemInstructionsHash(RedeemInstructions memory _redeemInstructions) public pure returns (bytes32) {
        return keccak256(abi.encode(_redeemInstructions));
    }

    function validateSingleRedeemInstruction(RedeemInstruction calldata _redeemInstruction) internal pure {
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

    /// @notice Validate redeem instructions
    /// @param _redeemInstructions The redeem instructions object
    function validateRedeemInstructions(RedeemInstructions calldata _redeemInstructions) public view {
        if (_redeemInstructions.saleEnd <= _redeemInstructions.saleStart || _redeemInstructions.saleEnd <= block.timestamp) {
            revert InvalidSaleEndOrStart();
        }
        if (_redeemInstructions.instructions.length == 0) {
            revert EmptyRedeemInstructions();
        }
        if (_redeemInstructions.mintToken.tokenContract != creatorContract) {
            revert MintTokenContractMustBeCreatorContract();
        }
        if (_redeemInstructions.mintToken.tokenType != TokenType.ERC1155) {
            revert MintTokenTypeMustBeERC1155();
        }

        uint256 numInstructions = _redeemInstructions.instructions.length;

        unchecked {
            for (uint256 i; i < numInstructions; ++i) {
                validateSingleRedeemInstruction(_redeemInstructions.instructions[i]);
            }
        }
    }

    /// @notice Set redeem instructions
    /// @param tokenId The token id to set redeem instructions for
    /// @param _redeemInstructions The redeem instructions object
    function setRedeem(uint256 tokenId, RedeemInstructions calldata _redeemInstructions) external onlyCreatorContract {
        if (_redeemInstructions.mintToken.tokenId != tokenId) {
            revert InvalidTokenIdsForTokenType();
        }

        validateRedeemInstructions(_redeemInstructions);

        bytes32 hash = redeemInstructionsHash(_redeemInstructions);
        if (redeemInstructionsHashIsAllowed[tokenId][hash]) {
            revert RedeemInstructionAlreadySet();
        }
        redeemInstructionsHashIsAllowed[tokenId][hash] = true;

        emit RedeemSet(creatorContract, hash, _redeemInstructions);
    }

    /// @notice Clear redeem instructions
    /// @param tokenId The token id to clear redeem instructions for
    /// @param hashes Array of redeem instructions hashes to clear
    function clearRedeem(uint256 tokenId, bytes32[] calldata hashes) external onlyCreatorContract {
        uint256 numHashes = hashes.length;

        unchecked {
            for (uint256 i; i < numHashes; ++i) {
                redeemInstructionsHashIsAllowed[tokenId][hashes[i]] = false;
            }
        }

        emit RedeemsCleared(creatorContract, hashes);
    }

    /// @notice Request mint
    /// @param tokenId The token id to mint
    /// @param amount The amount to mint
    /// @param ethValueSent The amount of eth sent
    /// @param minterArguments The abi encoded minter arguments (address, RedeemInstructions, uint256[][], uint256[][])
    function requestMint(
        address sender,
        uint256 tokenId,
        uint256 amount,
        uint256 ethValueSent,
        bytes calldata minterArguments
    ) external onlyCreatorContract returns (ICreatorCommands.CommandSet memory commands) {
        (RedeemInstructions memory redeemInstructions, uint256[][] memory tokenIds, uint256[][] memory amounts) = abi.decode(
            minterArguments,
            (RedeemInstructions, uint256[][], uint256[][])
        );
        bytes32 hash = redeemInstructionsHash(redeemInstructions);

        if (tokenId != redeemInstructions.mintToken.tokenId) {
            revert InvalidTokenIdsForTokenType();
        }
        if (!redeemInstructionsHashIsAllowed[tokenId][hash]) {
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
        if (amount != redeemInstructions.mintToken.amount) {
            revert IncorrectMintAmount();
        }

        uint256 numInstructions = redeemInstructions.instructions.length;

        unchecked {
            for (uint256 i; i < numInstructions; ++i) {
                RedeemInstruction memory instruction = redeemInstructions.instructions[i];
                if (instruction.tokenType == TokenType.ERC1155) {
                    _handleErc1155Redeem(sender, instruction, tokenIds[i], amounts[i]);
                } else if (instruction.tokenType == TokenType.ERC721) {
                    _handleErc721Redeem(sender, instruction, tokenIds[i]);
                } else if (instruction.tokenType == TokenType.ERC20) {
                    _handleErc20Redeem(sender, instruction);
                }
            }
        }

        bool shouldTransferFunds = redeemInstructions.ethRecipient != address(0);
        commands.setSize(shouldTransferFunds ? 2 : 1);
        commands.mint(sender, tokenId, amount);

        if (shouldTransferFunds) {
            commands.transfer(redeemInstructions.ethRecipient, ethValueSent);
        }

        emit RedeemProcessed(creatorContract, hash, sender, tokenIds, amounts);
    }

    function _handleErc721Redeem(address sender, RedeemInstruction memory instruction, uint256[] memory tokenIds) internal {
        uint256 numTokenIds = tokenIds.length;

        if (numTokenIds != instruction.amount) {
            revert IncorrectBurnOrTransferAmount();
        }

        unchecked {
            for (uint256 j; j < numTokenIds; j++) {
                if (tokenIds[j] < instruction.tokenIdStart || tokenIds[j] > instruction.tokenIdEnd) {
                    revert TokenIdOutOfRange();
                }
                if (instruction.burnFunction != 0) {
                    if (IERC721(instruction.tokenContract).ownerOf(tokenIds[j]) != sender) {
                        revert SenderIsNotTokenOwner();
                    }
                    (bool success, ) = instruction.tokenContract.call(abi.encodeWithSelector(instruction.burnFunction, tokenIds[j]));
                    if (!success) {
                        revert BurnFailed();
                    }
                } else {
                    IERC721(instruction.tokenContract).safeTransferFrom(sender, instruction.transferRecipient, tokenIds[j]);
                }
            }
        }
    }

    function _handleErc1155Redeem(address sender, RedeemInstruction memory instruction, uint256[] memory tokenIds, uint256[] memory amounts) internal {
        uint256 numTokenIds = tokenIds.length;

        if (amounts.length != numTokenIds) {
            revert IncorrectNumberOfTokenIds();
        }
        uint256 sum;
        for (uint256 j = 0; j < numTokenIds; ) {
            sum += amounts[j];

            if (tokenIds[j] < instruction.tokenIdStart || tokenIds[j] > instruction.tokenIdEnd) {
                revert TokenIdOutOfRange();
            }

            unchecked {
                ++j;
            }
        }

        if (sum != instruction.amount) {
            revert IncorrectBurnOrTransferAmount();
        }
        if (instruction.burnFunction != 0) {
            (bool success, ) = instruction.tokenContract.call(abi.encodeWithSelector(instruction.burnFunction, sender, tokenIds, amounts));
            if (!success) {
                revert BurnFailed();
            }
        } else {
            IERC1155(instruction.tokenContract).safeBatchTransferFrom(sender, instruction.transferRecipient, tokenIds, amounts, "");
        }
    }

    function _handleErc20Redeem(address sender, RedeemInstruction memory instruction) internal {
        if (instruction.burnFunction != 0) {
            (bool success, ) = instruction.tokenContract.call(abi.encodeWithSelector(instruction.burnFunction, sender, instruction.amount));
            if (!success) {
                revert BurnFailed();
            }
        } else {
            IERC20(instruction.tokenContract).transferFrom(sender, instruction.transferRecipient, instruction.amount);
        }
    }

    /// @notice Reset sale - Use clearRedeem instead
    function resetSale(uint256) external view override onlyCreatorContract {
        revert MustCallClearRedeem();
    }
}
