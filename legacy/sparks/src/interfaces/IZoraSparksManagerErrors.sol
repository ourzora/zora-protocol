// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import {IZoraSparks1155Errors} from "./IZoraSparks1155.sol";

interface IZoraSparksManagerErrors is IZoraSparks1155Errors {
    error PremintExecutorCannotBeZero();
    error InvalidAdminAction();
    error InvalidOwnerForAssociatedZoraSparks();
    error DefaultOwnerCannotBeZero();
}
