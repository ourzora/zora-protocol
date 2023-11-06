---
"@zoralabs/zora-1155-contracts": minor
---

Premint v2 - adding a new signature, where `createReferral` can be specified.  `ZoraCreator1155PremintExecutor` recognizes new version of the signature, and still works with the v1 (legacy) version of the signature.  1155 contract has been updated to now take abi encoded premint config, premint config version, and send it to an external library to decode the config, the signer, and setup actions.

`mintReferral` and `mintRecipient` are now specified in the premint functions, via the `MintArguments mintArguments` param; new `premintV1` and `premintV2` function now take the `MintArguments` struct as an argument which contains `mintRecipient`, defining  which account will receive the minted tokens, `mintComment`, and `mintReferral`, defining which account will receive a mintReferral reward, if any.  `mintRecipient` must be specified or else it reverts.

ZoraCreator1155PremintExecutor can now validate signatures by passing it the contract address, instead of needing to pass the full contract creation config, enabling it to validate signatures for 1155 contracts that were not created via the premint executor contract.  This allows premints signatures to be validated on contracts that have been upgrade to a version that supports premints, and allows premints to be created on contracts that were not created via the premint executor contract.

1155 contract has been updated to now take abi encoded premint config, premint config version, and send it to an external library to decode the config, the signer, and setup actions.  

changes to `ZoraCreator1155PremintExecutorImpl`:

`PremintConfigV2` are updated to containe `createReferral`, and now look like:
```solidity
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
    // The address that will receive creatorRewards, secondary royalties, and paid mint funds.  This is the address that will be set on the `royaltyRecipient` for the created token on the 1155 contract, which is the address that receives creator rewards and secondary royalties for the token, and on the `fundsRecipient` on the ZoraCreatorFixedPriceSaleStrategy contract for the token, which is the address that receives paid mint funds for the token.
    address payoutRecipient;
    // Fixed price minter address
    address fixedPriceMinter;
    // create referral
    address createReferral;
}
```
`PremintConfig` fields are **the same as they were before, but are treated as a version 1**:

```solidity
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
    // RoyaltyMintSchedule for created tokens. Every nth token will go to the royalty recipient.
    uint32 royaltyMintSchedule;
    // RoyaltyBPS for created tokens. The royalty amount in basis points for secondary sales.
    uint32 royaltyBPS;
    // RoyaltyRecipient for created tokens. The address that will receive the royalty payments.
    address royaltyRecipient;
    // Fixed price minter address
    address fixedPriceMinter;
}
```

### changes to `ZoraCreator1155PremintExecutorImpl`:

* new function `premintV1` - takes a `PremintConfig`, and premint v1 signature, and executes a premint, with added functionality of being able to specify mint referral and mint recipient
* new function `premintV2` - takes a `PremintConfigV2` signature and executes a premint, with being able to specify mint referral and mint recipient
* deprecated function `premint` - call `premintV1` instead
* new function `isValidSignatureV1` - takes an 1155 address, contract admin, premint v1 config and signature,  and validates the signature.  Can be used for 1155 contracts that were not created via the premint executor contract.
* new function `isValidSignatureV2` - takes an 1155 address, contract admin, premint v2 config and signature,  and validates the signature.  Can be used for 1155 contracts that were not created via the premint executor contract.
* deprecated function `isValidSignature` - call `isValidSignatureV1` instead

### changes to `Zora1155Impl`:

* `delegateSetupNewToken` now takes an abi encoded premintConfig (of any version), and premint config version, and sends it to an external library to decode the config, the signer, and setup actions.  Previously it took a non-encoded PremintConfig.  This new changes allows this function signature to support multiple versions of a premint config, while offloading decoding of the config and the corresponding setup actions to the external library.  This ultimately allows supporting multiple versions of a premint config and corresponding signature without increasing codespace.