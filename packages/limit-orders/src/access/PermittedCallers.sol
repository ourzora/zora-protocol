// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {Ownable2Step} from "@openzeppelin/contracts/access/Ownable2Step.sol";

abstract contract PermittedCallers is Ownable2Step {
    address private constant PUBLIC_ACCESS = address(0);

    mapping(address caller => bool permitted) private _permittedCallers;

    event PermittedCallerUpdated(address indexed caller, bool permitted);

    error CallerNotPermitted();
    error PermittedCallersLengthMismatch();

    constructor(address owner_) Ownable(owner_) {
        _permittedCallers[PUBLIC_ACCESS] = true;
    }

    modifier onlyPermitted() {
        _onlyPermitted();
        _;
    }

    function _onlyPermitted() internal view {
        require(_isPermitted(msg.sender), CallerNotPermitted());
    }

    function isPermittedCaller(address caller) public view returns (bool) {
        return _isPermitted(caller);
    }

    function setPermittedCallers(address[] calldata callers, bool[] calldata permitted) external onlyOwner {
        require(callers.length == permitted.length, PermittedCallersLengthMismatch());
        for (uint256 i = 0; i < callers.length; i++) {
            _permittedCallers[callers[i]] = permitted[i];
            emit PermittedCallerUpdated(callers[i], permitted[i]);
        }
    }

    function _isPermitted(address caller) internal view returns (bool) {
        return _permittedCallers[PUBLIC_ACCESS] || _permittedCallers[caller];
    }
}
