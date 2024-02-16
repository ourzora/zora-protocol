// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

interface IHasCreatorAttribution {
    event CreatorAttribution(bytes32 structHash, string domainName, string version, address creator, bytes signature);
}

interface IHasSupportedPremintSignatureVersions {
    function supportedPremintSignatureVersions() external pure returns (string[] memory);
}

// this is the current version of the Zora Token contract creation
interface ISupportsAABasedDelegatedTokenCreation {
    function delegateSetupNewToken(
        bytes memory premintConfigEncoded,
        bytes32 premintVersion,
        bytes calldata signature,
        address sender,
        address premintSignerContract
    ) external returns (uint256 newTokenId);
}

interface IZoraCreator1155DelegatedCreation is IHasCreatorAttribution, IHasSupportedPremintSignatureVersions, ISupportsAABasedDelegatedTokenCreation {}

// this was the legacy interface which has both functions bundled in it - ideally these would be defined in their
// own interfaces that can be checked if the interface method is supported.  going forward (above) they are separate
interface IZoraCreator1155DelegatedCreationLegacy {
    event CreatorAttribution(bytes32 structHash, string domainName, string version, address creator, bytes signature);

    function supportedPremintSignatureVersions() external pure returns (string[] memory);

    function delegateSetupNewToken(
        bytes memory premintConfigEncoded,
        bytes32 premintVersion,
        bytes calldata signature,
        address sender
    ) external returns (uint256 newTokenId);
}
