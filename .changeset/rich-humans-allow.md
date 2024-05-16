---
"@zoralabs/zora-1155-contracts": minor
---

Updates to Premint that enables preminting against contracts that were not created via premint, as well as adding collaborators to premint contracts by being able specify an array of additionalAdmins in a premint's contract creation config.

#### No breaking changes

These updates are fully backwards compatible; the old functions on the contracts are still intact and will work. Additionally, these updates dont require a new premint config version to be signed; the only thing that could be affected is the deterministic address to be signed against, in the case there are additional contract admins.

#### Ability to add contract-wide additional admins with premint

There is a new struct called `ContractWithAdditionalAdminsCreationConfig` that replaces `ContractCreationConfig`. This contains, in addition to the existing fields, a new array `address[] additionalAdmins` - these addresses are added as additional admins when a contract is created by converting each address into a setup action that adds the contract-wide role `PERMISSION_BIT_ADMIN` to that account.

```solidity
// new struct:
struct ContractWithAdditionalAdminsCreationConfig {
  // Creator/admin of the created contract.  Must match the account that signed the message
  address contractAdmin;
  // Metadata URI for the created contract
  string contractURI;
  // Name of the created contract
  string contractName;
  // additional accounts that will be added as admins
  // to the contract
  address[] additionalAdmins;
}

// existing struct that is replaced:
struct ContractCreationConfig {
  address contractAdmin;
  string contractURI;
  string contractName;
}
```

Having a list of `additionalAdmins` results in the 1155 contract having a different deterministic address, based on a `salt` made from a hash of the array of `setupActions` that are generated to add those additional accounts as admins. As a result, the creator and additional admins would be signing a message against an address expected to be deterministic with consideration for those additional admins.

To get the address in consideration of the new admins, there is a new function on the preminter contract:

```solidity
// new function that takes into consideration the additional admins:
function getContractWithAdditionalAdminsAddress(
  ContractWithAdditionalAdminsCreationConfig calldata contractConfig
) public view override returns (address);

// existing function can be called if there are no additional admins:
function getContractAddress(
  ContractCreationConfig calldata contractConfig
) public view override returns (address);
```

This should be called to get the expected contract address when there are additional admins.

To determine if an address is authorized to create a premint when there are additional admins, there is a new function:

```solidity
// new function that takes into consideration the additional admins:
function isAuthorizedToCreatePremintWithAdditionalAdmins(
  address signer,
  address premintContractConfigContractAdmin,
  address contractAddress,
  address[] calldata additionalAdmins
) public view returns (bool isAuthorized);

// existing function can be called if there are no additional admins:
function isAuthorizedToCreatePremint(
  address signer,
  address premintContractConfigContractAdmin,
  address contractAddress
) public view returns (bool isAuthorized);
```

If any account in those `additionalAdmins`, it is considered authorized and can also sign a premint against the contract address of the original premint, before the contract is created. The collaborator's premint can be brought onchain first, and the original admin will be set as the admin along with all the `additionalAdmins`.

#### New ability to do premints against existing contracts

Executing premint against contracts not created via premint can be done with a new function on the preminter called `premintExistingContract`; instead of it taking a `ContractWithAdditionalAdminsCreationConfig`, it takes an 1155 contract address:

```solidity
function premintExistingContract(
  address tokenContract,
  bytes calldata encodedPremintConfig,
  string calldata premintConfigVersion,
  bytes calldata signature,
  uint256 quantityToMint,
  MintArguments calldata mintArguments,
  address firstMinter,
  address signerContract
) external payable returns (uint256 tokenId);
```

This contract address must be a zora creator 1155 contract that already supports premint, which is version 2.0.0 and up.

#### New shared functions for preminting with new or existing contracts.

In order to avoid having to create one function each for premint v1, v2, and future versions of premint, the new function `premintExistingContact` takes an abi encoded `premintConfig`, in addition to a `premintConfigVersion`; the abi encoded premint config can be a premintV1, premintV2, or erc20Premint.

Correspondingly the existing `premintV1/premintV2/premintERC20` functions are deprecated in favor of a function `premintNewContract` that takes the already abi encoded `premintConfig`, and corresponding `premintConfigVersion`. This single function works with all versions of premint configs:

```solidity
function premintExistingContract(
  address tokenContract,
  bytes calldata encodedPremintConfig,
  string calldata premintConfigVersion,
  bytes calldata signature,
  uint256 quantityToMint,
  MintArguments calldata mintArguments,
  address firstMinter,
  address signerContract
) external payable returns (uint256 tokenId);
```

```solidity
function premintNewContract(
  ContractWithAdditionalAdminsCreationConfig calldata contractConfig,
  bytes calldata encodedPremintConfig,
  string calldata premintConfigVersion,
  bytes calldata signature,
  uint256 quantityToMint,
  MintArguments calldata mintArguments,
  address firstMinter,
  address signerContract
) external payable returns (PremintResult memory);
```

#### 1155 factory's createContractDeterministic resulting address is affected by `setupActions`

The FactoryProxy's `createContractDeterministic` function now takes into consideration the `bytes[] calldata setupActions` when creating the contract at the deterministic address. This won't affect contracts that don't have any setup actions, as their address will be the same as it was before.
