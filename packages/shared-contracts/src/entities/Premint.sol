// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

struct ContractCreationConfig {
    // Creator/admin of the created contract.  Must match the account that signed the message
    address contractAdmin;
    // Metadata URI for the created contract
    string contractURI;
    // Name of the created contract
    string contractName;
}

struct ContractWithAdditionalAdminsCreationConfig {
    // Creator/admin of the created contract.  Must match the account that signed the message
    address contractAdmin;
    // Metadata URI for the created contract
    string contractURI;
    // Name of the created contract
    string contractName;
    // additional collabotors that will be added as admins
    // to the contract
    address[] additionalAdmins;
}

struct PremintConfigEncoded {
    // Unique id of the token, used to ensure that multiple signatures can't be used to create the same intended token.
    // only one signature per token id, scoped to the contract hash can be executed.
    uint32 uid;
    // Version of this premint, scoped to the uid and contract.  Not used for logic in the contract, but used externally to track the newest version
    uint32 version;
    // If executing this signature results in preventing any signature with this uid from being minted.
    bool deleted;
    // abi encoded token creation config
    bytes tokenConfig;
    // hashed premint config version
    bytes32 premintConfigVersion;
}

struct PremintConfig {
    // The config for the token to be created
    TokenCreationConfig tokenConfig;
    // Unique id of the token, used to ensure that multiple signatures can't be used to create the same intended token.
    // only one signature per token id, scoped to the contract hash can be executed.
    uint32 uid;
    // Version of this premint, scoped to the uid and contract.  Not used for logic in the contract, but used externally to track the newest version
    uint32 version;
    // If executing this signature results in preventing any signature with this uid from being minted.
    bool deleted;
}

struct TokenCreationConfig {
    // Metadata URI for the created token
    string tokenURI;
    // Max supply of the created token
    uint256 maxSupply;
    // Max tokens that can be minted for an address, 0 if unlimited
    uint64 maxTokensPerAddress;
    // Price per token in eth wei. 0 for a free mint.
    uint96 pricePerToken;
    // The start time of the mint, 0 for immediate.  Prevents signatures from being used until the start time.
    uint64 mintStart;
    // The duration of the mint, starting from the first mint of this token. 0 for infinite
    uint64 mintDuration;
    // deperecated field; will be ignored.
    uint32 royaltyMintSchedule;
    // RoyaltyBPS for created tokens. The royalty amount in basis points for secondary sales.
    uint32 royaltyBPS;
    // This is the address that will be set on the `royaltyRecipient` for the created token on the 1155 contract,
    // which is the address that receives creator rewards and secondary royalties for the token,
    // and on the `fundsRecipient` on the ZoraCreatorFixedPriceSaleStrategy contract for the token,
    // which is the address that receives paid mint funds for the token.
    address royaltyRecipient;
    // Fixed price minter address
    address fixedPriceMinter;
}

struct PremintConfigV2 {
    // The config for the token to be created
    TokenCreationConfigV2 tokenConfig;
    // Unique id of the token, used to ensure that multiple signatures can't be used to create the same intended token.
    // only one signature per token id, scoped to the contract hash can be executed.
    uint32 uid;
    // Version of this premint, scoped to the uid and contract.  Not used for logic in the contract, but used externally to track the newest version
    uint32 version;
    // If executing this signature results in preventing any signature with this uid from being minted.
    bool deleted;
}

struct TokenCreationConfigV2 {
    // Metadata URI for the created token
    string tokenURI;
    // Max supply of the created token
    uint256 maxSupply;
    // Max tokens that can be minted for an address, 0 if unlimited
    uint64 maxTokensPerAddress;
    // Price per token in eth wei. 0 for a free mint.
    uint96 pricePerToken;
    // The start time of the mint, 0 for immediate.  Prevents signatures from being used until the start time.
    uint64 mintStart;
    // The duration of the mint, starting from the first mint of this token. 0 for infinite
    uint64 mintDuration;
    // RoyaltyBPS for created tokens. The royalty amount in basis points for secondary sales.
    uint32 royaltyBPS;
    // This is the address that will be set on the `royaltyRecipient` for the created token on the 1155 contract,
    // which is the address that receives creator rewards and secondary royalties for the token,
    // and on the `fundsRecipient` on the ZoraCreatorFixedPriceSaleStrategy contract for the token,
    // which is the address that receives paid mint funds for the token.
    address payoutRecipient;
    // Fixed price minter address
    address fixedPriceMinter;
    // create referral
    address createReferral;
}

struct PremintConfigV3 {
    // The config for the token to be created
    TokenCreationConfigV3 tokenConfig;
    // Unique id of the token, used to ensure that multiple signatures can't be used to create the same intended token.
    // only one signature per token id, scoped to the contract hash can be executed.
    uint32 uid;
    // Version of this premint, scoped to the uid and contract.  Not used for logic in the contract, but used externally to track the newest version
    uint32 version;
    // If executing this signature results in preventing any signature with this uid from being minted.
    bool deleted;
}

struct TokenCreationConfigV3 {
    // Metadata URI for the created token
    string tokenURI;
    // Max supply of the created token
    uint256 maxSupply;
    // RoyaltyBPS for created tokens. The royalty amount in basis points for secondary sales.
    uint32 royaltyBPS;
    // The address that the will receive rewards/funds/royalties.
    address payoutRecipient;
    // The address that referred the creation of the token.
    address createReferral;
    // The start time of the mint, 0 for immediate.
    uint64 mintStart;
    // The address of the minter module.
    address minter;
    // The abi encoded data to be passed to the minter to setup the sales config for the premint.
    bytes premintSalesConfig;
}

struct MintArguments {
    address mintRecipient;
    string mintComment;
    /// array of accounts to receive rewards - mintReferral is first argument, and platformReferral is second.  platformReferral isn't supported as of now but will be in a future release.
    address[] mintRewardsRecipients;
}

struct PremintResult {
    address contractAddress;
    uint256 tokenId;
    bool createdNewContract;
}
