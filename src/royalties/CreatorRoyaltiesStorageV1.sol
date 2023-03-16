// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import {ICreatorRoyaltiesControl} from "../interfaces/ICreatorRoyaltiesControl.sol";

abstract contract CreatorRoyaltiesStorageV1 is ICreatorRoyaltiesControl {
    mapping(uint256 => RoyaltyConfiguration) public royalties;

    uint256[50] private __gap;
}
