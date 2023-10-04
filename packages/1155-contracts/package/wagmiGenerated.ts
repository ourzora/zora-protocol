//////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
// DeterministicProxyDeployer
//////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

export const deterministicProxyDeployerABI = [
  { stateMutability: "nonpayable", type: "constructor", inputs: [] },
  {
    type: "error",
    inputs: [
      { name: "expected", internalType: "address", type: "address" },
      { name: "actual", internalType: "address", type: "address" },
    ],
    name: "FactoryProxyAddressMismatch",
  },
  { type: "error", inputs: [], name: "FailedToInitGenericDeployedContract" },
  { type: "error", inputs: [], name: "InvalidShortString" },
  {
    type: "error",
    inputs: [{ name: "str", internalType: "string", type: "string" }],
    name: "StringTooLong",
  },
  { type: "event", anonymous: false, inputs: [], name: "EIP712DomainChanged" },
  {
    stateMutability: "nonpayable",
    type: "function",
    inputs: [
      { name: "genericCreationSalt", internalType: "bytes32", type: "bytes32" },
      { name: "creationCode", internalType: "bytes", type: "bytes" },
      { name: "initCall", internalType: "bytes", type: "bytes" },
      { name: "signature", internalType: "bytes", type: "bytes" },
    ],
    name: "createAndInitGenericContractDeterministic",
    outputs: [
      { name: "resultAddress", internalType: "address", type: "address" },
    ],
  },
  {
    stateMutability: "nonpayable",
    type: "function",
    inputs: [
      { name: "proxyShimSalt", internalType: "bytes32", type: "bytes32" },
      { name: "proxySalt", internalType: "bytes32", type: "bytes32" },
      { name: "proxyCreationCode", internalType: "bytes", type: "bytes" },
      {
        name: "expectedFactoryProxyAddress",
        internalType: "address",
        type: "address",
      },
      {
        name: "implementationAddress",
        internalType: "address",
        type: "address",
      },
      { name: "owner", internalType: "address", type: "address" },
      { name: "signature", internalType: "bytes", type: "bytes" },
    ],
    name: "createFactoryProxyDeterministic",
    outputs: [
      { name: "factoryProxyAddress", internalType: "address", type: "address" },
    ],
  },
  {
    stateMutability: "view",
    type: "function",
    inputs: [],
    name: "eip712Domain",
    outputs: [
      { name: "fields", internalType: "bytes1", type: "bytes1" },
      { name: "name", internalType: "string", type: "string" },
      { name: "version", internalType: "string", type: "string" },
      { name: "chainId", internalType: "uint256", type: "uint256" },
      { name: "verifyingContract", internalType: "address", type: "address" },
      { name: "salt", internalType: "bytes32", type: "bytes32" },
      { name: "extensions", internalType: "uint256[]", type: "uint256[]" },
    ],
  },
  {
    stateMutability: "view",
    type: "function",
    inputs: [
      { name: "proxyShimSalt", internalType: "bytes32", type: "bytes32" },
      { name: "proxySalt", internalType: "bytes32", type: "bytes32" },
      { name: "proxyCreationCode", internalType: "bytes", type: "bytes" },
      {
        name: "implementationAddress",
        internalType: "address",
        type: "address",
      },
      { name: "newOwner", internalType: "address", type: "address" },
    ],
    name: "hashedDigestFactoryProxy",
    outputs: [{ name: "", internalType: "bytes32", type: "bytes32" }],
  },
  {
    stateMutability: "view",
    type: "function",
    inputs: [
      { name: "salt", internalType: "bytes32", type: "bytes32" },
      { name: "creationCode", internalType: "bytes", type: "bytes" },
      { name: "initCall", internalType: "bytes", type: "bytes" },
    ],
    name: "hashedDigestGenericCreation",
    outputs: [{ name: "", internalType: "bytes32", type: "bytes32" }],
  },
  {
    stateMutability: "pure",
    type: "function",
    inputs: [
      { name: "digest", internalType: "bytes32", type: "bytes32" },
      { name: "signature", internalType: "bytes", type: "bytes" },
    ],
    name: "recoverSignature",
    outputs: [{ name: "", internalType: "address", type: "address" }],
  },
] as const;

//////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
// IImmutableCreate2Factory
//////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

/**
 * - [__View Contract on Ethereum Etherscan__](https://etherscan.io/address/0x0000000000FFe8B47B3e2130213B802212439497)
 * - [__View Contract on Goerli Etherscan__](https://goerli.etherscan.io/address/0x0000000000FFe8B47B3e2130213B802212439497)
 * - [__View Contract on Op Mainnet Optimism Explorer__](https://explorer.optimism.io/address/0x0000000000FFe8B47B3e2130213B802212439497)
 * - [__View Contract on Optimism Goerli Etherscan__](https://goerli-optimism.etherscan.io/address/0x0000000000FFe8B47B3e2130213B802212439497)
 * - [__View Contract on Zora Goerli Testnet Explorer__](https://testnet.explorer.zora.energy/address/0x0000000000FFe8B47B3e2130213B802212439497)
 * - [__View Contract on Base Basescan__](https://basescan.org/address/0x0000000000FFe8B47B3e2130213B802212439497)
 * - [__View Contract on Base Goerli Basescan__](https://goerli.basescan.org/address/0x0000000000FFe8B47B3e2130213B802212439497)
 * - [__View Contract on Zora Explorer__](https://explorer.zora.energy/address/0x0000000000FFe8B47B3e2130213B802212439497)
 * - [__View Contract on Sepolia Etherscan__](https://sepolia.etherscan.io/address/0x0000000000FFe8B47B3e2130213B802212439497)
 */
export const iImmutableCreate2FactoryABI = [
  {
    stateMutability: "view",
    type: "function",
    inputs: [
      { name: "salt", internalType: "bytes32", type: "bytes32" },
      { name: "initCode", internalType: "bytes", type: "bytes" },
    ],
    name: "findCreate2Address",
    outputs: [
      { name: "deploymentAddress", internalType: "address", type: "address" },
    ],
  },
  {
    stateMutability: "view",
    type: "function",
    inputs: [
      { name: "salt", internalType: "bytes32", type: "bytes32" },
      { name: "initCodeHash", internalType: "bytes32", type: "bytes32" },
    ],
    name: "findCreate2AddressViaHash",
    outputs: [
      { name: "deploymentAddress", internalType: "address", type: "address" },
    ],
  },
  {
    stateMutability: "view",
    type: "function",
    inputs: [
      { name: "deploymentAddress", internalType: "address", type: "address" },
    ],
    name: "hasBeenDeployed",
    outputs: [{ name: "", internalType: "bool", type: "bool" }],
  },
  {
    stateMutability: "payable",
    type: "function",
    inputs: [
      { name: "salt", internalType: "bytes32", type: "bytes32" },
      { name: "initializationCode", internalType: "bytes", type: "bytes" },
    ],
    name: "safeCreate2",
    outputs: [
      { name: "deploymentAddress", internalType: "address", type: "address" },
    ],
  },
] as const;

/**
 * - [__View Contract on Ethereum Etherscan__](https://etherscan.io/address/0x0000000000FFe8B47B3e2130213B802212439497)
 * - [__View Contract on Goerli Etherscan__](https://goerli.etherscan.io/address/0x0000000000FFe8B47B3e2130213B802212439497)
 * - [__View Contract on Op Mainnet Optimism Explorer__](https://explorer.optimism.io/address/0x0000000000FFe8B47B3e2130213B802212439497)
 * - [__View Contract on Optimism Goerli Etherscan__](https://goerli-optimism.etherscan.io/address/0x0000000000FFe8B47B3e2130213B802212439497)
 * - [__View Contract on Zora Goerli Testnet Explorer__](https://testnet.explorer.zora.energy/address/0x0000000000FFe8B47B3e2130213B802212439497)
 * - [__View Contract on Base Basescan__](https://basescan.org/address/0x0000000000FFe8B47B3e2130213B802212439497)
 * - [__View Contract on Base Goerli Basescan__](https://goerli.basescan.org/address/0x0000000000FFe8B47B3e2130213B802212439497)
 * - [__View Contract on Zora Explorer__](https://explorer.zora.energy/address/0x0000000000FFe8B47B3e2130213B802212439497)
 * - [__View Contract on Sepolia Etherscan__](https://sepolia.etherscan.io/address/0x0000000000FFe8B47B3e2130213B802212439497)
 */
export const iImmutableCreate2FactoryAddress = {
  1: "0x0000000000FFe8B47B3e2130213B802212439497",
  5: "0x0000000000FFe8B47B3e2130213B802212439497",
  10: "0x0000000000FFe8B47B3e2130213B802212439497",
  420: "0x0000000000FFe8B47B3e2130213B802212439497",
  424: "0x0000000000FFe8B47B3e2130213B802212439497",
  999: "0x0000000000FFe8B47B3e2130213B802212439497",
  8453: "0x0000000000FFe8B47B3e2130213B802212439497",
  58008: "0x0000000000FFe8B47B3e2130213B802212439497",
  84531: "0x0000000000FFe8B47B3e2130213B802212439497",
  7777777: "0x0000000000FFe8B47B3e2130213B802212439497",
  11155111: "0x0000000000FFe8B47B3e2130213B802212439497",
} as const;

/**
 * - [__View Contract on Ethereum Etherscan__](https://etherscan.io/address/0x0000000000FFe8B47B3e2130213B802212439497)
 * - [__View Contract on Goerli Etherscan__](https://goerli.etherscan.io/address/0x0000000000FFe8B47B3e2130213B802212439497)
 * - [__View Contract on Op Mainnet Optimism Explorer__](https://explorer.optimism.io/address/0x0000000000FFe8B47B3e2130213B802212439497)
 * - [__View Contract on Optimism Goerli Etherscan__](https://goerli-optimism.etherscan.io/address/0x0000000000FFe8B47B3e2130213B802212439497)
 * - [__View Contract on Zora Goerli Testnet Explorer__](https://testnet.explorer.zora.energy/address/0x0000000000FFe8B47B3e2130213B802212439497)
 * - [__View Contract on Base Basescan__](https://basescan.org/address/0x0000000000FFe8B47B3e2130213B802212439497)
 * - [__View Contract on Base Goerli Basescan__](https://goerli.basescan.org/address/0x0000000000FFe8B47B3e2130213B802212439497)
 * - [__View Contract on Zora Explorer__](https://explorer.zora.energy/address/0x0000000000FFe8B47B3e2130213B802212439497)
 * - [__View Contract on Sepolia Etherscan__](https://sepolia.etherscan.io/address/0x0000000000FFe8B47B3e2130213B802212439497)
 */
export const iImmutableCreate2FactoryConfig = {
  address: iImmutableCreate2FactoryAddress,
  abi: iImmutableCreate2FactoryABI,
} as const;

//////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
// ZoraCreator1155FactoryImpl
//////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

/**
 * - [__View Contract on Ethereum Etherscan__](https://etherscan.io/address/0x777777C338d93e2C7adf08D102d45CA7CC4Ed021)
 * - [__View Contract on Goerli Etherscan__](https://goerli.etherscan.io/address/0x777777C338d93e2C7adf08D102d45CA7CC4Ed021)
 * - [__View Contract on Op Mainnet Optimism Explorer__](https://explorer.optimism.io/address/0x777777C338d93e2C7adf08D102d45CA7CC4Ed021)
 * - [__View Contract on Optimism Goerli Etherscan__](https://goerli-optimism.etherscan.io/address/0x777777C338d93e2C7adf08D102d45CA7CC4Ed021)
 * - [__View Contract on Zora Goerli Testnet Explorer__](https://testnet.explorer.zora.energy/address/0x777777C338d93e2C7adf08D102d45CA7CC4Ed021)
 * - [__View Contract on Base Basescan__](https://basescan.org/address/0x777777C338d93e2C7adf08D102d45CA7CC4Ed021)
 * - [__View Contract on Base Goerli Basescan__](https://goerli.basescan.org/address/0x777777C338d93e2C7adf08D102d45CA7CC4Ed021)
 * - [__View Contract on Zora Explorer__](https://explorer.zora.energy/address/0x777777C338d93e2C7adf08D102d45CA7CC4Ed021)
 * - [__View Contract on Sepolia Etherscan__](https://sepolia.etherscan.io/address/0x13dAA8E9e3f68deDE7b1386ACdc12eA98F2FB688)
 */
