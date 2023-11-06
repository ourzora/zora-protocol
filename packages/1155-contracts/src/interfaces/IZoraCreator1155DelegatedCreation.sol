// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

interface IZoraCreator1155DelegatedCreation {
    event CreatorAttribution(bytes32 structHash, string domainName, string version, address creator, bytes signature);

    function supportedPremintSignatureVersions() external pure returns (string[] memory);

    function delegateSetupNewToken(
        bytes memory premintConfigEncoded,
        bytes32 premintVersion,
        bytes calldata signature,
        address sender
    ) external returns (uint256 newTokenId);
}
