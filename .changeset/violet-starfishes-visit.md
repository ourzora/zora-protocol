---
"@zoralabs/zora-1155-contracts": minor
---

# Premint v2

### New fields on signature

Adding a new `PremintConfigV2` struct that can be signed, that now contains a `createReferral`.  `ZoraCreator1155PremintExecutor` recognizes new version of the `PremintConfig`, and still works with the v1 (legacy) version of the `PremintConfig`.  

Additional changes to the `PremintConfigV2`:
* `tokenConfig.royaltyMintSchedule` has been removed as it is deprecated and no longer recognized by new versions of the 1155 contract
* `tokenConfig.royaltyRecipient` has been renamed to `tokenConfig.payoutRecipient` to better reflect the fact that this address is used to receive creator rewards, secondary royalties, and paid mint funds.  This is the address that will be set on the `royaltyRecipient` for the created token on the 1155 contract, which is the address that receives creator rewards and secondary royalties for the token, and on the `fundsRecipient` on the ZoraCreatorFixedPriceSaleStrategy contract for the token, which is the address that receives paid mint funds for the token.

### New MintArguments on premint functions, specifying `mintRecipient` and `mintReferral`

`mintReferral` and `mintRecipient` are now specified in the premint functions on the `ZoraCreator1155PremintExecutor`, via the `MintArguments mintArguments` param; new `premintV1` and `premintV2` function now take the `MintArguments` struct as an argument which contains `mintRecipient`, defining  which account will receive the minted tokens, `mintComment`, and `mintReferral`, defining which account will receive a mintReferral reward, if any.  `mintRecipient` must be specified or else it reverts.

### New signature validation methods

ZoraCreator1155PremintExecutor can now validate signatures by passing it the contract address, instead of needing to pass the full contract creation config, enabling it to validate signatures for 1155 contracts that were not created via the premint executor contract.  This allows premints signatures to be validated on contracts that have been upgraded to a version that supports premints, and allows premints to be created on contracts that were not created via the premint executor contract. These functions are called `isValidSignatureV1` and `isValidSignatureV2` for v1 and v2 of the premint config structs and signatures correspondingly.

### Changes to handling of setting of fundsRecipient

Previously the `fundsRecipient` on the fixeed priced minters sales config for the token was set to the signer of the premint.  This has been changed to be set to the `payoutRecipient` of the premint config for v2 of premint config, and to the `royaltyRecipient` of the premint config for v1 of the premint config, for 1155 contracts that are to be newly created, and for existing 1155 contracts that are upgraded to the latest version and execute a v1 of the premint config.

### Changes to 1155's `delegateSetupNewToken`

`delegateSetupNewToken` on 1155 contract has been updated to now take an abi encoded premint config, premint config version, and send it to an external library to decode the config, the signer, and setup actions.  Previously it took a non-encoded PremintConfig.  This new change allows this function signature to support multiple versions of a premint config, while offloading decoding of the config and the corresponding setup actions to the external library.  This ultimately allows supporting multiple versions of a premint config and corresponding signature without increasing codespace. 

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
    // deperecated field; will be ignored.
    uint32 royaltyMintSchedule;
    // RoyaltyBPS for created tokens. The royalty amount in basis points for secondary sales.
    uint32 royaltyBPS;
    // The address that will receive creatorRewards, secondary royalties, and paid mint funds.  This is the address that will be set on the `royaltyRecipient` for the created token on the 1155 contract, which is the address that receives creator rewards and secondary royalties for the token, and on the `fundsRecipient` on the ZoraCreatorFixedPriceSaleStrategy contract for the token, which is the address that receives paid mint funds for the token.
    address royaltyRecipient;
    // Fixed price minter address
    address fixedPriceMinter;
}
```

### changes to `ZoraCreator1155PremintExecutorImpl`:

* new function `premintV1` - takes a `PremintConfig`, and premint v1 signature, and executes a premint, with added functionality of being able to specify mint referral and mint recipient
* new function `premintV2` - takes a `PremintConfigV2` signature and executes a premint, with being able to specify mint referral and mint recipient
* deprecated function `premint` - call `premintV1` instead
* new function

```solidity
isAuthorizedToCreatePremint(
        address signer,
        address premintContractConfigContractAdmin,
        address contractAddress
) public view returns (bool isAuthorized)
``` 

takes a signer, contractConfig.contractAdmin, and 1155 address, and determines if the signer is authorized to sign premints on the given contract.  Replaces `isValidSignature` - by putting the burden on clients to first decode the signature, then pass the recovered signer to this function to determine if the signer has premint authorization on the contract.
* deprecated function `isValidSignature` - call `isValidSignatureV1` instead