export const zoraCreator1155FactoryImplABI = [
  {
    stateMutability: "nonpayable",
    type: "constructor",
    inputs: [
      {
        name: "_zora1155Impl",
        internalType: "contract IZoraCreator1155",
        type: "address",
      },
      {
        name: "_merkleMinter",
        internalType: "contract IMinter1155",
        type: "address",
      },
      {
        name: "_fixedPriceMinter",
        internalType: "contract IMinter1155",
        type: "address",
      },
      {
        name: "_redeemMinterFactory",
        internalType: "contract IMinter1155",
        type: "address",
      },
    ],
  },
  { type: "error", inputs: [], name: "ADDRESS_DELEGATECALL_TO_NON_CONTRACT" },
  { type: "error", inputs: [], name: "ADDRESS_LOW_LEVEL_CALL_FAILED" },
  { type: "error", inputs: [], name: "Constructor_ImplCannotBeZero" },
  { type: "error", inputs: [], name: "ERC1967_NEW_IMPL_NOT_CONTRACT" },
  { type: "error", inputs: [], name: "ERC1967_NEW_IMPL_NOT_UUPS" },
  { type: "error", inputs: [], name: "ERC1967_UNSUPPORTED_PROXIABLEUUID" },
  {
    type: "error",
    inputs: [],
    name: "FUNCTION_MUST_BE_CALLED_THROUGH_ACTIVE_PROXY",
  },
  {
    type: "error",
    inputs: [],
    name: "FUNCTION_MUST_BE_CALLED_THROUGH_DELEGATECALL",
  },
  {
    type: "error",
    inputs: [],
    name: "INITIALIZABLE_CONTRACT_ALREADY_INITIALIZED",
  },
  {
    type: "error",
    inputs: [],
    name: "INITIALIZABLE_CONTRACT_IS_NOT_INITIALIZING",
  },
  { type: "error", inputs: [], name: "ONLY_OWNER" },
  { type: "error", inputs: [], name: "ONLY_PENDING_OWNER" },
  { type: "error", inputs: [], name: "OWNER_CANNOT_BE_ZERO_ADDRESS" },
  {
    type: "error",
    inputs: [],
    name: "UUPS_UPGRADEABLE_MUST_NOT_BE_CALLED_THROUGH_DELEGATECALL",
  },
  {
    type: "error",
    inputs: [
      { name: "expected", internalType: "string", type: "string" },
      { name: "actual", internalType: "string", type: "string" },
    ],
    name: "UpgradeToMismatchedContractName",
  },
  {
    type: "event",
    anonymous: false,
    inputs: [
      {
        name: "previousAdmin",
        internalType: "address",
        type: "address",
        indexed: false,
      },
      {
        name: "newAdmin",
        internalType: "address",
        type: "address",
        indexed: false,
      },
    ],
    name: "AdminChanged",
  },
  {
    type: "event",
    anonymous: false,
    inputs: [
      {
        name: "beacon",
        internalType: "address",
        type: "address",
        indexed: true,
      },
    ],
    name: "BeaconUpgraded",
  },
  { type: "event", anonymous: false, inputs: [], name: "FactorySetup" },
  {
    type: "event",
    anonymous: false,
    inputs: [
      { name: "version", internalType: "uint8", type: "uint8", indexed: false },
    ],
    name: "Initialized",
  },
  {
    type: "event",
    anonymous: false,
    inputs: [
      {
        name: "owner",
        internalType: "address",
        type: "address",
        indexed: true,
      },
      {
        name: "canceledOwner",
        internalType: "address",
        type: "address",
        indexed: true,
      },
    ],
    name: "OwnerCanceled",
  },
  {
    type: "event",
    anonymous: false,
    inputs: [
      {
        name: "owner",
        internalType: "address",
        type: "address",
        indexed: true,
      },
      {
        name: "pendingOwner",
        internalType: "address",
        type: "address",
        indexed: true,
      },
    ],
    name: "OwnerPending",
  },
  {
    type: "event",
    anonymous: false,
    inputs: [
      {
        name: "prevOwner",
        internalType: "address",
        type: "address",
        indexed: true,
      },
      {
        name: "newOwner",
        internalType: "address",
        type: "address",
        indexed: true,
      },
    ],
    name: "OwnerUpdated",
  },
  {
    type: "event",
    anonymous: false,
    inputs: [
      {
        name: "newContract",
        internalType: "address",
        type: "address",
        indexed: true,
      },
      {
        name: "creator",
        internalType: "address",
        type: "address",
        indexed: true,
      },
      {
        name: "defaultAdmin",
        internalType: "address",
        type: "address",
        indexed: true,
      },
      {
        name: "contractURI",
        internalType: "string",
        type: "string",
        indexed: false,
      },
      { name: "name", internalType: "string", type: "string", indexed: false },
      {
        name: "defaultRoyaltyConfiguration",
        internalType: "struct ICreatorRoyaltiesControl.RoyaltyConfiguration",
        type: "tuple",
        components: [
          {
            name: "royaltyMintSchedule",
            internalType: "uint32",
            type: "uint32",
          },
          { name: "royaltyBPS", internalType: "uint32", type: "uint32" },
          {
            name: "royaltyRecipient",
            internalType: "address",
            type: "address",
          },
        ],
        indexed: false,
      },
    ],
    name: "SetupNewContract",
  },
  {
    type: "event",
    anonymous: false,
    inputs: [
      {
        name: "implementation",
        internalType: "address",
        type: "address",
        indexed: true,
      },
    ],
    name: "Upgraded",
  },
  {
    stateMutability: "nonpayable",
    type: "function",
    inputs: [],
    name: "acceptOwnership",
    outputs: [],
  },
  {
    stateMutability: "nonpayable",
    type: "function",
    inputs: [],
    name: "cancelOwnershipTransfer",
    outputs: [],
  },
  {
    stateMutability: "pure",
    type: "function",
    inputs: [],
    name: "contractName",
    outputs: [{ name: "", internalType: "string", type: "string" }],
  },
  {
    stateMutability: "pure",
    type: "function",
    inputs: [],
    name: "contractURI",
    outputs: [{ name: "", internalType: "string", type: "string" }],
  },
  {
    stateMutability: "pure",
    type: "function",
    inputs: [],
    name: "contractVersion",
    outputs: [{ name: "", internalType: "string", type: "string" }],
  },
  {
    stateMutability: "nonpayable",
    type: "function",
    inputs: [
      { name: "newContractURI", internalType: "string", type: "string" },
      { name: "name", internalType: "string", type: "string" },
      {
        name: "defaultRoyaltyConfiguration",
        internalType: "struct ICreatorRoyaltiesControl.RoyaltyConfiguration",
        type: "tuple",
        components: [
          {
            name: "royaltyMintSchedule",
            internalType: "uint32",
            type: "uint32",
          },
          { name: "royaltyBPS", internalType: "uint32", type: "uint32" },
          {
            name: "royaltyRecipient",
            internalType: "address",
            type: "address",
          },
        ],
      },
      {
        name: "defaultAdmin",
        internalType: "address payable",
        type: "address",
      },
      { name: "setupActions", internalType: "bytes[]", type: "bytes[]" },
    ],
    name: "createContract",
    outputs: [{ name: "", internalType: "address", type: "address" }],
  },
  {
    stateMutability: "nonpayable",
    type: "function",
    inputs: [
      { name: "newContractURI", internalType: "string", type: "string" },
      { name: "name", internalType: "string", type: "string" },
      {
        name: "defaultRoyaltyConfiguration",
        internalType: "struct ICreatorRoyaltiesControl.RoyaltyConfiguration",
        type: "tuple",
        components: [
          {
            name: "royaltyMintSchedule",
            internalType: "uint32",
            type: "uint32",
          },
          { name: "royaltyBPS", internalType: "uint32", type: "uint32" },
          {
            name: "royaltyRecipient",
            internalType: "address",
            type: "address",
          },
        ],
      },
      {
        name: "defaultAdmin",
        internalType: "address payable",
        type: "address",
      },
      { name: "setupActions", internalType: "bytes[]", type: "bytes[]" },
    ],
    name: "createContractDeterministic",
    outputs: [{ name: "", internalType: "address", type: "address" }],
  },
  {
    stateMutability: "view",
    type: "function",
    inputs: [],
    name: "defaultMinters",
    outputs: [
      {
        name: "minters",
        internalType: "contract IMinter1155[]",
        type: "address[]",
      },
    ],
  },
  {
    stateMutability: "view",
    type: "function",
    inputs: [
      { name: "msgSender", internalType: "address", type: "address" },
      { name: "newContractURI", internalType: "string", type: "string" },
      { name: "name", internalType: "string", type: "string" },
      { name: "contractAdmin", internalType: "address", type: "address" },
    ],
    name: "deterministicContractAddress",
    outputs: [{ name: "", internalType: "address", type: "address" }],
  },
  {
    stateMutability: "view",
    type: "function",
    inputs: [],
    name: "fixedPriceMinter",
    outputs: [
      { name: "", internalType: "contract IMinter1155", type: "address" },
    ],
  },
  {
    stateMutability: "view",
    type: "function",
    inputs: [],
    name: "implementation",
    outputs: [{ name: "", internalType: "address", type: "address" }],
  },
  {
    stateMutability: "nonpayable",
    type: "function",
    inputs: [
      { name: "_initialOwner", internalType: "address", type: "address" },
    ],
    name: "initialize",
    outputs: [],
  },
  {
    stateMutability: "view",
    type: "function",
    inputs: [],
    name: "merkleMinter",
    outputs: [
      { name: "", internalType: "contract IMinter1155", type: "address" },
    ],
  },
  {
    stateMutability: "view",
    type: "function",
    inputs: [],
    name: "owner",
    outputs: [{ name: "", internalType: "address", type: "address" }],
  },
  {
    stateMutability: "view",
    type: "function",
    inputs: [],
    name: "pendingOwner",
    outputs: [{ name: "", internalType: "address", type: "address" }],
  },
  {
    stateMutability: "view",
    type: "function",
    inputs: [],
    name: "proxiableUUID",
    outputs: [{ name: "", internalType: "bytes32", type: "bytes32" }],
  },
  {
    stateMutability: "view",
    type: "function",
    inputs: [],
    name: "redeemMinterFactory",
    outputs: [
      { name: "", internalType: "contract IMinter1155", type: "address" },
    ],
  },
  {
    stateMutability: "nonpayable",
    type: "function",
    inputs: [],
    name: "resignOwnership",
    outputs: [],
  },
  {
    stateMutability: "nonpayable",
    type: "function",
    inputs: [{ name: "_newOwner", internalType: "address", type: "address" }],
    name: "safeTransferOwnership",
    outputs: [],
  },
  {
    stateMutability: "nonpayable",
    type: "function",
    inputs: [{ name: "_newOwner", internalType: "address", type: "address" }],
    name: "transferOwnership",
    outputs: [],
  },
  {
    stateMutability: "nonpayable",
    type: "function",
    inputs: [
      { name: "newImplementation", internalType: "address", type: "address" },
    ],
    name: "upgradeTo",
    outputs: [],
  },
  {
    stateMutability: "payable",
    type: "function",
    inputs: [
      { name: "newImplementation", internalType: "address", type: "address" },
      { name: "data", internalType: "bytes", type: "bytes" },
    ],
    name: "upgradeToAndCall",
    outputs: [],
  },
  {
    stateMutability: "view",
    type: "function",
    inputs: [],
    name: "zora1155Impl",
    outputs: [
      { name: "", internalType: "contract IZoraCreator1155", type: "address" },
    ],
  },
] as const;

/**
 * - [__View Contract on Ethereum Etherscan__](https://etherscan.io/address/0x777777C338d93e2C7adf08D102d45CA7CC4Ed021)
 * - [__View Contract on Goerli Etherscan__](https://goerli.etherscan.io/address/0x777777C338d93e2C7adf08D102d45CA7CC4Ed021)
 * - [__View Contract on Op Mainnet Optimism Explorer__](https://explorer.optimism.io/address/0x777777C338d93e2C7adf08D102d45CA7CC4Ed021)
 * - [__View Contract on Optimism Goerli Etherscan__](https://goerli-optimism.etherscan.io/address/0x777777C338d93e2C7adf08D102d45CA7CC4Ed021)
 * - [__View Contract on Zora Goerli Testnet Explorer__](https://testnet.explorer.zora.energy/address/0x777777C338d93e2C7adf08D102d45CA7CC4Ed021)
 * - [__View Contract on Base Basescan__](https://basescan.org/address/0x777777C338d93e2C7adf08D102d45CA7CC4Ed021)
 * - [__View Contract on Base Goerli Basescan__](https://goerli.basescan.org/address/0x777777C338d93e2C7adf08D102d45CA7CC4Ed021)
 * - [__View Contract on Zora Explorer__](https://explorer.zora.energy/address/0x777777C338d93e2C7adf08D102d45CA7CC4Ed021)
 * - [__View Contract on Sepolia Etherscan__](https://sepolia.etherscan.io/address/0x13dAA8E9e3f68deDE7b1386ACdc12eA98F2FB688)
 */
export const zoraCreator1155FactoryImplAddress = {
  1: "0x777777C338d93e2C7adf08D102d45CA7CC4Ed021",
  5: "0x777777C338d93e2C7adf08D102d45CA7CC4Ed021",
  10: "0x777777C338d93e2C7adf08D102d45CA7CC4Ed021",
  420: "0x777777C338d93e2C7adf08D102d45CA7CC4Ed021",
  424: "0x6E742921602a5195f6439c8b8b827E85902E1B2D",
  999: "0x777777C338d93e2C7adf08D102d45CA7CC4Ed021",
  8453: "0x777777C338d93e2C7adf08D102d45CA7CC4Ed021",
  58008: "0x6E742921602a5195f6439c8b8b827E85902E1B2D",
  84531: "0x777777C338d93e2C7adf08D102d45CA7CC4Ed021",
  7777777: "0x777777C338d93e2C7adf08D102d45CA7CC4Ed021",
  11155111: "0x13dAA8E9e3f68deDE7b1386ACdc12eA98F2FB688",
} as const;

/**
 * - [__View Contract on Ethereum Etherscan__](https://etherscan.io/address/0x777777C338d93e2C7adf08D102d45CA7CC4Ed021)
 * - [__View Contract on Goerli Etherscan__](https://goerli.etherscan.io/address/0x777777C338d93e2C7adf08D102d45CA7CC4Ed021)
 * - [__View Contract on Op Mainnet Optimism Explorer__](https://explorer.optimism.io/address/0x777777C338d93e2C7adf08D102d45CA7CC4Ed021)
 * - [__View Contract on Optimism Goerli Etherscan__](https://goerli-optimism.etherscan.io/address/0x777777C338d93e2C7adf08D102d45CA7CC4Ed021)
 * - [__View Contract on Zora Goerli Testnet Explorer__](https://testnet.explorer.zora.energy/address/0x777777C338d93e2C7adf08D102d45CA7CC4Ed021)
 * - [__View Contract on Base Basescan__](https://basescan.org/address/0x777777C338d93e2C7adf08D102d45CA7CC4Ed021)
 * - [__View Contract on Base Goerli Basescan__](https://goerli.basescan.org/address/0x777777C338d93e2C7adf08D102d45CA7CC4Ed021)
 * - [__View Contract on Zora Explorer__](https://explorer.zora.energy/address/0x777777C338d93e2C7adf08D102d45CA7CC4Ed021)
 * - [__View Contract on Sepolia Etherscan__](https://sepolia.etherscan.io/address/0x13dAA8E9e3f68deDE7b1386ACdc12eA98F2FB688)
 */
export const zoraCreator1155FactoryImplConfig = {
  address: zoraCreator1155FactoryImplAddress,
  abi: zoraCreator1155FactoryImplABI,
} as const;

//////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
// ZoraCreator1155Impl
//////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

