// SPDX-License-Identifier: MIT
pragma solidity >=0.8.17;

interface IHasContractName {
    /// @notice Contract name returns the pretty contract name
    function contractName() external returns (string memory);
}

interface IContractMetadata is IHasContractName {
    /// @notice Contract URI returns the uri for more information about the given contract
    function contractURI() external returns (string memory);
}
