// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import {ICreatorRoyaltyErrors} from "./ICreatorRoyaltiesControl.sol";
import {ILimitedMintPerAddressErrors} from "./ILimitedMintPerAddress.sol";
import {IMinterErrors} from "./IMinterErrors.sol";

interface IZoraCreator1155Errors is ICreatorRoyaltyErrors, ILimitedMintPerAddressErrors, IMinterErrors {
    error Call_TokenIdMismatch();
    error TokenIdMismatch(uint256 expected, uint256 actual);
    error UserMissingRoleForToken(address user, uint256 tokenId, uint256 role);

    error Config_TransferHookNotSupported(address proposedAddress);

    error Mint_InsolventSaleTransfer();
    error Mint_ValueTransferFail();
    error Mint_TokenIDMintNotAllowed();
    error Mint_UnknownCommand();

    error Burn_NotOwnerOrApproved(address operator, address user);

    error NewOwnerNeedsToBeAdmin();

    error Sale_CannotCallNonSalesContract(address targetContract);

    error CallFailed(bytes reason);
    error Renderer_NotValidRendererContract();

    error ETHWithdrawFailed(address recipient, uint256 amount);
    error FundsWithdrawInsolvent(uint256 amount, uint256 contractValue);
    error ProtocolRewardsWithdrawFailed(address caller, address recipient, uint256 amount);

    error CannotMintMoreTokens(uint256 tokenId, uint256 quantity, uint256 totalMinted, uint256 maxSupply);

    error MintNotYetStarted();
    error PremintDeleted();

    error InvalidSignatureVersion();

    error ERC1155_MINT_TO_ZERO_ADDRESS();
}