export const zoraCreator1155ImplABI = [
  {
    stateMutability: "nonpayable",
    type: "constructor",
    inputs: [
      { name: "_mintFeeRecipient", internalType: "address", type: "address" },
      { name: "_upgradeGate", internalType: "address", type: "address" },
      { name: "_protocolRewards", internalType: "address", type: "address" },
    ],
  },
  { type: "error", inputs: [], name: "ADDRESS_DELEGATECALL_TO_NON_CONTRACT" },
  { type: "error", inputs: [], name: "ADDRESS_LOW_LEVEL_CALL_FAILED" },
  {
    type: "error",
    inputs: [
      { name: "operator", internalType: "address", type: "address" },
      { name: "user", internalType: "address", type: "address" },
    ],
    name: "Burn_NotOwnerOrApproved",
  },
  { type: "error", inputs: [], name: "CREATOR_FUNDS_RECIPIENT_NOT_SET" },
  {
    type: "error",
    inputs: [{ name: "reason", internalType: "bytes", type: "bytes" }],
    name: "CallFailed",
  },
  { type: "error", inputs: [], name: "Call_TokenIdMismatch" },
  {
    type: "error",
    inputs: [
      { name: "tokenId", internalType: "uint256", type: "uint256" },
      { name: "quantity", internalType: "uint256", type: "uint256" },
      { name: "totalMinted", internalType: "uint256", type: "uint256" },
      { name: "maxSupply", internalType: "uint256", type: "uint256" },
    ],
    name: "CannotMintMoreTokens",
  },
  {
    type: "error",
    inputs: [
      { name: "proposedAddress", internalType: "address", type: "address" },
    ],
    name: "Config_TransferHookNotSupported",
  },
  {
    type: "error",
    inputs: [],
    name: "ERC1155_ACCOUNTS_AND_IDS_LENGTH_MISMATCH",
  },
  {
    type: "error",
    inputs: [],
    name: "ERC1155_ADDRESS_ZERO_IS_NOT_A_VALID_OWNER",
  },
  { type: "error", inputs: [], name: "ERC1155_BURN_AMOUNT_EXCEEDS_BALANCE" },
  { type: "error", inputs: [], name: "ERC1155_BURN_FROM_ZERO_ADDRESS" },
  {
    type: "error",
    inputs: [],
    name: "ERC1155_CALLER_IS_NOT_TOKEN_OWNER_OR_APPROVED",
  },
  {
    type: "error",
    inputs: [],
    name: "ERC1155_ERC1155RECEIVER_REJECTED_TOKENS",
  },
  {
    type: "error",
    inputs: [],
    name: "ERC1155_IDS_AND_AMOUNTS_LENGTH_MISMATCH",
  },
  {
    type: "error",
    inputs: [],
    name: "ERC1155_INSUFFICIENT_BALANCE_FOR_TRANSFER",
  },
  { type: "error", inputs: [], name: "ERC1155_MINT_TO_ZERO_ADDRESS" },
  { type: "error", inputs: [], name: "ERC1155_SETTING_APPROVAL_FOR_SELF" },
  {
    type: "error",
    inputs: [],
    name: "ERC1155_TRANSFER_TO_NON_ERC1155RECEIVER_IMPLEMENTER",
  },
  { type: "error", inputs: [], name: "ERC1155_TRANSFER_TO_ZERO_ADDRESS" },
  { type: "error", inputs: [], name: "ERC1967_NEW_IMPL_NOT_CONTRACT" },
  { type: "error", inputs: [], name: "ERC1967_NEW_IMPL_NOT_UUPS" },
  { type: "error", inputs: [], name: "ERC1967_UNSUPPORTED_PROXIABLEUUID" },
  {
    type: "error",
    inputs: [
      { name: "recipient", internalType: "address", type: "address" },
      { name: "amount", internalType: "uint256", type: "uint256" },
    ],
    name: "ETHWithdrawFailed",
  },
  {
    type: "error",
    inputs: [],
    name: "FUNCTION_MUST_BE_CALLED_THROUGH_ACTIVE_PROXY",
  },
  {
    type: "error",
    inputs: [],
    name: "FUNCTION_MUST_BE_CALLED_THROUGH_DELEGATECALL",
  },
  {
    type: "error",
    inputs: [
      { name: "amount", internalType: "uint256", type: "uint256" },
      { name: "contractValue", internalType: "uint256", type: "uint256" },
    ],
    name: "FundsWithdrawInsolvent",
  },
  {
    type: "error",
    inputs: [],
    name: "INITIALIZABLE_CONTRACT_ALREADY_INITIALIZED",
  },
  {
    type: "error",
    inputs: [],
    name: "INITIALIZABLE_CONTRACT_IS_NOT_INITIALIZING",
  },
  { type: "error", inputs: [], name: "INVALID_ADDRESS_ZERO" },
  { type: "error", inputs: [], name: "INVALID_ETH_AMOUNT" },
  { type: "error", inputs: [], name: "InvalidMintSchedule" },
  { type: "error", inputs: [], name: "MintNotYetStarted" },
  { type: "error", inputs: [], name: "Mint_InsolventSaleTransfer" },
  { type: "error", inputs: [], name: "Mint_TokenIDMintNotAllowed" },
  { type: "error", inputs: [], name: "Mint_UnknownCommand" },
  { type: "error", inputs: [], name: "Mint_ValueTransferFail" },
  { type: "error", inputs: [], name: "NewOwnerNeedsToBeAdmin" },
  {
    type: "error",
    inputs: [{ name: "tokenId", internalType: "uint256", type: "uint256" }],
    name: "NoRendererForToken",
  },
  { type: "error", inputs: [], name: "ONLY_CREATE_REFERRAL" },
  { type: "error", inputs: [], name: "PremintDeleted" },
  {
    type: "error",
    inputs: [
      { name: "caller", internalType: "address", type: "address" },
      { name: "recipient", internalType: "address", type: "address" },
      { name: "amount", internalType: "uint256", type: "uint256" },
    ],
    name: "ProtocolRewardsWithdrawFailed",
  },
  {
    type: "error",
    inputs: [{ name: "renderer", internalType: "address", type: "address" }],
    name: "RendererNotValid",
  },
  { type: "error", inputs: [], name: "Renderer_NotValidRendererContract" },
  {
    type: "error",
    inputs: [
      { name: "targetContract", internalType: "address", type: "address" },
    ],
    name: "Sale_CannotCallNonSalesContract",
  },
  {
    type: "error",
    inputs: [
      { name: "expected", internalType: "uint256", type: "uint256" },
      { name: "actual", internalType: "uint256", type: "uint256" },
    ],
    name: "TokenIdMismatch",
  },
  {
    type: "error",
    inputs: [],
    name: "UUPS_UPGRADEABLE_MUST_NOT_BE_CALLED_THROUGH_DELEGATECALL",
  },
  {
    type: "error",
    inputs: [
      { name: "user", internalType: "address", type: "address" },
      { name: "tokenId", internalType: "uint256", type: "uint256" },
      { name: "role", internalType: "uint256", type: "uint256" },
    ],
    name: "UserMissingRoleForToken",
  },
  {
    type: "event",
    anonymous: false,
    inputs: [
      {
        name: "previousAdmin",
        internalType: "address",
        type: "address",
        indexed: false,
      },
      {
        name: "newAdmin",
        internalType: "address",
        type: "address",
        indexed: false,
      },
    ],
    name: "AdminChanged",
  },
  {
    type: "event",
    anonymous: false,
    inputs: [
      {
        name: "account",
        internalType: "address",
        type: "address",
        indexed: true,
      },
      {
        name: "operator",
        internalType: "address",
        type: "address",
        indexed: true,
      },
      { name: "approved", internalType: "bool", type: "bool", indexed: false },
    ],
    name: "ApprovalForAll",
  },
  {
    type: "event",
    anonymous: false,
    inputs: [
      {
        name: "beacon",
        internalType: "address",
        type: "address",
        indexed: true,
      },
    ],
    name: "BeaconUpgraded",
  },
  {
    type: "event",
    anonymous: false,
    inputs: [
      {
        name: "updater",
        internalType: "address",
        type: "address",
        indexed: true,
      },
      {
        name: "updateType",
        internalType: "enum IZoraCreator1155.ConfigUpdate",
        type: "uint8",
        indexed: true,
      },
      {
        name: "newConfig",
        internalType: "struct IZoraCreator1155TypesV1.ContractConfig",
        type: "tuple",
        components: [
          { name: "owner", internalType: "address", type: "address" },
          { name: "__gap1", internalType: "uint96", type: "uint96" },
          {
            name: "fundsRecipient",
            internalType: "address payable",
            type: "address",
          },
          { name: "__gap2", internalType: "uint96", type: "uint96" },
          {
            name: "transferHook",
            internalType: "contract ITransferHookReceiver",
            type: "address",
          },
          { name: "__gap3", internalType: "uint96", type: "uint96" },
        ],
        indexed: false,
      },
    ],
    name: "ConfigUpdated",
  },
  {
    type: "event",
    anonymous: false,
    inputs: [
      {
        name: "updater",
        internalType: "address",
        type: "address",
        indexed: true,
      },
      { name: "uri", internalType: "string", type: "string", indexed: false },
      { name: "name", internalType: "string", type: "string", indexed: false },
    ],
    name: "ContractMetadataUpdated",
  },
  {
    type: "event",
    anonymous: false,
    inputs: [
      {
        name: "renderer",
        internalType: "contract IRenderer1155",
        type: "address",
        indexed: false,
      },
    ],
    name: "ContractRendererUpdated",
  },
  {
    type: "event",
    anonymous: false,
    inputs: [
      {
        name: "structHash",
        internalType: "bytes32",
        type: "bytes32",
        indexed: false,
      },
      {
        name: "domainName",
        internalType: "string",
        type: "string",
        indexed: false,
      },
      {
        name: "version",
        internalType: "string",
        type: "string",
        indexed: false,
      },
      {
        name: "creator",
        internalType: "address",
        type: "address",
        indexed: false,
      },
      {
        name: "signature",
        internalType: "bytes",
        type: "bytes",
        indexed: false,
      },
    ],
    name: "CreatorAttribution",
  },
  {
    type: "event",
    anonymous: false,
    inputs: [
      { name: "version", internalType: "uint8", type: "uint8", indexed: false },
    ],
    name: "Initialized",
  },
  {
    type: "event",
    anonymous: false,
    inputs: [
      {
        name: "lastOwner",
        internalType: "address",
        type: "address",
        indexed: false,
      },
      {
        name: "newOwner",
        internalType: "address",
        type: "address",
        indexed: false,
      },
    ],
    name: "OwnershipTransferred",
  },
  {
    type: "event",
    anonymous: false,
    inputs: [
      {
        name: "sender",
        internalType: "address",
        type: "address",
        indexed: true,
      },
      {
        name: "minter",
        internalType: "address",
        type: "address",
        indexed: true,
      },
      {
        name: "tokenId",
        internalType: "uint256",
        type: "uint256",
        indexed: true,
      },
      {
        name: "quantity",
        internalType: "uint256",
        type: "uint256",
        indexed: false,
      },
      {
        name: "value",
        internalType: "uint256",
        type: "uint256",
        indexed: false,
      },
    ],
    name: "Purchased",
  },
  {
    type: "event",
    anonymous: false,
    inputs: [
      {
        name: "tokenId",
        internalType: "uint256",
        type: "uint256",
        indexed: true,
      },
      {
        name: "renderer",
        internalType: "address",
        type: "address",
        indexed: true,
      },
      { name: "user", internalType: "address", type: "address", indexed: true },
    ],
    name: "RendererUpdated",
  },
  {
    type: "event",
    anonymous: false,
    inputs: [
      {
        name: "tokenId",
        internalType: "uint256",
        type: "uint256",
        indexed: true,
      },
      {
        name: "sender",
        internalType: "address",
        type: "address",
        indexed: true,
      },
      {
        name: "newURI",
        internalType: "string",
        type: "string",
        indexed: false,
      },
      {
        name: "maxSupply",
        internalType: "uint256",
        type: "uint256",
        indexed: false,
      },
    ],
    name: "SetupNewToken",
  },
  {
    type: "event",
    anonymous: false,
    inputs: [
      {
        name: "operator",
        internalType: "address",
        type: "address",
        indexed: true,
      },
      { name: "from", internalType: "address", type: "address", indexed: true },
      { name: "to", internalType: "address", type: "address", indexed: true },
      {
        name: "ids",
        internalType: "uint256[]",
        type: "uint256[]",
        indexed: false,
      },
      {
        name: "values",
        internalType: "uint256[]",
        type: "uint256[]",
        indexed: false,
      },
    ],
    name: "TransferBatch",
  },
  {
    type: "event",
    anonymous: false,
    inputs: [
      {
        name: "operator",
        internalType: "address",
        type: "address",
        indexed: true,
      },
      { name: "from", internalType: "address", type: "address", indexed: true },
      { name: "to", internalType: "address", type: "address", indexed: true },
      { name: "id", internalType: "uint256", type: "uint256", indexed: false },
      {
        name: "value",
        internalType: "uint256",
        type: "uint256",
        indexed: false,
      },
    ],
    name: "TransferSingle",
  },
  {
    type: "event",
    anonymous: false,
    inputs: [
      { name: "value", internalType: "string", type: "string", indexed: false },
      { name: "id", internalType: "uint256", type: "uint256", indexed: true },
    ],
    name: "URI",
  },
  {
    type: "event",
    anonymous: false,
    inputs: [
      {
        name: "tokenId",
        internalType: "uint256",
        type: "uint256",
        indexed: true,
      },
      { name: "user", internalType: "address", type: "address", indexed: true },
      {
        name: "permissions",
        internalType: "uint256",
        type: "uint256",
        indexed: true,
      },
    ],
    name: "UpdatedPermissions",
  },
  {
    type: "event",
    anonymous: false,
    inputs: [
      {
        name: "tokenId",
        internalType: "uint256",
        type: "uint256",
        indexed: true,
      },
      { name: "user", internalType: "address", type: "address", indexed: true },
      {
        name: "configuration",
        internalType: "struct ICreatorRoyaltiesControl.RoyaltyConfiguration",
        type: "tuple",
        components: [
          {
            name: "royaltyMintSchedule",
            internalType: "uint32",
            type: "uint32",
          },
          { name: "royaltyBPS", internalType: "uint32", type: "uint32" },
          {
            name: "royaltyRecipient",
            internalType: "address",
            type: "address",
          },
        ],
        indexed: false,
      },
    ],
    name: "UpdatedRoyalties",
  },
  {
    type: "event",
    anonymous: false,
    inputs: [
      { name: "from", internalType: "address", type: "address", indexed: true },
      {
        name: "tokenId",
        internalType: "uint256",
        type: "uint256",
        indexed: true,
      },
      {
        name: "tokenData",
        internalType: "struct IZoraCreator1155TypesV1.TokenData",
        type: "tuple",
        components: [
          { name: "uri", internalType: "string", type: "string" },
          { name: "maxSupply", internalType: "uint256", type: "uint256" },
          { name: "totalMinted", internalType: "uint256", type: "uint256" },
        ],
        indexed: false,
      },
    ],
    name: "UpdatedToken",
  },
  {
    type: "event",
    anonymous: false,
    inputs: [
      {
        name: "implementation",
        internalType: "address",
        type: "address",
        indexed: true,
      },
    ],
    name: "Upgraded",
  },
  {
    stateMutability: "view",
    type: "function",
    inputs: [],
    name: "CONTRACT_BASE_ID",
    outputs: [{ name: "", internalType: "uint256", type: "uint256" }],
  },
  {
    stateMutability: "view",
    type: "function",
    inputs: [],
    name: "PERMISSION_BIT_ADMIN",
    outputs: [{ name: "", internalType: "uint256", type: "uint256" }],
  },
  {
    stateMutability: "view",
    type: "function",
    inputs: [],
    name: "PERMISSION_BIT_FUNDS_MANAGER",
    outputs: [{ name: "", internalType: "uint256", type: "uint256" }],
  },
  {
    stateMutability: "view",
    type: "function",
    inputs: [],
    name: "PERMISSION_BIT_METADATA",
    outputs: [{ name: "", internalType: "uint256", type: "uint256" }],
  },
  {
    stateMutability: "view",
    type: "function",
    inputs: [],
    name: "PERMISSION_BIT_MINTER",
    outputs: [{ name: "", internalType: "uint256", type: "uint256" }],
  },
  {
    stateMutability: "view",
    type: "function",
    inputs: [],
    name: "PERMISSION_BIT_SALES",
    outputs: [{ name: "", internalType: "uint256", type: "uint256" }],
  },
  {
    stateMutability: "nonpayable",
    type: "function",
    inputs: [
      { name: "tokenId", internalType: "uint256", type: "uint256" },
      { name: "user", internalType: "address", type: "address" },
      { name: "permissionBits", internalType: "uint256", type: "uint256" },
    ],
    name: "addPermission",
    outputs: [],
  },
  {
    stateMutability: "nonpayable",
    type: "function",
    inputs: [
      { name: "recipient", internalType: "address", type: "address" },
      { name: "tokenId", internalType: "uint256", type: "uint256" },
      { name: "quantity", internalType: "uint256", type: "uint256" },
      { name: "data", internalType: "bytes", type: "bytes" },
    ],
    name: "adminMint",
    outputs: [],
  },
  {
    stateMutability: "nonpayable",
    type: "function",
    inputs: [
      { name: "recipient", internalType: "address", type: "address" },
      { name: "tokenIds", internalType: "uint256[]", type: "uint256[]" },
      { name: "quantities", internalType: "uint256[]", type: "uint256[]" },
      { name: "data", internalType: "bytes", type: "bytes" },
    ],
    name: "adminMintBatch",
    outputs: [],
  },
  {
    stateMutability: "view",
    type: "function",
    inputs: [{ name: "lastTokenId", internalType: "uint256", type: "uint256" }],
    name: "assumeLastTokenIdMatches",
    outputs: [],
  },
  {
    stateMutability: "view",
    type: "function",
    inputs: [
      { name: "account", internalType: "address", type: "address" },
      { name: "id", internalType: "uint256", type: "uint256" },
    ],
    name: "balanceOf",
    outputs: [{ name: "", internalType: "uint256", type: "uint256" }],
  },
  {
    stateMutability: "view",
    type: "function",
    inputs: [
      { name: "accounts", internalType: "address[]", type: "address[]" },
      { name: "ids", internalType: "uint256[]", type: "uint256[]" },
    ],
    name: "balanceOfBatch",
    outputs: [
      { name: "batchBalances", internalType: "uint256[]", type: "uint256[]" },
    ],
  },
  {
    stateMutability: "nonpayable",
    type: "function",
    inputs: [
      { name: "from", internalType: "address", type: "address" },
      { name: "tokenIds", internalType: "uint256[]", type: "uint256[]" },
      { name: "amounts", internalType: "uint256[]", type: "uint256[]" },
    ],
    name: "burnBatch",
    outputs: [],
  },
  {
    stateMutability: "nonpayable",
    type: "function",
    inputs: [
      { name: "tokenId", internalType: "uint256", type: "uint256" },
      { name: "data", internalType: "bytes", type: "bytes" },
    ],
    name: "callRenderer",
    outputs: [],
  },
  {
    stateMutability: "nonpayable",
    type: "function",
    inputs: [
      { name: "tokenId", internalType: "uint256", type: "uint256" },
      {
        name: "salesConfig",
        internalType: "contract IMinter1155",
        type: "address",
      },
      { name: "data", internalType: "bytes", type: "bytes" },
    ],
    name: "callSale",
    outputs: [],
  },
  {
    stateMutability: "pure",
    type: "function",
    inputs: [{ name: "numTokens", internalType: "uint256", type: "uint256" }],
    name: "computeFreeMintRewards",
    outputs: [
      {
        name: "",
        internalType: "struct RewardsSettings",
        type: "tuple",
        components: [
          { name: "creatorReward", internalType: "uint256", type: "uint256" },
          {
            name: "createReferralReward",
            internalType: "uint256",
            type: "uint256",
          },
          {
            name: "mintReferralReward",
            internalType: "uint256",
            type: "uint256",
          },
          {
            name: "firstMinterReward",
            internalType: "uint256",
            type: "uint256",
          },
          { name: "zoraReward", internalType: "uint256", type: "uint256" },
        ],
      },
    ],
  },
  {
    stateMutability: "pure",
    type: "function",
    inputs: [{ name: "numTokens", internalType: "uint256", type: "uint256" }],
    name: "computePaidMintRewards",
    outputs: [
      {
        name: "",
        internalType: "struct RewardsSettings",
        type: "tuple",
        components: [
          { name: "creatorReward", internalType: "uint256", type: "uint256" },
          {
            name: "createReferralReward",
            internalType: "uint256",
            type: "uint256",
          },
          {
            name: "mintReferralReward",
            internalType: "uint256",
            type: "uint256",
          },
          {
            name: "firstMinterReward",
            internalType: "uint256",
            type: "uint256",
          },
          { name: "zoraReward", internalType: "uint256", type: "uint256" },
        ],
      },
    ],
  },
  {
    stateMutability: "pure",
    type: "function",
    inputs: [{ name: "numTokens", internalType: "uint256", type: "uint256" }],
    name: "computeTotalReward",
    outputs: [{ name: "", internalType: "uint256", type: "uint256" }],
  },
  {
    stateMutability: "view",
    type: "function",
    inputs: [],
    name: "config",
    outputs: [
      { name: "owner", internalType: "address", type: "address" },
      { name: "__gap1", internalType: "uint96", type: "uint96" },
      {
        name: "fundsRecipient",
        internalType: "address payable",
        type: "address",
      },
      { name: "__gap2", internalType: "uint96", type: "uint96" },
      {
        name: "transferHook",
        internalType: "contract ITransferHookReceiver",
        type: "address",
      },
      { name: "__gap3", internalType: "uint96", type: "uint96" },
    ],
  },
  {
    stateMutability: "view",
    type: "function",
    inputs: [],
    name: "contractURI",
    outputs: [{ name: "", internalType: "string", type: "string" }],
  },
  {
    stateMutability: "pure",
    type: "function",
    inputs: [],
    name: "contractVersion",
    outputs: [{ name: "", internalType: "string", type: "string" }],
  },
  {
    stateMutability: "view",
    type: "function",
    inputs: [{ name: "", internalType: "uint256", type: "uint256" }],
    name: "createReferrals",
    outputs: [{ name: "", internalType: "address", type: "address" }],
  },
  {
    stateMutability: "view",
    type: "function",
    inputs: [{ name: "", internalType: "uint256", type: "uint256" }],
    name: "customRenderers",
    outputs: [
      { name: "", internalType: "contract IRenderer1155", type: "address" },
    ],
  },
  {
    stateMutability: "nonpayable",
    type: "function",
    inputs: [
      {
        name: "premintConfig",
        internalType: "struct PremintConfig",
        type: "tuple",
        components: [
          {
            name: "tokenConfig",
            internalType: "struct TokenCreationConfig",
            type: "tuple",
            components: [
              { name: "tokenURI", internalType: "string", type: "string" },
              { name: "maxSupply", internalType: "uint256", type: "uint256" },
              {
                name: "maxTokensPerAddress",
                internalType: "uint64",
                type: "uint64",
              },
              { name: "pricePerToken", internalType: "uint96", type: "uint96" },
              { name: "mintStart", internalType: "uint64", type: "uint64" },
              { name: "mintDuration", internalType: "uint64", type: "uint64" },
              {
                name: "royaltyMintSchedule",
                internalType: "uint32",
                type: "uint32",
              },
              { name: "royaltyBPS", internalType: "uint32", type: "uint32" },
              {
                name: "royaltyRecipient",
                internalType: "address",
                type: "address",
              },
              {
                name: "fixedPriceMinter",
                internalType: "address",
                type: "address",
              },
            ],
          },
          { name: "uid", internalType: "uint32", type: "uint32" },
          { name: "version", internalType: "uint32", type: "uint32" },
          { name: "deleted", internalType: "bool", type: "bool" },
        ],
      },
      { name: "signature", internalType: "bytes", type: "bytes" },
      { name: "sender", internalType: "address", type: "address" },
    ],
    name: "delegateSetupNewToken",
    outputs: [{ name: "newTokenId", internalType: "uint256", type: "uint256" }],
  },
  {
    stateMutability: "view",
    type: "function",
    inputs: [{ name: "", internalType: "uint32", type: "uint32" }],
    name: "delegatedTokenId",
    outputs: [{ name: "", internalType: "uint256", type: "uint256" }],
  },
  {
    stateMutability: "view",
    type: "function",
    inputs: [{ name: "", internalType: "uint256", type: "uint256" }],
    name: "firstMinters",
    outputs: [{ name: "", internalType: "address", type: "address" }],
  },
  {
    stateMutability: "view",
    type: "function",
    inputs: [],
    name: "getCreatorRewardRecipient",
    outputs: [{ name: "", internalType: "address payable", type: "address" }],
  },
  {
    stateMutability: "view",
    type: "function",
    inputs: [{ name: "tokenId", internalType: "uint256", type: "uint256" }],
    name: "getCustomRenderer",
    outputs: [
      {
        name: "customRenderer",
        internalType: "contract IRenderer1155",
        type: "address",
      },
    ],
  },
  {
    stateMutability: "view",
    type: "function",
    inputs: [{ name: "tokenId", internalType: "uint256", type: "uint256" }],
    name: "getRoyalties",
    outputs: [
      {
        name: "",
        internalType: "struct ICreatorRoyaltiesControl.RoyaltyConfiguration",
        type: "tuple",
        components: [
          {
            name: "royaltyMintSchedule",
            internalType: "uint32",
            type: "uint32",
          },
          { name: "royaltyBPS", internalType: "uint32", type: "uint32" },
          {
            name: "royaltyRecipient",
            internalType: "address",
            type: "address",
          },
        ],
      },
    ],
  },
  {
    stateMutability: "view",
    type: "function",
    inputs: [{ name: "tokenId", internalType: "uint256", type: "uint256" }],
    name: "getTokenInfo",
    outputs: [
      {
        name: "",
        internalType: "struct IZoraCreator1155TypesV1.TokenData",
        type: "tuple",
        components: [
          { name: "uri", internalType: "string", type: "string" },
          { name: "maxSupply", internalType: "uint256", type: "uint256" },
          { name: "totalMinted", internalType: "uint256", type: "uint256" },
        ],
      },
    ],
  },
  {
    stateMutability: "view",
    type: "function",
    inputs: [],
    name: "implementation",
    outputs: [{ name: "", internalType: "address", type: "address" }],
  },
  {
    stateMutability: "nonpayable",
    type: "function",
    inputs: [
      { name: "contractName", internalType: "string", type: "string" },
      { name: "newContractURI", internalType: "string", type: "string" },
      {
        name: "defaultRoyaltyConfiguration",
        internalType: "struct ICreatorRoyaltiesControl.RoyaltyConfiguration",
        type: "tuple",
        components: [
          {
            name: "royaltyMintSchedule",
            internalType: "uint32",
            type: "uint32",
          },
          { name: "royaltyBPS", internalType: "uint32", type: "uint32" },
          {
            name: "royaltyRecipient",
            internalType: "address",
            type: "address",
          },
        ],
      },
      {
        name: "defaultAdmin",
        internalType: "address payable",
        type: "address",
      },
      { name: "setupActions", internalType: "bytes[]", type: "bytes[]" },
    ],
    name: "initialize",
    outputs: [],
  },
  {
    stateMutability: "view",
    type: "function",
    inputs: [
      { name: "user", internalType: "address", type: "address" },
      { name: "tokenId", internalType: "uint256", type: "uint256" },
      { name: "role", internalType: "uint256", type: "uint256" },
    ],
    name: "isAdminOrRole",
    outputs: [{ name: "", internalType: "bool", type: "bool" }],
  },
  {
    stateMutability: "view",
    type: "function",
    inputs: [
      { name: "account", internalType: "address", type: "address" },
      { name: "operator", internalType: "address", type: "address" },
    ],
    name: "isApprovedForAll",
    outputs: [{ name: "", internalType: "bool", type: "bool" }],
  },
  {
    stateMutability: "view",
    type: "function",
    inputs: [{ name: "", internalType: "uint256", type: "uint256" }],
    name: "metadataRendererContract",
    outputs: [{ name: "", internalType: "address", type: "address" }],
  },
  {
    stateMutability: "payable",
    type: "function",
    inputs: [
      { name: "minter", internalType: "contract IMinter1155", type: "address" },
      { name: "tokenId", internalType: "uint256", type: "uint256" },
      { name: "quantity", internalType: "uint256", type: "uint256" },
      { name: "minterArguments", internalType: "bytes", type: "bytes" },
    ],
    name: "mint",
    outputs: [],
  },
  {
    stateMutability: "pure",
    type: "function",
    inputs: [],
    name: "mintFee",
    outputs: [{ name: "", internalType: "uint256", type: "uint256" }],
  },
  {
    stateMutability: "payable",
    type: "function",
    inputs: [
      { name: "minter", internalType: "contract IMinter1155", type: "address" },
      { name: "tokenId", internalType: "uint256", type: "uint256" },
      { name: "quantity", internalType: "uint256", type: "uint256" },
      { name: "minterArguments", internalType: "bytes", type: "bytes" },
      { name: "mintReferral", internalType: "address", type: "address" },
    ],
    name: "mintWithRewards",
    outputs: [],
  },
  {
    stateMutability: "nonpayable",
    type: "function",
    inputs: [{ name: "data", internalType: "bytes[]", type: "bytes[]" }],
    name: "multicall",
    outputs: [{ name: "results", internalType: "bytes[]", type: "bytes[]" }],
  },
  {
    stateMutability: "view",
    type: "function",
    inputs: [],
    name: "name",
    outputs: [{ name: "", internalType: "string", type: "string" }],
  },
  {
    stateMutability: "view",
    type: "function",
    inputs: [],
    name: "nextTokenId",
    outputs: [{ name: "", internalType: "uint256", type: "uint256" }],
  },
  {
    stateMutability: "view",
    type: "function",
    inputs: [],
    name: "owner",
    outputs: [{ name: "", internalType: "address", type: "address" }],
  },
  {
    stateMutability: "view",
    type: "function",
    inputs: [
      { name: "", internalType: "uint256", type: "uint256" },
      { name: "", internalType: "address", type: "address" },
    ],
    name: "permissions",
    outputs: [{ name: "", internalType: "uint256", type: "uint256" }],
  },
  {
    stateMutability: "view",
    type: "function",
    inputs: [],
    name: "proxiableUUID",
    outputs: [{ name: "", internalType: "bytes32", type: "bytes32" }],
  },
  {
    stateMutability: "nonpayable",
    type: "function",
    inputs: [
      { name: "tokenId", internalType: "uint256", type: "uint256" },
      { name: "user", internalType: "address", type: "address" },
      { name: "permissionBits", internalType: "uint256", type: "uint256" },
    ],
    name: "removePermission",
    outputs: [],
  },
  {
    stateMutability: "view",
    type: "function",
    inputs: [{ name: "", internalType: "uint256", type: "uint256" }],
    name: "royalties",
    outputs: [
      { name: "royaltyMintSchedule", internalType: "uint32", type: "uint32" },
      { name: "royaltyBPS", internalType: "uint32", type: "uint32" },
      { name: "royaltyRecipient", internalType: "address", type: "address" },
    ],
  },
  {
    stateMutability: "view",
    type: "function",
    inputs: [
      { name: "tokenId", internalType: "uint256", type: "uint256" },
      { name: "salePrice", internalType: "uint256", type: "uint256" },
    ],
    name: "royaltyInfo",
    outputs: [
      { name: "receiver", internalType: "address", type: "address" },
      { name: "royaltyAmount", internalType: "uint256", type: "uint256" },
    ],
  },
  {
    stateMutability: "nonpayable",
    type: "function",
    inputs: [
      { name: "from", internalType: "address", type: "address" },
      { name: "to", internalType: "address", type: "address" },
      { name: "ids", internalType: "uint256[]", type: "uint256[]" },
      { name: "amounts", internalType: "uint256[]", type: "uint256[]" },
      { name: "data", internalType: "bytes", type: "bytes" },
    ],
    name: "safeBatchTransferFrom",
    outputs: [],
  },
  {
    stateMutability: "nonpayable",
    type: "function",
    inputs: [
      { name: "from", internalType: "address", type: "address" },
      { name: "to", internalType: "address", type: "address" },
      { name: "id", internalType: "uint256", type: "uint256" },
      { name: "amount", internalType: "uint256", type: "uint256" },
      { name: "data", internalType: "bytes", type: "bytes" },
    ],
    name: "safeTransferFrom",
    outputs: [],
  },
  {
    stateMutability: "nonpayable",
    type: "function",
    inputs: [
      { name: "operator", internalType: "address", type: "address" },
      { name: "approved", internalType: "bool", type: "bool" },
    ],
    name: "setApprovalForAll",
    outputs: [],
  },
  {
    stateMutability: "nonpayable",
    type: "function",
    inputs: [
      {
        name: "fundsRecipient",
        internalType: "address payable",
        type: "address",
      },
    ],
    name: "setFundsRecipient",
    outputs: [],
  },
  {
    stateMutability: "nonpayable",
    type: "function",
    inputs: [{ name: "newOwner", internalType: "address", type: "address" }],
    name: "setOwner",
    outputs: [],
  },
  {
    stateMutability: "nonpayable",
    type: "function",
    inputs: [
      { name: "tokenId", internalType: "uint256", type: "uint256" },
      {
        name: "renderer",
        internalType: "contract IRenderer1155",
        type: "address",
      },
    ],
    name: "setTokenMetadataRenderer",
    outputs: [],
  },
  {
    stateMutability: "nonpayable",
    type: "function",
    inputs: [
      {
        name: "transferHook",
        internalType: "contract ITransferHookReceiver",
        type: "address",
      },
    ],
    name: "setTransferHook",
    outputs: [],
  },
  {
    stateMutability: "nonpayable",
    type: "function",
    inputs: [
      { name: "newURI", internalType: "string", type: "string" },
      { name: "maxSupply", internalType: "uint256", type: "uint256" },
    ],
    name: "setupNewToken",
    outputs: [{ name: "", internalType: "uint256", type: "uint256" }],
  },
  {
    stateMutability: "nonpayable",
    type: "function",
    inputs: [
      { name: "newURI", internalType: "string", type: "string" },
      { name: "maxSupply", internalType: "uint256", type: "uint256" },
      { name: "createReferral", internalType: "address", type: "address" },
    ],
    name: "setupNewTokenWithCreateReferral",
    outputs: [{ name: "", internalType: "uint256", type: "uint256" }],
  },
  {
    stateMutability: "view",
    type: "function",
    inputs: [{ name: "interfaceId", internalType: "bytes4", type: "bytes4" }],
    name: "supportsInterface",
    outputs: [{ name: "", internalType: "bool", type: "bool" }],
  },
  {
    stateMutability: "pure",
    type: "function",
    inputs: [],
    name: "symbol",
    outputs: [{ name: "", internalType: "string", type: "string" }],
  },
  {
    stateMutability: "nonpayable",
    type: "function",
    inputs: [
      { name: "_newURI", internalType: "string", type: "string" },
      { name: "_newName", internalType: "string", type: "string" },
    ],
    name: "updateContractMetadata",
    outputs: [],
  },
  {
    stateMutability: "nonpayable",
    type: "function",
    inputs: [
      { name: "tokenId", internalType: "uint256", type: "uint256" },
      { name: "recipient", internalType: "address", type: "address" },
    ],
    name: "updateCreateReferral",
    outputs: [],
  },
  {
    stateMutability: "nonpayable",
    type: "function",
    inputs: [
      { name: "tokenId", internalType: "uint256", type: "uint256" },
      {
        name: "newConfiguration",
        internalType: "struct ICreatorRoyaltiesControl.RoyaltyConfiguration",
        type: "tuple",
        components: [
          {
            name: "royaltyMintSchedule",
            internalType: "uint32",
            type: "uint32",
          },
          { name: "royaltyBPS", internalType: "uint32", type: "uint32" },
          {
            name: "royaltyRecipient",
            internalType: "address",
            type: "address",
          },
        ],
      },
    ],
    name: "updateRoyaltiesForToken",
    outputs: [],
  },
  {
    stateMutability: "nonpayable",
    type: "function",
    inputs: [
      { name: "tokenId", internalType: "uint256", type: "uint256" },
      { name: "_newURI", internalType: "string", type: "string" },
    ],
    name: "updateTokenURI",
    outputs: [],
  },
  {
    stateMutability: "nonpayable",
    type: "function",
    inputs: [
      { name: "newImplementation", internalType: "address", type: "address" },
    ],
    name: "upgradeTo",
    outputs: [],
  },
  {
    stateMutability: "payable",
    type: "function",
    inputs: [
      { name: "newImplementation", internalType: "address", type: "address" },
      { name: "data", internalType: "bytes", type: "bytes" },
    ],
    name: "upgradeToAndCall",
    outputs: [],
  },
  {
    stateMutability: "view",
    type: "function",
    inputs: [{ name: "tokenId", internalType: "uint256", type: "uint256" }],
    name: "uri",
    outputs: [{ name: "", internalType: "string", type: "string" }],
  },
  {
    stateMutability: "nonpayable",
    type: "function",
    inputs: [],
    name: "withdraw",
    outputs: [],
  },
  {
    stateMutability: "nonpayable",
    type: "function",
    inputs: [
      { name: "to", internalType: "address", type: "address" },
      { name: "amount", internalType: "uint256", type: "uint256" },
    ],
    name: "withdrawRewards",
    outputs: [],
  },
] as const;

