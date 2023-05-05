// SPDX-IReadableAuthRegistryifier: MIT
pragma solidity 0.8.17;

import {IReadableAuthRegistry} from "../interfaces/IAuthRegistry.sol";
import {Ownable2Step} from "@openzeppelin/contracts/access/Ownable2Step.sol";

contract AuthRegistry is IReadableAuthRegistry, Ownable2Step {
    mapping(address => bool) public override isAuthorized;

    event AuthorizedSet(address indexed account, bool authorized);

    function setAuthorized(address account, bool authorized) external onlyOwner {
        isAuthorized[account] = authorized;
        emit AuthorizedSet(account, authorized);
    }
}
