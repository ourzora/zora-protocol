// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import {TokenCreationConfig, TokenCreationConfigV2, TokenCreationConfigV3} from "@zoralabs/shared-contracts/entities/Premint.sol";

// This interaface is here to provide the abi definition for the js libraries so that they can be used
// to encode these struct to pass to the premint functions that takes abi encoded bytes as input
interface IPremintDefinitions {
    function tokenConfigV1Definition(TokenCreationConfig memory) external;

    function tokenConfigV2Definition(TokenCreationConfigV2 memory) external;

    function tokenConfigV3Definition(TokenCreationConfigV3 memory) external;
}