//////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
// ZoraCreator1155PremintExecutorImpl
//////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

/**
 * - [__View Contract on Ethereum Etherscan__](https://etherscan.io/address/0x7777773606e7e46C8Ba8B98C08f5cD218e31d340)
 * - [__View Contract on Goerli Etherscan__](https://goerli.etherscan.io/address/0x7777773606e7e46C8Ba8B98C08f5cD218e31d340)
 * - [__View Contract on Op Mainnet Optimism Explorer__](https://explorer.optimism.io/address/0x7777773606e7e46C8Ba8B98C08f5cD218e31d340)
 * - [__View Contract on Optimism Goerli Etherscan__](https://goerli-optimism.etherscan.io/address/0x7777773606e7e46C8Ba8B98C08f5cD218e31d340)
 * - [__View Contract on Zora Goerli Testnet Explorer__](https://testnet.explorer.zora.energy/address/0x7777773606e7e46C8Ba8B98C08f5cD218e31d340)
 * - [__View Contract on Base Basescan__](https://basescan.org/address/0x7777773606e7e46C8Ba8B98C08f5cD218e31d340)
 * - [__View Contract on Base Goerli Basescan__](https://goerli.basescan.org/address/0x7777773606e7e46C8Ba8B98C08f5cD218e31d340)
 * - [__View Contract on Zora Explorer__](https://explorer.zora.energy/address/0x7777773606e7e46C8Ba8B98C08f5cD218e31d340)
 */
