// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import {ITransferHookReceiver} from "../interfaces/ITransferHookReceiver.sol";

/// @notice Creator Base Storage Types V1
interface IZoraCreator1155TypesV1 {
    /// @notice Used to store each individual token data
    struct TokenData {
        string uri;
        uint256 maxSupply;
        uint256 totalMinted;
    }

    /// @notice Used to store contract-level configuration
    struct ContractConfig {
        address owner;
        address payable fundsRecipient;
        ITransferHookReceiver transferHook;
    }
}
