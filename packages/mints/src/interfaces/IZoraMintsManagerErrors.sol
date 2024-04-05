// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import {IZoraMints1155Errors} from "./IZoraMints1155.sol";

interface IZoraMintsManagerErrors is IZoraMints1155Errors {
    error PremintExecutorCannotBeZero();
    error InvalidAdminAction();
    error InvalidOwnerForAssociatedZoraMints();
    error DefaultOwnerCannotBeZero();
}