export const zoraCreator1155PremintExecutorImplABI = [
  {
    stateMutability: "nonpayable",
    type: "constructor",
    inputs: [
      {
        name: "_factory",
        internalType: "contract IZoraCreator1155Factory",
        type: "address",
      },
    ],
  },
  { type: "error", inputs: [], name: "ADDRESS_DELEGATECALL_TO_NON_CONTRACT" },
  { type: "error", inputs: [], name: "ADDRESS_LOW_LEVEL_CALL_FAILED" },
  {
    type: "error",
    inputs: [
      { name: "operator", internalType: "address", type: "address" },
      { name: "user", internalType: "address", type: "address" },
    ],
    name: "Burn_NotOwnerOrApproved",
  },
  {
    type: "error",
    inputs: [{ name: "reason", internalType: "bytes", type: "bytes" }],
    name: "CallFailed",
  },
  { type: "error", inputs: [], name: "Call_TokenIdMismatch" },
  {
    type: "error",
    inputs: [
      { name: "tokenId", internalType: "uint256", type: "uint256" },
      { name: "quantity", internalType: "uint256", type: "uint256" },
      { name: "totalMinted", internalType: "uint256", type: "uint256" },
      { name: "maxSupply", internalType: "uint256", type: "uint256" },
    ],
    name: "CannotMintMoreTokens",
  },
  {
    type: "error",
    inputs: [
      { name: "proposedAddress", internalType: "address", type: "address" },
    ],
    name: "Config_TransferHookNotSupported",
  },
  { type: "error", inputs: [], name: "ERC1967_NEW_IMPL_NOT_CONTRACT" },
  { type: "error", inputs: [], name: "ERC1967_NEW_IMPL_NOT_UUPS" },
  { type: "error", inputs: [], name: "ERC1967_UNSUPPORTED_PROXIABLEUUID" },
  {
    type: "error",
    inputs: [
      { name: "recipient", internalType: "address", type: "address" },
      { name: "amount", internalType: "uint256", type: "uint256" },
    ],
    name: "ETHWithdrawFailed",
  },
  {
    type: "error",
    inputs: [],
    name: "FUNCTION_MUST_BE_CALLED_THROUGH_ACTIVE_PROXY",
  },
  {
    type: "error",
    inputs: [],
    name: "FUNCTION_MUST_BE_CALLED_THROUGH_DELEGATECALL",
  },
  {
    type: "error",
    inputs: [
      { name: "amount", internalType: "uint256", type: "uint256" },
      { name: "contractValue", internalType: "uint256", type: "uint256" },
    ],
    name: "FundsWithdrawInsolvent",
  },
  {
    type: "error",
    inputs: [],
    name: "INITIALIZABLE_CONTRACT_ALREADY_INITIALIZED",
  },
  {
    type: "error",
    inputs: [],
    name: "INITIALIZABLE_CONTRACT_IS_NOT_INITIALIZING",
  },
  { type: "error", inputs: [], name: "MintNotYetStarted" },
  { type: "error", inputs: [], name: "Mint_InsolventSaleTransfer" },
  { type: "error", inputs: [], name: "Mint_TokenIDMintNotAllowed" },
  { type: "error", inputs: [], name: "Mint_UnknownCommand" },
  { type: "error", inputs: [], name: "Mint_ValueTransferFail" },
  { type: "error", inputs: [], name: "NewOwnerNeedsToBeAdmin" },
  { type: "error", inputs: [], name: "ONLY_OWNER" },
  { type: "error", inputs: [], name: "ONLY_PENDING_OWNER" },
  { type: "error", inputs: [], name: "OWNER_CANNOT_BE_ZERO_ADDRESS" },
  { type: "error", inputs: [], name: "PremintDeleted" },
  {
    type: "error",
    inputs: [
      { name: "caller", internalType: "address", type: "address" },
      { name: "recipient", internalType: "address", type: "address" },
      { name: "amount", internalType: "uint256", type: "uint256" },
    ],
    name: "ProtocolRewardsWithdrawFailed",
  },
  { type: "error", inputs: [], name: "Renderer_NotValidRendererContract" },
  {
    type: "error",
    inputs: [
      { name: "targetContract", internalType: "address", type: "address" },
    ],
    name: "Sale_CannotCallNonSalesContract",
  },
  {
    type: "error",
    inputs: [
      { name: "expected", internalType: "uint256", type: "uint256" },
      { name: "actual", internalType: "uint256", type: "uint256" },
    ],
    name: "TokenIdMismatch",
  },
  {
    type: "error",
    inputs: [],
    name: "UUPS_UPGRADEABLE_MUST_NOT_BE_CALLED_THROUGH_DELEGATECALL",
  },
  {
    type: "error",
    inputs: [
      { name: "expected", internalType: "string", type: "string" },
      { name: "actual", internalType: "string", type: "string" },
    ],
    name: "UpgradeToMismatchedContractName",
  },
  {
    type: "error",
    inputs: [
      { name: "user", internalType: "address", type: "address" },
      { name: "tokenId", internalType: "uint256", type: "uint256" },
      { name: "role", internalType: "uint256", type: "uint256" },
    ],
    name: "UserMissingRoleForToken",
  },
  {
    type: "event",
    anonymous: false,
    inputs: [
      {
        name: "previousAdmin",
        internalType: "address",
        type: "address",
        indexed: false,
      },
      {
        name: "newAdmin",
        internalType: "address",
        type: "address",
        indexed: false,
      },
    ],
    name: "AdminChanged",
  },
  {
    type: "event",
    anonymous: false,
    inputs: [
      {
        name: "beacon",
        internalType: "address",
        type: "address",
        indexed: true,
      },
    ],
    name: "BeaconUpgraded",
  },
  {
    type: "event",
    anonymous: false,
    inputs: [
      { name: "version", internalType: "uint8", type: "uint8", indexed: false },
    ],
    name: "Initialized",
  },
  {
    type: "event",
    anonymous: false,
    inputs: [
      {
        name: "owner",
        internalType: "address",
        type: "address",
        indexed: true,
      },
      {
        name: "canceledOwner",
        internalType: "address",
        type: "address",
        indexed: true,
      },
    ],
    name: "OwnerCanceled",
  },
  {
    type: "event",
    anonymous: false,
    inputs: [
      {
        name: "owner",
        internalType: "address",
        type: "address",
        indexed: true,
      },
      {
        name: "pendingOwner",
        internalType: "address",
        type: "address",
        indexed: true,
      },
    ],
    name: "OwnerPending",
  },
  {
    type: "event",
    anonymous: false,
    inputs: [
      {
        name: "prevOwner",
        internalType: "address",
        type: "address",
        indexed: true,
      },
      {
        name: "newOwner",
        internalType: "address",
        type: "address",
        indexed: true,
      },
    ],
    name: "OwnerUpdated",
  },
  {
    type: "event",
    anonymous: false,
    inputs: [
      {
        name: "contractAddress",
        internalType: "address",
        type: "address",
        indexed: true,
      },
      {
        name: "tokenId",
        internalType: "uint256",
        type: "uint256",
        indexed: true,
      },
      {
        name: "createdNewContract",
        internalType: "bool",
        type: "bool",
        indexed: true,
      },
      { name: "uid", internalType: "uint32", type: "uint32", indexed: false },
      {
        name: "contractConfig",
        internalType: "struct ContractCreationConfig",
        type: "tuple",
        components: [
          { name: "contractAdmin", internalType: "address", type: "address" },
          { name: "contractURI", internalType: "string", type: "string" },
          { name: "contractName", internalType: "string", type: "string" },
        ],
        indexed: false,
      },
      {
        name: "tokenConfig",
        internalType: "struct TokenCreationConfig",
        type: "tuple",
        components: [
          { name: "tokenURI", internalType: "string", type: "string" },
          { name: "maxSupply", internalType: "uint256", type: "uint256" },
          {
            name: "maxTokensPerAddress",
            internalType: "uint64",
            type: "uint64",
          },
          { name: "pricePerToken", internalType: "uint96", type: "uint96" },
          { name: "mintStart", internalType: "uint64", type: "uint64" },
          { name: "mintDuration", internalType: "uint64", type: "uint64" },
          {
            name: "royaltyMintSchedule",
            internalType: "uint32",
            type: "uint32",
          },
          { name: "royaltyBPS", internalType: "uint32", type: "uint32" },
          {
            name: "royaltyRecipient",
            internalType: "address",
            type: "address",
          },
          {
            name: "fixedPriceMinter",
            internalType: "address",
            type: "address",
          },
        ],
        indexed: false,
      },
      {
        name: "minter",
        internalType: "address",
        type: "address",
        indexed: false,
      },
      {
        name: "quantityMinted",
        internalType: "uint256",
        type: "uint256",
        indexed: false,
      },
    ],
    name: "Preminted",
  },
  {
    type: "event",
    anonymous: false,
    inputs: [
      {
        name: "implementation",
        internalType: "address",
        type: "address",
        indexed: true,
      },
    ],
    name: "Upgraded",
  },
  {
    stateMutability: "nonpayable",
    type: "function",
    inputs: [],
    name: "acceptOwnership",
    outputs: [],
  },
  {
    stateMutability: "nonpayable",
    type: "function",
    inputs: [],
    name: "cancelOwnershipTransfer",
    outputs: [],
  },
  {
    stateMutability: "pure",
    type: "function",
    inputs: [],
    name: "contractName",
    outputs: [{ name: "", internalType: "string", type: "string" }],
  },
  {
    stateMutability: "view",
    type: "function",
    inputs: [
      {
        name: "contractConfig",
        internalType: "struct ContractCreationConfig",
        type: "tuple",
        components: [
          { name: "contractAdmin", internalType: "address", type: "address" },
          { name: "contractURI", internalType: "string", type: "string" },
          { name: "contractName", internalType: "string", type: "string" },
        ],
      },
    ],
    name: "getContractAddress",
    outputs: [{ name: "", internalType: "address", type: "address" }],
  },
  {
    stateMutability: "nonpayable",
    type: "function",
    inputs: [
      { name: "_initialOwner", internalType: "address", type: "address" },
    ],
    name: "initialize",
    outputs: [],
  },
  {
    stateMutability: "view",
    type: "function",
    inputs: [
      {
        name: "contractConfig",
        internalType: "struct ContractCreationConfig",
        type: "tuple",
        components: [
          { name: "contractAdmin", internalType: "address", type: "address" },
          { name: "contractURI", internalType: "string", type: "string" },
          { name: "contractName", internalType: "string", type: "string" },
        ],
      },
      {
        name: "premintConfig",
        internalType: "struct PremintConfig",
        type: "tuple",
        components: [
          {
            name: "tokenConfig",
            internalType: "struct TokenCreationConfig",
            type: "tuple",
            components: [
              { name: "tokenURI", internalType: "string", type: "string" },
              { name: "maxSupply", internalType: "uint256", type: "uint256" },
              {
                name: "maxTokensPerAddress",
                internalType: "uint64",
                type: "uint64",
              },
              { name: "pricePerToken", internalType: "uint96", type: "uint96" },
              { name: "mintStart", internalType: "uint64", type: "uint64" },
              { name: "mintDuration", internalType: "uint64", type: "uint64" },
              {
                name: "royaltyMintSchedule",
                internalType: "uint32",
                type: "uint32",
              },
              { name: "royaltyBPS", internalType: "uint32", type: "uint32" },
              {
                name: "royaltyRecipient",
                internalType: "address",
                type: "address",
              },
              {
                name: "fixedPriceMinter",
                internalType: "address",
                type: "address",
              },
            ],
          },
          { name: "uid", internalType: "uint32", type: "uint32" },
          { name: "version", internalType: "uint32", type: "uint32" },
          { name: "deleted", internalType: "bool", type: "bool" },
        ],
      },
      { name: "signature", internalType: "bytes", type: "bytes" },
    ],
    name: "isValidSignature",
    outputs: [
      { name: "isValid", internalType: "bool", type: "bool" },
      { name: "contractAddress", internalType: "address", type: "address" },
      { name: "recoveredSigner", internalType: "address", type: "address" },
    ],
  },
  {
    stateMutability: "view",
    type: "function",
    inputs: [],
    name: "owner",
    outputs: [{ name: "", internalType: "address", type: "address" }],
  },
  {
    stateMutability: "view",
    type: "function",
    inputs: [],
    name: "pendingOwner",
    outputs: [{ name: "", internalType: "address", type: "address" }],
  },
  {
    stateMutability: "payable",
    type: "function",
    inputs: [
      {
        name: "contractConfig",
        internalType: "struct ContractCreationConfig",
        type: "tuple",
        components: [
          { name: "contractAdmin", internalType: "address", type: "address" },
          { name: "contractURI", internalType: "string", type: "string" },
          { name: "contractName", internalType: "string", type: "string" },
        ],
      },
      {
        name: "premintConfig",
        internalType: "struct PremintConfig",
        type: "tuple",
        components: [
          {
            name: "tokenConfig",
            internalType: "struct TokenCreationConfig",
            type: "tuple",
            components: [
              { name: "tokenURI", internalType: "string", type: "string" },
              { name: "maxSupply", internalType: "uint256", type: "uint256" },
              {
                name: "maxTokensPerAddress",
                internalType: "uint64",
                type: "uint64",
              },
              { name: "pricePerToken", internalType: "uint96", type: "uint96" },
              { name: "mintStart", internalType: "uint64", type: "uint64" },
              { name: "mintDuration", internalType: "uint64", type: "uint64" },
              {
                name: "royaltyMintSchedule",
                internalType: "uint32",
                type: "uint32",
              },
              { name: "royaltyBPS", internalType: "uint32", type: "uint32" },
              {
                name: "royaltyRecipient",
                internalType: "address",
                type: "address",
              },
              {
                name: "fixedPriceMinter",
                internalType: "address",
                type: "address",
              },
            ],
          },
          { name: "uid", internalType: "uint32", type: "uint32" },
          { name: "version", internalType: "uint32", type: "uint32" },
          { name: "deleted", internalType: "bool", type: "bool" },
        ],
      },
      { name: "signature", internalType: "bytes", type: "bytes" },
      { name: "quantityToMint", internalType: "uint256", type: "uint256" },
      { name: "mintComment", internalType: "string", type: "string" },
    ],
    name: "premint",
    outputs: [{ name: "newTokenId", internalType: "uint256", type: "uint256" }],
  },
  {
    stateMutability: "view",
    type: "function",
    inputs: [
      { name: "contractAddress", internalType: "address", type: "address" },
      { name: "uid", internalType: "uint32", type: "uint32" },
    ],
    name: "premintStatus",
    outputs: [
      { name: "contractCreated", internalType: "bool", type: "bool" },
      { name: "tokenIdForPremint", internalType: "uint256", type: "uint256" },
    ],
  },
  {
    stateMutability: "view",
    type: "function",
    inputs: [],
    name: "proxiableUUID",
    outputs: [{ name: "", internalType: "bytes32", type: "bytes32" }],
  },
  {
    stateMutability: "view",
    type: "function",
    inputs: [
      {
        name: "premintConfig",
        internalType: "struct PremintConfig",
        type: "tuple",
        components: [
          {
            name: "tokenConfig",
            internalType: "struct TokenCreationConfig",
            type: "tuple",
            components: [
              { name: "tokenURI", internalType: "string", type: "string" },
              { name: "maxSupply", internalType: "uint256", type: "uint256" },
              {
                name: "maxTokensPerAddress",
                internalType: "uint64",
                type: "uint64",
              },
              { name: "pricePerToken", internalType: "uint96", type: "uint96" },
              { name: "mintStart", internalType: "uint64", type: "uint64" },
              { name: "mintDuration", internalType: "uint64", type: "uint64" },
              {
                name: "royaltyMintSchedule",
                internalType: "uint32",
                type: "uint32",
              },
              { name: "royaltyBPS", internalType: "uint32", type: "uint32" },
              {
                name: "royaltyRecipient",
                internalType: "address",
                type: "address",
              },
              {
                name: "fixedPriceMinter",
                internalType: "address",
                type: "address",
              },
            ],
          },
          { name: "uid", internalType: "uint32", type: "uint32" },
          { name: "version", internalType: "uint32", type: "uint32" },
          { name: "deleted", internalType: "bool", type: "bool" },
        ],
      },
      { name: "zor1155Address", internalType: "address", type: "address" },
      { name: "signature", internalType: "bytes", type: "bytes" },
    ],
    name: "recoverSigner",
    outputs: [{ name: "", internalType: "address", type: "address" }],
  },
  {
    stateMutability: "nonpayable",
    type: "function",
    inputs: [],
    name: "resignOwnership",
    outputs: [],
  },
  {
    stateMutability: "nonpayable",
    type: "function",
    inputs: [{ name: "_newOwner", internalType: "address", type: "address" }],
    name: "safeTransferOwnership",
    outputs: [],
  },
  {
    stateMutability: "nonpayable",
    type: "function",
    inputs: [{ name: "_newOwner", internalType: "address", type: "address" }],
    name: "transferOwnership",
    outputs: [],
  },
  {
    stateMutability: "nonpayable",
    type: "function",
    inputs: [
      { name: "newImplementation", internalType: "address", type: "address" },
    ],
    name: "upgradeTo",
    outputs: [],
  },
  {
    stateMutability: "payable",
    type: "function",
    inputs: [
      { name: "newImplementation", internalType: "address", type: "address" },
      { name: "data", internalType: "bytes", type: "bytes" },
    ],
    name: "upgradeToAndCall",
    outputs: [],
  },
  {
    stateMutability: "view",
    type: "function",
    inputs: [],
    name: "zora1155Factory",
    outputs: [
      {
        name: "",
        internalType: "contract IZoraCreator1155Factory",
        type: "address",
      },
    ],
  },
] as const;

/**
 * - [__View Contract on Ethereum Etherscan__](https://etherscan.io/address/0x7777773606e7e46C8Ba8B98C08f5cD218e31d340)
 * - [__View Contract on Goerli Etherscan__](https://goerli.etherscan.io/address/0x7777773606e7e46C8Ba8B98C08f5cD218e31d340)
 * - [__View Contract on Op Mainnet Optimism Explorer__](https://explorer.optimism.io/address/0x7777773606e7e46C8Ba8B98C08f5cD218e31d340)
 * - [__View Contract on Optimism Goerli Etherscan__](https://goerli-optimism.etherscan.io/address/0x7777773606e7e46C8Ba8B98C08f5cD218e31d340)
 * - [__View Contract on Zora Goerli Testnet Explorer__](https://testnet.explorer.zora.energy/address/0x7777773606e7e46C8Ba8B98C08f5cD218e31d340)
 * - [__View Contract on Base Basescan__](https://basescan.org/address/0x7777773606e7e46C8Ba8B98C08f5cD218e31d340)
 * - [__View Contract on Base Goerli Basescan__](https://goerli.basescan.org/address/0x7777773606e7e46C8Ba8B98C08f5cD218e31d340)
 * - [__View Contract on Zora Explorer__](https://explorer.zora.energy/address/0x7777773606e7e46C8Ba8B98C08f5cD218e31d340)
 */
export const zoraCreator1155PremintExecutorImplAddress = {
  1: "0x7777773606e7e46C8Ba8B98C08f5cD218e31d340",
  5: "0x7777773606e7e46C8Ba8B98C08f5cD218e31d340",
  10: "0x7777773606e7e46C8Ba8B98C08f5cD218e31d340",
  420: "0x7777773606e7e46C8Ba8B98C08f5cD218e31d340",
  999: "0x7777773606e7e46C8Ba8B98C08f5cD218e31d340",
  8453: "0x7777773606e7e46C8Ba8B98C08f5cD218e31d340",
  84531: "0x7777773606e7e46C8Ba8B98C08f5cD218e31d340",
  7777777: "0x7777773606e7e46C8Ba8B98C08f5cD218e31d340",
} as const;

/**
 * - [__View Contract on Ethereum Etherscan__](https://etherscan.io/address/0x7777773606e7e46C8Ba8B98C08f5cD218e31d340)
 * - [__View Contract on Goerli Etherscan__](https://goerli.etherscan.io/address/0x7777773606e7e46C8Ba8B98C08f5cD218e31d340)
 * - [__View Contract on Op Mainnet Optimism Explorer__](https://explorer.optimism.io/address/0x7777773606e7e46C8Ba8B98C08f5cD218e31d340)
 * - [__View Contract on Optimism Goerli Etherscan__](https://goerli-optimism.etherscan.io/address/0x7777773606e7e46C8Ba8B98C08f5cD218e31d340)
 * - [__View Contract on Zora Goerli Testnet Explorer__](https://testnet.explorer.zora.energy/address/0x7777773606e7e46C8Ba8B98C08f5cD218e31d340)
 * - [__View Contract on Base Basescan__](https://basescan.org/address/0x7777773606e7e46C8Ba8B98C08f5cD218e31d340)
 * - [__View Contract on Base Goerli Basescan__](https://goerli.basescan.org/address/0x7777773606e7e46C8Ba8B98C08f5cD218e31d340)
 * - [__View Contract on Zora Explorer__](https://explorer.zora.energy/address/0x7777773606e7e46C8Ba8B98C08f5cD218e31d340)
 */
export const zoraCreator1155PremintExecutorImplConfig = {
  address: zoraCreator1155PremintExecutorImplAddress,
  abi: zoraCreator1155PremintExecutorImplABI,
} as const;

//////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
// ZoraCreatorFixedPriceSaleStrategy
//////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

/**
 * - [__View Contract on Ethereum Etherscan__](https://etherscan.io/address/0x04E2516A2c207E84a1839755675dfd8eF6302F0a)
 * - [__View Contract on Goerli Etherscan__](https://goerli.etherscan.io/address/0x04E2516A2c207E84a1839755675dfd8eF6302F0a)
 * - [__View Contract on Op Mainnet Optimism Explorer__](https://explorer.optimism.io/address/0x3678862f04290E565cCA2EF163BAeb92Bb76790C)
 * - [__View Contract on Optimism Goerli Etherscan__](https://goerli-optimism.etherscan.io/address/0x04E2516A2c207E84a1839755675dfd8eF6302F0a)
 * - [__View Contract on Zora Goerli Testnet Explorer__](https://testnet.explorer.zora.energy/address/0x04E2516A2c207E84a1839755675dfd8eF6302F0a)
 * - [__View Contract on Base Basescan__](https://basescan.org/address/0x04E2516A2c207E84a1839755675dfd8eF6302F0a)
 * - [__View Contract on Base Goerli Basescan__](https://goerli.basescan.org/address/0x04E2516A2c207E84a1839755675dfd8eF6302F0a)
 * - [__View Contract on Zora Explorer__](https://explorer.zora.energy/address/0x04E2516A2c207E84a1839755675dfd8eF6302F0a)
 * - [__View Contract on Sepolia Etherscan__](https://sepolia.etherscan.io/address/0xA5E8d0d4FCed34E86AF6d4E16131C7210Ba8b4b7)
 */
export const zoraCreatorFixedPriceSaleStrategyABI = [
  { type: "error", inputs: [], name: "SaleEnded" },
  { type: "error", inputs: [], name: "SaleHasNotStarted" },
  {
    type: "error",
    inputs: [
      { name: "user", internalType: "address", type: "address" },
      { name: "limit", internalType: "uint256", type: "uint256" },
      { name: "requestedAmount", internalType: "uint256", type: "uint256" },
    ],
    name: "UserExceedsMintLimit",
  },
  { type: "error", inputs: [], name: "WrongValueSent" },
  {
    type: "event",
    anonymous: false,
    inputs: [
      {
        name: "sender",
        internalType: "address",
        type: "address",
        indexed: true,
      },
      {
        name: "tokenContract",
        internalType: "address",
        type: "address",
        indexed: true,
      },
      {
        name: "tokenId",
        internalType: "uint256",
        type: "uint256",
        indexed: true,
      },
      {
        name: "quantity",
        internalType: "uint256",
        type: "uint256",
        indexed: false,
      },
      {
        name: "comment",
        internalType: "string",
        type: "string",
        indexed: false,
      },
    ],
    name: "MintComment",
  },
  {
    type: "event",
    anonymous: false,
    inputs: [
      {
        name: "mediaContract",
        internalType: "address",
        type: "address",
        indexed: true,
      },
      {
        name: "tokenId",
        internalType: "uint256",
        type: "uint256",
        indexed: true,
      },
      {
        name: "salesConfig",
        internalType: "struct ZoraCreatorFixedPriceSaleStrategy.SalesConfig",
        type: "tuple",
        components: [
          { name: "saleStart", internalType: "uint64", type: "uint64" },
          { name: "saleEnd", internalType: "uint64", type: "uint64" },
          {
            name: "maxTokensPerAddress",
            internalType: "uint64",
            type: "uint64",
          },
          { name: "pricePerToken", internalType: "uint96", type: "uint96" },
          { name: "fundsRecipient", internalType: "address", type: "address" },
        ],
        indexed: false,
      },
    ],
    name: "SaleSet",
  },
  {
    stateMutability: "pure",
    type: "function",
    inputs: [],
    name: "contractName",
    outputs: [{ name: "", internalType: "string", type: "string" }],
  },
  {
    stateMutability: "pure",
    type: "function",
    inputs: [],
    name: "contractURI",
    outputs: [{ name: "", internalType: "string", type: "string" }],
  },
  {
    stateMutability: "pure",
    type: "function",
    inputs: [],
    name: "contractVersion",
    outputs: [{ name: "", internalType: "string", type: "string" }],
  },
  {
    stateMutability: "view",
    type: "function",
    inputs: [
      { name: "tokenContract", internalType: "address", type: "address" },
      { name: "tokenId", internalType: "uint256", type: "uint256" },
      { name: "wallet", internalType: "address", type: "address" },
    ],
    name: "getMintedPerWallet",
    outputs: [{ name: "", internalType: "uint256", type: "uint256" }],
  },
  {
    stateMutability: "nonpayable",
    type: "function",
    inputs: [
      { name: "", internalType: "address", type: "address" },
      { name: "tokenId", internalType: "uint256", type: "uint256" },
      { name: "quantity", internalType: "uint256", type: "uint256" },
      { name: "ethValueSent", internalType: "uint256", type: "uint256" },
      { name: "minterArguments", internalType: "bytes", type: "bytes" },
    ],
    name: "requestMint",
    outputs: [
      {
        name: "commands",
        internalType: "struct ICreatorCommands.CommandSet",
        type: "tuple",
        components: [
          {
            name: "commands",
            internalType: "struct ICreatorCommands.Command[]",
            type: "tuple[]",
            components: [
              {
                name: "method",
                internalType: "enum ICreatorCommands.CreatorActions",
                type: "uint8",
              },
              { name: "args", internalType: "bytes", type: "bytes" },
            ],
          },
          { name: "at", internalType: "uint256", type: "uint256" },
        ],
      },
    ],
  },
  {
    stateMutability: "nonpayable",
    type: "function",
    inputs: [{ name: "tokenId", internalType: "uint256", type: "uint256" }],
    name: "resetSale",
    outputs: [],
  },
  {
    stateMutability: "view",
    type: "function",
    inputs: [
      { name: "tokenContract", internalType: "address", type: "address" },
      { name: "tokenId", internalType: "uint256", type: "uint256" },
    ],
    name: "sale",
    outputs: [
      {
        name: "",
        internalType: "struct ZoraCreatorFixedPriceSaleStrategy.SalesConfig",
        type: "tuple",
        components: [
          { name: "saleStart", internalType: "uint64", type: "uint64" },
          { name: "saleEnd", internalType: "uint64", type: "uint64" },
          {
            name: "maxTokensPerAddress",
            internalType: "uint64",
            type: "uint64",
          },
          { name: "pricePerToken", internalType: "uint96", type: "uint96" },
          { name: "fundsRecipient", internalType: "address", type: "address" },
        ],
      },
    ],
  },
  {
    stateMutability: "nonpayable",
    type: "function",
    inputs: [
      { name: "tokenId", internalType: "uint256", type: "uint256" },
      {
        name: "salesConfig",
        internalType: "struct ZoraCreatorFixedPriceSaleStrategy.SalesConfig",
        type: "tuple",
        components: [
          { name: "saleStart", internalType: "uint64", type: "uint64" },
          { name: "saleEnd", internalType: "uint64", type: "uint64" },
          {
            name: "maxTokensPerAddress",
            internalType: "uint64",
            type: "uint64",
          },
          { name: "pricePerToken", internalType: "uint96", type: "uint96" },
          { name: "fundsRecipient", internalType: "address", type: "address" },
        ],
      },
    ],
    name: "setSale",
    outputs: [],
  },
  {
    stateMutability: "pure",
    type: "function",
    inputs: [{ name: "interfaceId", internalType: "bytes4", type: "bytes4" }],
    name: "supportsInterface",
    outputs: [{ name: "", internalType: "bool", type: "bool" }],
  },
] as const;

/**
 * - [__View Contract on Ethereum Etherscan__](https://etherscan.io/address/0x04E2516A2c207E84a1839755675dfd8eF6302F0a)
 * - [__View Contract on Goerli Etherscan__](https://goerli.etherscan.io/address/0x04E2516A2c207E84a1839755675dfd8eF6302F0a)
 * - [__View Contract on Op Mainnet Optimism Explorer__](https://explorer.optimism.io/address/0x3678862f04290E565cCA2EF163BAeb92Bb76790C)
 * - [__View Contract on Optimism Goerli Etherscan__](https://goerli-optimism.etherscan.io/address/0x04E2516A2c207E84a1839755675dfd8eF6302F0a)
 * - [__View Contract on Zora Goerli Testnet Explorer__](https://testnet.explorer.zora.energy/address/0x04E2516A2c207E84a1839755675dfd8eF6302F0a)
 * - [__View Contract on Base Basescan__](https://basescan.org/address/0x04E2516A2c207E84a1839755675dfd8eF6302F0a)
 * - [__View Contract on Base Goerli Basescan__](https://goerli.basescan.org/address/0x04E2516A2c207E84a1839755675dfd8eF6302F0a)
 * - [__View Contract on Zora Explorer__](https://explorer.zora.energy/address/0x04E2516A2c207E84a1839755675dfd8eF6302F0a)
 * - [__View Contract on Sepolia Etherscan__](https://sepolia.etherscan.io/address/0xA5E8d0d4FCed34E86AF6d4E16131C7210Ba8b4b7)
 */
export const zoraCreatorFixedPriceSaleStrategyAddress = {
  1: "0x04E2516A2c207E84a1839755675dfd8eF6302F0a",
  5: "0x04E2516A2c207E84a1839755675dfd8eF6302F0a",
  10: "0x3678862f04290E565cCA2EF163BAeb92Bb76790C",
  420: "0x04E2516A2c207E84a1839755675dfd8eF6302F0a",
  424: "0xc288fe9B145fC31D9aFBa771d0FeB986F6eb49e3",
  999: "0x04E2516A2c207E84a1839755675dfd8eF6302F0a",
  8453: "0x04E2516A2c207E84a1839755675dfd8eF6302F0a",
  58008: "0xc288fe9B145fC31D9aFBa771d0FeB986F6eb49e3",
  84531: "0x04E2516A2c207E84a1839755675dfd8eF6302F0a",
  7777777: "0x04E2516A2c207E84a1839755675dfd8eF6302F0a",
  11155111: "0xA5E8d0d4FCed34E86AF6d4E16131C7210Ba8b4b7",
} as const;

/**
 * - [__View Contract on Ethereum Etherscan__](https://etherscan.io/address/0x04E2516A2c207E84a1839755675dfd8eF6302F0a)
 * - [__View Contract on Goerli Etherscan__](https://goerli.etherscan.io/address/0x04E2516A2c207E84a1839755675dfd8eF6302F0a)
 * - [__View Contract on Op Mainnet Optimism Explorer__](https://explorer.optimism.io/address/0x3678862f04290E565cCA2EF163BAeb92Bb76790C)
 * - [__View Contract on Optimism Goerli Etherscan__](https://goerli-optimism.etherscan.io/address/0x04E2516A2c207E84a1839755675dfd8eF6302F0a)
 * - [__View Contract on Zora Goerli Testnet Explorer__](https://testnet.explorer.zora.energy/address/0x04E2516A2c207E84a1839755675dfd8eF6302F0a)
 * - [__View Contract on Base Basescan__](https://basescan.org/address/0x04E2516A2c207E84a1839755675dfd8eF6302F0a)
 * - [__View Contract on Base Goerli Basescan__](https://goerli.basescan.org/address/0x04E2516A2c207E84a1839755675dfd8eF6302F0a)
 * - [__View Contract on Zora Explorer__](https://explorer.zora.energy/address/0x04E2516A2c207E84a1839755675dfd8eF6302F0a)
 * - [__View Contract on Sepolia Etherscan__](https://sepolia.etherscan.io/address/0xA5E8d0d4FCed34E86AF6d4E16131C7210Ba8b4b7)
 */
export const zoraCreatorFixedPriceSaleStrategyConfig = {
  address: zoraCreatorFixedPriceSaleStrategyAddress,
  abi: zoraCreatorFixedPriceSaleStrategyABI,
} as const;

//////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
// ZoraCreatorMerkleMinterStrategy
//////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

/**
 * - [__View Contract on Ethereum Etherscan__](https://etherscan.io/address/0xf48172CA3B6068B20eE4917Eb27b5472f1f272C7)
 * - [__View Contract on Goerli Etherscan__](https://goerli.etherscan.io/address/0xf48172CA3B6068B20eE4917Eb27b5472f1f272C7)
 * - [__View Contract on Op Mainnet Optimism Explorer__](https://explorer.optimism.io/address/0x899ce31dF6C6Af81203AcAaD285bF539234eF4b8)
 * - [__View Contract on Optimism Goerli Etherscan__](https://goerli-optimism.etherscan.io/address/0xf48172CA3B6068B20eE4917Eb27b5472f1f272C7)
 * - [__View Contract on Zora Goerli Testnet Explorer__](https://testnet.explorer.zora.energy/address/0xf48172CA3B6068B20eE4917Eb27b5472f1f272C7)
 * - [__View Contract on Base Basescan__](https://basescan.org/address/0xf48172CA3B6068B20eE4917Eb27b5472f1f272C7)
 * - [__View Contract on Base Goerli Basescan__](https://goerli.basescan.org/address/0xf48172CA3B6068B20eE4917Eb27b5472f1f272C7)
 * - [__View Contract on Zora Explorer__](https://explorer.zora.energy/address/0xf48172CA3B6068B20eE4917Eb27b5472f1f272C7)
 * - [__View Contract on Sepolia Etherscan__](https://sepolia.etherscan.io/address/0x357D8108A77762B41Ea0C4D69fBb1eF4391251eC)
 */
export const zoraCreatorMerkleMinterStrategyABI = [
  {
    type: "error",
    inputs: [
      { name: "mintTo", internalType: "address", type: "address" },
      { name: "merkleProof", internalType: "bytes32[]", type: "bytes32[]" },
      { name: "merkleRoot", internalType: "bytes32", type: "bytes32" },
    ],
    name: "InvalidMerkleProof",
  },
  { type: "error", inputs: [], name: "MerkleClaimsExceeded" },
  { type: "error", inputs: [], name: "SaleEnded" },
  { type: "error", inputs: [], name: "SaleHasNotStarted" },
  {
    type: "error",
    inputs: [
      { name: "user", internalType: "address", type: "address" },
      { name: "limit", internalType: "uint256", type: "uint256" },
      { name: "requestedAmount", internalType: "uint256", type: "uint256" },
    ],
    name: "UserExceedsMintLimit",
  },
  { type: "error", inputs: [], name: "WrongValueSent" },
  {
    type: "event",
    anonymous: false,
    inputs: [
      {
        name: "mediaContract",
        internalType: "address",
        type: "address",
        indexed: true,
      },
      {
        name: "tokenId",
        internalType: "uint256",
        type: "uint256",
        indexed: true,
      },
      {
        name: "merkleSaleSettings",
        internalType:
          "struct ZoraCreatorMerkleMinterStrategy.MerkleSaleSettings",
        type: "tuple",
        components: [
          { name: "presaleStart", internalType: "uint64", type: "uint64" },
          { name: "presaleEnd", internalType: "uint64", type: "uint64" },
          { name: "fundsRecipient", internalType: "address", type: "address" },
          { name: "merkleRoot", internalType: "bytes32", type: "bytes32" },
        ],
        indexed: false,
      },
    ],
    name: "SaleSet",
  },
  {
    stateMutability: "view",
    type: "function",
    inputs: [
      { name: "", internalType: "address", type: "address" },
      { name: "", internalType: "uint256", type: "uint256" },
    ],
    name: "allowedMerkles",
    outputs: [
      { name: "presaleStart", internalType: "uint64", type: "uint64" },
      { name: "presaleEnd", internalType: "uint64", type: "uint64" },
      { name: "fundsRecipient", internalType: "address", type: "address" },
      { name: "merkleRoot", internalType: "bytes32", type: "bytes32" },
    ],
  },
  {
    stateMutability: "pure",
    type: "function",
    inputs: [],
    name: "contractName",
    outputs: [{ name: "", internalType: "string", type: "string" }],
  },
  {
    stateMutability: "pure",
    type: "function",
    inputs: [],
    name: "contractURI",
    outputs: [{ name: "", internalType: "string", type: "string" }],
  },
  {
    stateMutability: "pure",
    type: "function",
    inputs: [],
    name: "contractVersion",
    outputs: [{ name: "", internalType: "string", type: "string" }],
  },
  {
    stateMutability: "view",
    type: "function",
    inputs: [
      { name: "tokenContract", internalType: "address", type: "address" },
      { name: "tokenId", internalType: "uint256", type: "uint256" },
      { name: "wallet", internalType: "address", type: "address" },
    ],
    name: "getMintedPerWallet",
    outputs: [{ name: "", internalType: "uint256", type: "uint256" }],
  },
  {
    stateMutability: "nonpayable",
    type: "function",
    inputs: [
      { name: "", internalType: "address", type: "address" },
      { name: "tokenId", internalType: "uint256", type: "uint256" },
      { name: "quantity", internalType: "uint256", type: "uint256" },
      { name: "ethValueSent", internalType: "uint256", type: "uint256" },
      { name: "minterArguments", internalType: "bytes", type: "bytes" },
    ],
    name: "requestMint",
    outputs: [
      {
        name: "commands",
        internalType: "struct ICreatorCommands.CommandSet",
        type: "tuple",
        components: [
          {
            name: "commands",
            internalType: "struct ICreatorCommands.Command[]",
            type: "tuple[]",
            components: [
              {
                name: "method",
                internalType: "enum ICreatorCommands.CreatorActions",
                type: "uint8",
              },
              { name: "args", internalType: "bytes", type: "bytes" },
            ],
          },
          { name: "at", internalType: "uint256", type: "uint256" },
        ],
      },
    ],
  },
  {
    stateMutability: "nonpayable",
    type: "function",
    inputs: [{ name: "tokenId", internalType: "uint256", type: "uint256" }],
    name: "resetSale",
    outputs: [],
  },
  {
    stateMutability: "view",
    type: "function",
    inputs: [
      { name: "tokenContract", internalType: "address", type: "address" },
      { name: "tokenId", internalType: "uint256", type: "uint256" },
    ],
    name: "sale",
    outputs: [
      {
        name: "",
        internalType:
          "struct ZoraCreatorMerkleMinterStrategy.MerkleSaleSettings",
        type: "tuple",
        components: [
          { name: "presaleStart", internalType: "uint64", type: "uint64" },
          { name: "presaleEnd", internalType: "uint64", type: "uint64" },
          { name: "fundsRecipient", internalType: "address", type: "address" },
          { name: "merkleRoot", internalType: "bytes32", type: "bytes32" },
        ],
      },
    ],
  },
  {
    stateMutability: "nonpayable",
    type: "function",
    inputs: [
      { name: "tokenId", internalType: "uint256", type: "uint256" },
      {
        name: "merkleSaleSettings",
        internalType:
          "struct ZoraCreatorMerkleMinterStrategy.MerkleSaleSettings",
        type: "tuple",
        components: [
          { name: "presaleStart", internalType: "uint64", type: "uint64" },
          { name: "presaleEnd", internalType: "uint64", type: "uint64" },
          { name: "fundsRecipient", internalType: "address", type: "address" },
          { name: "merkleRoot", internalType: "bytes32", type: "bytes32" },
        ],
      },
    ],
    name: "setSale",
    outputs: [],
  },
  {
    stateMutability: "pure",
    type: "function",
    inputs: [{ name: "interfaceId", internalType: "bytes4", type: "bytes4" }],
    name: "supportsInterface",
    outputs: [{ name: "", internalType: "bool", type: "bool" }],
  },
] as const;

/**
 * - [__View Contract on Ethereum Etherscan__](https://etherscan.io/address/0xf48172CA3B6068B20eE4917Eb27b5472f1f272C7)
 * - [__View Contract on Goerli Etherscan__](https://goerli.etherscan.io/address/0xf48172CA3B6068B20eE4917Eb27b5472f1f272C7)
 * - [__View Contract on Op Mainnet Optimism Explorer__](https://explorer.optimism.io/address/0x899ce31dF6C6Af81203AcAaD285bF539234eF4b8)
 * - [__View Contract on Optimism Goerli Etherscan__](https://goerli-optimism.etherscan.io/address/0xf48172CA3B6068B20eE4917Eb27b5472f1f272C7)
 * - [__View Contract on Zora Goerli Testnet Explorer__](https://testnet.explorer.zora.energy/address/0xf48172CA3B6068B20eE4917Eb27b5472f1f272C7)
 * - [__View Contract on Base Basescan__](https://basescan.org/address/0xf48172CA3B6068B20eE4917Eb27b5472f1f272C7)
 * - [__View Contract on Base Goerli Basescan__](https://goerli.basescan.org/address/0xf48172CA3B6068B20eE4917Eb27b5472f1f272C7)
 * - [__View Contract on Zora Explorer__](https://explorer.zora.energy/address/0xf48172CA3B6068B20eE4917Eb27b5472f1f272C7)
 * - [__View Contract on Sepolia Etherscan__](https://sepolia.etherscan.io/address/0x357D8108A77762B41Ea0C4D69fBb1eF4391251eC)
 */
export const zoraCreatorMerkleMinterStrategyAddress = {
  1: "0xf48172CA3B6068B20eE4917Eb27b5472f1f272C7",
  5: "0xf48172CA3B6068B20eE4917Eb27b5472f1f272C7",
  10: "0x899ce31dF6C6Af81203AcAaD285bF539234eF4b8",
  420: "0xf48172CA3B6068B20eE4917Eb27b5472f1f272C7",
  424: "0x314E552b55DFbDfD4d76623E1D45E5056723998B",
  999: "0xf48172CA3B6068B20eE4917Eb27b5472f1f272C7",
  8453: "0xf48172CA3B6068B20eE4917Eb27b5472f1f272C7",
  58008: "0x314E552b55DFbDfD4d76623E1D45E5056723998B",
  84531: "0xf48172CA3B6068B20eE4917Eb27b5472f1f272C7",
  7777777: "0xf48172CA3B6068B20eE4917Eb27b5472f1f272C7",
  11155111: "0x357D8108A77762B41Ea0C4D69fBb1eF4391251eC",
} as const;

/**
 * - [__View Contract on Ethereum Etherscan__](https://etherscan.io/address/0xf48172CA3B6068B20eE4917Eb27b5472f1f272C7)
 * - [__View Contract on Goerli Etherscan__](https://goerli.etherscan.io/address/0xf48172CA3B6068B20eE4917Eb27b5472f1f272C7)
 * - [__View Contract on Op Mainnet Optimism Explorer__](https://explorer.optimism.io/address/0x899ce31dF6C6Af81203AcAaD285bF539234eF4b8)
 * - [__View Contract on Optimism Goerli Etherscan__](https://goerli-optimism.etherscan.io/address/0xf48172CA3B6068B20eE4917Eb27b5472f1f272C7)
 * - [__View Contract on Zora Goerli Testnet Explorer__](https://testnet.explorer.zora.energy/address/0xf48172CA3B6068B20eE4917Eb27b5472f1f272C7)
 * - [__View Contract on Base Basescan__](https://basescan.org/address/0xf48172CA3B6068B20eE4917Eb27b5472f1f272C7)
 * - [__View Contract on Base Goerli Basescan__](https://goerli.basescan.org/address/0xf48172CA3B6068B20eE4917Eb27b5472f1f272C7)
 * - [__View Contract on Zora Explorer__](https://explorer.zora.energy/address/0xf48172CA3B6068B20eE4917Eb27b5472f1f272C7)
 * - [__View Contract on Sepolia Etherscan__](https://sepolia.etherscan.io/address/0x357D8108A77762B41Ea0C4D69fBb1eF4391251eC)
 */
export const zoraCreatorMerkleMinterStrategyConfig = {
  address: zoraCreatorMerkleMinterStrategyAddress,
  abi: zoraCreatorMerkleMinterStrategyABI,
} as const;

//////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
// ZoraCreatorRedeemMinterFactory
//////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

/**
 * - [__View Contract on Ethereum Etherscan__](https://etherscan.io/address/0x78964965cF77850224513a367f899435C5B69174)
 * - [__View Contract on Goerli Etherscan__](https://goerli.etherscan.io/address/0x78964965cF77850224513a367f899435C5B69174)
 * - [__View Contract on Op Mainnet Optimism Explorer__](https://explorer.optimism.io/address/0x1B28A04b7eB7b93f920ddF2021aa3fAE065395f2)
 * - [__View Contract on Optimism Goerli Etherscan__](https://goerli-optimism.etherscan.io/address/0x78964965cF77850224513a367f899435C5B69174)
 * - [__View Contract on Zora Goerli Testnet Explorer__](https://testnet.explorer.zora.energy/address/0x78964965cF77850224513a367f899435C5B69174)
 * - [__View Contract on Base Basescan__](https://basescan.org/address/0x78964965cF77850224513a367f899435C5B69174)
 * - [__View Contract on Base Goerli Basescan__](https://goerli.basescan.org/address/0x78964965cF77850224513a367f899435C5B69174)
 * - [__View Contract on Zora Explorer__](https://explorer.zora.energy/address/0x78964965cF77850224513a367f899435C5B69174)
 * - [__View Contract on Sepolia Etherscan__](https://sepolia.etherscan.io/address/0x66e7bE0b5A7dD9eb7999AAbE7AbdFa40381b6d5E)
 */
export const zoraCreatorRedeemMinterFactoryABI = [
  { stateMutability: "nonpayable", type: "constructor", inputs: [] },
  { type: "error", inputs: [], name: "CallerNotZoraCreator1155" },
  { type: "error", inputs: [], name: "MinterContractAlreadyExists" },
  { type: "error", inputs: [], name: "MinterContractDoesNotExist" },
  {
    type: "event",
    anonymous: false,
    inputs: [
      {
        name: "creatorContract",
        internalType: "address",
        type: "address",
        indexed: true,
      },
      {
        name: "minterContract",
        internalType: "address",
        type: "address",
        indexed: true,
      },
    ],
    name: "RedeemMinterDeployed",
  },
  {
    stateMutability: "view",
    type: "function",
    inputs: [],
    name: "CONTRACT_BASE_ID",
    outputs: [{ name: "", internalType: "uint256", type: "uint256" }],
  },
  {
    stateMutability: "pure",
    type: "function",
    inputs: [],
    name: "contractName",
    outputs: [{ name: "", internalType: "string", type: "string" }],
  },
  {
    stateMutability: "pure",
    type: "function",
    inputs: [],
    name: "contractURI",
    outputs: [{ name: "", internalType: "string", type: "string" }],
  },
  {
    stateMutability: "pure",
    type: "function",
    inputs: [],
    name: "contractVersion",
    outputs: [{ name: "", internalType: "string", type: "string" }],
  },
  {
    stateMutability: "nonpayable",
    type: "function",
    inputs: [],
    name: "createMinterIfNoneExists",
    outputs: [],
  },
  {
    stateMutability: "view",
    type: "function",
    inputs: [
      { name: "_creatorContract", internalType: "address", type: "address" },
    ],
    name: "doesRedeemMinterExistForCreatorContract",
    outputs: [{ name: "", internalType: "bool", type: "bool" }],
  },
  {
    stateMutability: "view",
    type: "function",
    inputs: [
      { name: "_creatorContract", internalType: "address", type: "address" },
    ],
    name: "getDeployedRedeemMinterForCreatorContract",
    outputs: [{ name: "", internalType: "address", type: "address" }],
  },
  {
    stateMutability: "view",
    type: "function",
    inputs: [
      { name: "_creatorContract", internalType: "address", type: "address" },
    ],
    name: "predictMinterAddress",
    outputs: [{ name: "", internalType: "address", type: "address" }],
  },
  {
    stateMutability: "nonpayable",
    type: "function",
    inputs: [
      { name: "sender", internalType: "address", type: "address" },
      { name: "tokenId", internalType: "uint256", type: "uint256" },
      { name: "quantity", internalType: "uint256", type: "uint256" },
      { name: "ethValueSent", internalType: "uint256", type: "uint256" },
      { name: "minterArguments", internalType: "bytes", type: "bytes" },
    ],
    name: "requestMint",
    outputs: [
      {
        name: "commands",
        internalType: "struct ICreatorCommands.CommandSet",
        type: "tuple",
        components: [
          {
            name: "commands",
            internalType: "struct ICreatorCommands.Command[]",
            type: "tuple[]",
            components: [
              {
                name: "method",
                internalType: "enum ICreatorCommands.CreatorActions",
                type: "uint8",
              },
              { name: "args", internalType: "bytes", type: "bytes" },
            ],
          },
          { name: "at", internalType: "uint256", type: "uint256" },
        ],
      },
    ],
  },
  {
    stateMutability: "pure",
    type: "function",
    inputs: [{ name: "interfaceId", internalType: "bytes4", type: "bytes4" }],
    name: "supportsInterface",
    outputs: [{ name: "", internalType: "bool", type: "bool" }],
  },
  {
    stateMutability: "view",
    type: "function",
    inputs: [],
    name: "zoraRedeemMinterImplementation",
    outputs: [{ name: "", internalType: "address", type: "address" }],
  },
] as const;

/**
 * - [__View Contract on Ethereum Etherscan__](https://etherscan.io/address/0x78964965cF77850224513a367f899435C5B69174)
 * - [__View Contract on Goerli Etherscan__](https://goerli.etherscan.io/address/0x78964965cF77850224513a367f899435C5B69174)
 * - [__View Contract on Op Mainnet Optimism Explorer__](https://explorer.optimism.io/address/0x1B28A04b7eB7b93f920ddF2021aa3fAE065395f2)
 * - [__View Contract on Optimism Goerli Etherscan__](https://goerli-optimism.etherscan.io/address/0x78964965cF77850224513a367f899435C5B69174)
 * - [__View Contract on Zora Goerli Testnet Explorer__](https://testnet.explorer.zora.energy/address/0x78964965cF77850224513a367f899435C5B69174)
 * - [__View Contract on Base Basescan__](https://basescan.org/address/0x78964965cF77850224513a367f899435C5B69174)
 * - [__View Contract on Base Goerli Basescan__](https://goerli.basescan.org/address/0x78964965cF77850224513a367f899435C5B69174)
 * - [__View Contract on Zora Explorer__](https://explorer.zora.energy/address/0x78964965cF77850224513a367f899435C5B69174)
 * - [__View Contract on Sepolia Etherscan__](https://sepolia.etherscan.io/address/0x66e7bE0b5A7dD9eb7999AAbE7AbdFa40381b6d5E)
 */
export const zoraCreatorRedeemMinterFactoryAddress = {
  1: "0x78964965cF77850224513a367f899435C5B69174",
  5: "0x78964965cF77850224513a367f899435C5B69174",
  10: "0x1B28A04b7eB7b93f920ddF2021aa3fAE065395f2",
  420: "0x78964965cF77850224513a367f899435C5B69174",
  424: "0xC6899816663891D7493939d74d83cb7f2BBcBB16",
  999: "0x78964965cF77850224513a367f899435C5B69174",
  8453: "0x78964965cF77850224513a367f899435C5B69174",
  58008: "0xC6899816663891D7493939d74d83cb7f2BBcBB16",
  84531: "0x78964965cF77850224513a367f899435C5B69174",
  7777777: "0x78964965cF77850224513a367f899435C5B69174",
  11155111: "0x66e7bE0b5A7dD9eb7999AAbE7AbdFa40381b6d5E",
} as const;

/**
 * - [__View Contract on Ethereum Etherscan__](https://etherscan.io/address/0x78964965cF77850224513a367f899435C5B69174)
 * - [__View Contract on Goerli Etherscan__](https://goerli.etherscan.io/address/0x78964965cF77850224513a367f899435C5B69174)
 * - [__View Contract on Op Mainnet Optimism Explorer__](https://explorer.optimism.io/address/0x1B28A04b7eB7b93f920ddF2021aa3fAE065395f2)
 * - [__View Contract on Optimism Goerli Etherscan__](https://goerli-optimism.etherscan.io/address/0x78964965cF77850224513a367f899435C5B69174)
 * - [__View Contract on Zora Goerli Testnet Explorer__](https://testnet.explorer.zora.energy/address/0x78964965cF77850224513a367f899435C5B69174)
 * - [__View Contract on Base Basescan__](https://basescan.org/address/0x78964965cF77850224513a367f899435C5B69174)
 * - [__View Contract on Base Goerli Basescan__](https://goerli.basescan.org/address/0x78964965cF77850224513a367f899435C5B69174)
 * - [__View Contract on Zora Explorer__](https://explorer.zora.energy/address/0x78964965cF77850224513a367f899435C5B69174)
 * - [__View Contract on Sepolia Etherscan__](https://sepolia.etherscan.io/address/0x66e7bE0b5A7dD9eb7999AAbE7AbdFa40381b6d5E)
 */
export const zoraCreatorRedeemMinterFactoryConfig = {
  address: zoraCreatorRedeemMinterFactoryAddress,
  abi: zoraCreatorRedeemMinterFactoryABI,
} as const;

//////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
// ZoraCreatorRedeemMinterStrategy
//////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

export const zoraCreatorRedeemMinterStrategyABI = [
  { type: "error", inputs: [], name: "BurnFailed" },
  { type: "error", inputs: [], name: "CallerNotCreatorContract" },
  { type: "error", inputs: [], name: "EmptyRedeemInstructions" },
  { type: "error", inputs: [], name: "IncorrectBurnOrTransferAmount" },
  { type: "error", inputs: [], name: "IncorrectMintAmount" },
  { type: "error", inputs: [], name: "IncorrectNumberOfTokenIds" },
  { type: "error", inputs: [], name: "InvalidCreatorContract" },
  { type: "error", inputs: [], name: "InvalidSaleEndOrStart" },
  { type: "error", inputs: [], name: "InvalidTokenIdsForTokenType" },
  { type: "error", inputs: [], name: "InvalidTokenType" },
  { type: "error", inputs: [], name: "MintTokenContractMustBeCreatorContract" },
  { type: "error", inputs: [], name: "MintTokenTypeMustBeERC1155" },
  { type: "error", inputs: [], name: "MustBurnOrTransfer" },
  { type: "error", inputs: [], name: "MustCallClearRedeem" },
  { type: "error", inputs: [], name: "RedeemInstructionAlreadySet" },
  { type: "error", inputs: [], name: "RedeemInstructionNotAllowed" },
  { type: "error", inputs: [], name: "SaleEnded" },
  { type: "error", inputs: [], name: "SaleHasNotStarted" },
  { type: "error", inputs: [], name: "SenderIsNotTokenOwner" },
  { type: "error", inputs: [], name: "TokenIdOutOfRange" },
  { type: "error", inputs: [], name: "WrongValueSent" },
  {
    type: "event",
    anonymous: false,
    inputs: [
      { name: "version", internalType: "uint8", type: "uint8", indexed: false },
    ],
    name: "Initialized",
  },
  {
    type: "event",
    anonymous: false,
    inputs: [
      {
        name: "target",
        internalType: "address",
        type: "address",
        indexed: true,
      },
      {
        name: "redeemsInstructionsHash",
        internalType: "bytes32",
        type: "bytes32",
        indexed: true,
      },
      {
        name: "sender",
        internalType: "address",
        type: "address",
        indexed: false,
      },
      {
        name: "tokenIds",
        internalType: "uint256[][]",
        type: "uint256[][]",
        indexed: false,
      },
      {
        name: "amounts",
        internalType: "uint256[][]",
        type: "uint256[][]",
        indexed: false,
      },
    ],
    name: "RedeemProcessed",
  },
  {
    type: "event",
    anonymous: false,
    inputs: [
      {
        name: "target",
        internalType: "address",
        type: "address",
        indexed: true,
      },
      {
        name: "redeemsInstructionsHash",
        internalType: "bytes32",
        type: "bytes32",
        indexed: true,
      },
      {
        name: "data",
        internalType:
          "struct ZoraCreatorRedeemMinterStrategy.RedeemInstructions",
        type: "tuple",
        components: [
          {
            name: "mintToken",
            internalType: "struct ZoraCreatorRedeemMinterStrategy.MintToken",
            type: "tuple",
            components: [
              {
                name: "tokenContract",
                internalType: "address",
                type: "address",
              },
              { name: "tokenId", internalType: "uint256", type: "uint256" },
              { name: "amount", internalType: "uint256", type: "uint256" },
              {
                name: "tokenType",
                internalType: "enum ZoraCreatorRedeemMinterStrategy.TokenType",
                type: "uint8",
              },
            ],
          },
          {
            name: "instructions",
            internalType:
              "struct ZoraCreatorRedeemMinterStrategy.RedeemInstruction[]",
            type: "tuple[]",
            components: [
              {
                name: "tokenType",
                internalType: "enum ZoraCreatorRedeemMinterStrategy.TokenType",
                type: "uint8",
              },
              { name: "amount", internalType: "uint256", type: "uint256" },
              {
                name: "tokenIdStart",
                internalType: "uint256",
                type: "uint256",
              },
              { name: "tokenIdEnd", internalType: "uint256", type: "uint256" },
              {
                name: "tokenContract",
                internalType: "address",
                type: "address",
              },
              {
                name: "transferRecipient",
                internalType: "address",
                type: "address",
              },
              { name: "burnFunction", internalType: "bytes4", type: "bytes4" },
            ],
          },
          { name: "saleStart", internalType: "uint64", type: "uint64" },
          { name: "saleEnd", internalType: "uint64", type: "uint64" },
          { name: "ethAmount", internalType: "uint256", type: "uint256" },
          { name: "ethRecipient", internalType: "address", type: "address" },
        ],
        indexed: false,
      },
    ],
    name: "RedeemSet",
  },
  {
    type: "event",
    anonymous: false,
    inputs: [
      {
        name: "target",
        internalType: "address",
        type: "address",
        indexed: true,
      },
      {
        name: "redeemInstructionsHashes",
        internalType: "bytes32[]",
        type: "bytes32[]",
        indexed: true,
      },
    ],
    name: "RedeemsCleared",
  },
  {
    stateMutability: "nonpayable",
    type: "function",
    inputs: [
      { name: "tokenId", internalType: "uint256", type: "uint256" },
      { name: "hashes", internalType: "bytes32[]", type: "bytes32[]" },
    ],
    name: "clearRedeem",
    outputs: [],
  },
  {
    stateMutability: "pure",
    type: "function",
    inputs: [],
    name: "contractName",
    outputs: [{ name: "", internalType: "string", type: "string" }],
  },
  {
    stateMutability: "pure",
    type: "function",
    inputs: [],
    name: "contractURI",
    outputs: [{ name: "", internalType: "string", type: "string" }],
  },
  {
    stateMutability: "pure",
    type: "function",
    inputs: [],
    name: "contractVersion",
    outputs: [{ name: "", internalType: "string", type: "string" }],
  },
  {
    stateMutability: "view",
    type: "function",
    inputs: [],
    name: "creatorContract",
    outputs: [{ name: "", internalType: "address", type: "address" }],
  },
  {
    stateMutability: "nonpayable",
    type: "function",
    inputs: [
      { name: "_creatorContract", internalType: "address", type: "address" },
    ],
    name: "initialize",
    outputs: [],
  },
  {
    stateMutability: "pure",
    type: "function",
    inputs: [
      {
        name: "_redeemInstructions",
        internalType:
          "struct ZoraCreatorRedeemMinterStrategy.RedeemInstructions",
        type: "tuple",
        components: [
          {
            name: "mintToken",
            internalType: "struct ZoraCreatorRedeemMinterStrategy.MintToken",
            type: "tuple",
            components: [
              {
                name: "tokenContract",
                internalType: "address",
                type: "address",
              },
              { name: "tokenId", internalType: "uint256", type: "uint256" },
              { name: "amount", internalType: "uint256", type: "uint256" },
              {
                name: "tokenType",
                internalType: "enum ZoraCreatorRedeemMinterStrategy.TokenType",
                type: "uint8",
              },
            ],
          },
          {
            name: "instructions",
            internalType:
              "struct ZoraCreatorRedeemMinterStrategy.RedeemInstruction[]",
            type: "tuple[]",
            components: [
              {
                name: "tokenType",
                internalType: "enum ZoraCreatorRedeemMinterStrategy.TokenType",
                type: "uint8",
              },
              { name: "amount", internalType: "uint256", type: "uint256" },
              {
                name: "tokenIdStart",
                internalType: "uint256",
                type: "uint256",
              },
              { name: "tokenIdEnd", internalType: "uint256", type: "uint256" },
              {
                name: "tokenContract",
                internalType: "address",
                type: "address",
              },
              {
                name: "transferRecipient",
                internalType: "address",
                type: "address",
              },
              { name: "burnFunction", internalType: "bytes4", type: "bytes4" },
            ],
          },
          { name: "saleStart", internalType: "uint64", type: "uint64" },
          { name: "saleEnd", internalType: "uint64", type: "uint64" },
          { name: "ethAmount", internalType: "uint256", type: "uint256" },
          { name: "ethRecipient", internalType: "address", type: "address" },
        ],
      },
    ],
    name: "redeemInstructionsHash",
    outputs: [{ name: "", internalType: "bytes32", type: "bytes32" }],
  },
  {
    stateMutability: "view",
    type: "function",
    inputs: [
      { name: "", internalType: "uint256", type: "uint256" },
      { name: "", internalType: "bytes32", type: "bytes32" },
    ],
    name: "redeemInstructionsHashIsAllowed",
    outputs: [{ name: "", internalType: "bool", type: "bool" }],
  },
  {
    stateMutability: "nonpayable",
    type: "function",
    inputs: [
      { name: "sender", internalType: "address", type: "address" },
      { name: "tokenId", internalType: "uint256", type: "uint256" },
      { name: "amount", internalType: "uint256", type: "uint256" },
      { name: "ethValueSent", internalType: "uint256", type: "uint256" },
      { name: "minterArguments", internalType: "bytes", type: "bytes" },
    ],
    name: "requestMint",
    outputs: [
      {
        name: "commands",
        internalType: "struct ICreatorCommands.CommandSet",
        type: "tuple",
        components: [
          {
            name: "commands",
            internalType: "struct ICreatorCommands.Command[]",
            type: "tuple[]",
            components: [
              {
                name: "method",
                internalType: "enum ICreatorCommands.CreatorActions",
                type: "uint8",
              },
              { name: "args", internalType: "bytes", type: "bytes" },
            ],
          },
          { name: "at", internalType: "uint256", type: "uint256" },
        ],
      },
    ],
  },
  {
    stateMutability: "view",
    type: "function",
    inputs: [{ name: "", internalType: "uint256", type: "uint256" }],
    name: "resetSale",
    outputs: [],
  },
  {
    stateMutability: "nonpayable",
    type: "function",
    inputs: [
      { name: "tokenId", internalType: "uint256", type: "uint256" },
      {
        name: "_redeemInstructions",
        internalType:
          "struct ZoraCreatorRedeemMinterStrategy.RedeemInstructions",
        type: "tuple",
        components: [
          {
            name: "mintToken",
            internalType: "struct ZoraCreatorRedeemMinterStrategy.MintToken",
            type: "tuple",
            components: [
              {
                name: "tokenContract",
                internalType: "address",
                type: "address",
              },
              { name: "tokenId", internalType: "uint256", type: "uint256" },
              { name: "amount", internalType: "uint256", type: "uint256" },
              {
                name: "tokenType",
                internalType: "enum ZoraCreatorRedeemMinterStrategy.TokenType",
                type: "uint8",
              },
            ],
          },
          {
            name: "instructions",
            internalType:
              "struct ZoraCreatorRedeemMinterStrategy.RedeemInstruction[]",
            type: "tuple[]",
            components: [
              {
                name: "tokenType",
                internalType: "enum ZoraCreatorRedeemMinterStrategy.TokenType",
                type: "uint8",
              },
              { name: "amount", internalType: "uint256", type: "uint256" },
              {
                name: "tokenIdStart",
                internalType: "uint256",
                type: "uint256",
              },
              { name: "tokenIdEnd", internalType: "uint256", type: "uint256" },
              {
                name: "tokenContract",
                internalType: "address",
                type: "address",
              },
              {
                name: "transferRecipient",
                internalType: "address",
                type: "address",
              },
              { name: "burnFunction", internalType: "bytes4", type: "bytes4" },
            ],
          },
          { name: "saleStart", internalType: "uint64", type: "uint64" },
          { name: "saleEnd", internalType: "uint64", type: "uint64" },
          { name: "ethAmount", internalType: "uint256", type: "uint256" },
          { name: "ethRecipient", internalType: "address", type: "address" },
        ],
      },
    ],
    name: "setRedeem",
    outputs: [],
  },
  {
    stateMutability: "pure",
    type: "function",
    inputs: [{ name: "interfaceId", internalType: "bytes4", type: "bytes4" }],
    name: "supportsInterface",
    outputs: [{ name: "", internalType: "bool", type: "bool" }],
  },
  {
    stateMutability: "view",
    type: "function",
    inputs: [
      {
        name: "_redeemInstructions",
        internalType:
          "struct ZoraCreatorRedeemMinterStrategy.RedeemInstructions",
        type: "tuple",
        components: [
          {
            name: "mintToken",
            internalType: "struct ZoraCreatorRedeemMinterStrategy.MintToken",
            type: "tuple",
            components: [
              {
                name: "tokenContract",
                internalType: "address",
                type: "address",
              },
              { name: "tokenId", internalType: "uint256", type: "uint256" },
              { name: "amount", internalType: "uint256", type: "uint256" },
              {
                name: "tokenType",
                internalType: "enum ZoraCreatorRedeemMinterStrategy.TokenType",
                type: "uint8",
              },
            ],
          },
          {
            name: "instructions",
            internalType:
              "struct ZoraCreatorRedeemMinterStrategy.RedeemInstruction[]",
            type: "tuple[]",
            components: [
              {
                name: "tokenType",
                internalType: "enum ZoraCreatorRedeemMinterStrategy.TokenType",
                type: "uint8",
              },
              { name: "amount", internalType: "uint256", type: "uint256" },
              {
                name: "tokenIdStart",
                internalType: "uint256",
                type: "uint256",
              },
              { name: "tokenIdEnd", internalType: "uint256", type: "uint256" },
              {
                name: "tokenContract",
                internalType: "address",
                type: "address",
              },
              {
                name: "transferRecipient",
                internalType: "address",
                type: "address",
              },
              { name: "burnFunction", internalType: "bytes4", type: "bytes4" },
            ],
          },
          { name: "saleStart", internalType: "uint64", type: "uint64" },
          { name: "saleEnd", internalType: "uint64", type: "uint64" },
          { name: "ethAmount", internalType: "uint256", type: "uint256" },
          { name: "ethRecipient", internalType: "address", type: "address" },
        ],
      },
    ],
    name: "validateRedeemInstructions",
    outputs: [],
  },
] as const;
