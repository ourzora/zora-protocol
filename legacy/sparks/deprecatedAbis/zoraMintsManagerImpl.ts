export const abi = [
  {
    type: "constructor",
    inputs: [
      {
        name: "_premintExecutor",
        type: "address",
        internalType: "contract IZoraCreator1155PremintExecutorAllVersions",
      },
    ],
    stateMutability: "nonpayable",
  },
  {
    type: "function",
    name: "UPGRADE_INTERFACE_VERSION",
    inputs: [],
    outputs: [{ name: "", type: "string", internalType: "string" }],
    stateMutability: "view",
  },
  {
    type: "function",
    name: "acceptOwnership",
    inputs: [],
    outputs: [],
    stateMutability: "nonpayable",
  },
  {
    type: "function",
    name: "callWithTransferTokens",
    inputs: [
      { name: "callFrom", type: "address", internalType: "address" },
      {
        name: "tokenIds",
        type: "uint256[]",
        internalType: "uint256[]",
      },
      {
        name: "quantities",
        type: "uint256[]",
        internalType: "uint256[]",
      },
      { name: "call", type: "bytes", internalType: "bytes" },
    ],
    outputs: [
      { name: "success", type: "bool", internalType: "bool" },
      { name: "result", type: "bytes", internalType: "bytes" },
    ],
    stateMutability: "payable",
  },
  {
    type: "function",
    name: "canCall",
    inputs: [
      { name: "caller", type: "address", internalType: "address" },
      { name: "", type: "address", internalType: "address" },
      { name: "", type: "bytes4", internalType: "bytes4" },
    ],
    outputs: [{ name: "", type: "bool", internalType: "bool" }],
    stateMutability: "view",
  },
  {
    type: "function",
    name: "collect",
    inputs: [
      {
        name: "zoraCreator1155Contract",
        type: "address",
        internalType: "contract IMintWithSparks",
      },
      {
        name: "minter",
        type: "address",
        internalType: "contract IMinter1155",
      },
      {
        name: "zoraCreator1155TokenId",
        type: "uint256",
        internalType: "uint256",
      },
      {
        name: "collectMintArguments",
        type: "tuple",
        internalType: "struct ICollectWithZoraSparks.CollectMintArguments",
        components: [
          {
            name: "mintRewardsRecipients",
            type: "address[]",
            internalType: "address[]",
          },
          {
            name: "minterArguments",
            type: "bytes",
            internalType: "bytes",
          },
          {
            name: "mintComment",
            type: "string",
            internalType: "string",
          },
        ],
      },
    ],
    outputs: [],
    stateMutability: "payable",
  },
  {
    type: "function",
    name: "collectPremint",
    inputs: [
      {
        name: "contractConfig",
        type: "tuple",
        internalType: "struct ContractWithAdditionalAdminsCreationConfig",
        components: [
          {
            name: "contractAdmin",
            type: "address",
            internalType: "address",
          },
          {
            name: "contractURI",
            type: "string",
            internalType: "string",
          },
          {
            name: "contractName",
            type: "string",
            internalType: "string",
          },
          {
            name: "additionalAdmins",
            type: "address[]",
            internalType: "address[]",
          },
        ],
      },
      {
        name: "tokenContract",
        type: "address",
        internalType: "address",
      },
      {
        name: "premintConfig",
        type: "tuple",
        internalType: "struct PremintConfigEncoded",
        components: [
          { name: "uid", type: "uint32", internalType: "uint32" },
          { name: "version", type: "uint32", internalType: "uint32" },
          { name: "deleted", type: "bool", internalType: "bool" },
          { name: "tokenConfig", type: "bytes", internalType: "bytes" },
          {
            name: "premintConfigVersion",
            type: "bytes32",
            internalType: "bytes32",
          },
        ],
      },
      { name: "signature", type: "bytes", internalType: "bytes" },
      {
        name: "mintArguments",
        type: "tuple",
        internalType: "struct MintArguments",
        components: [
          {
            name: "mintRecipient",
            type: "address",
            internalType: "address",
          },
          {
            name: "mintComment",
            type: "string",
            internalType: "string",
          },
          {
            name: "mintRewardsRecipients",
            type: "address[]",
            internalType: "address[]",
          },
        ],
      },
      { name: "firstMinter", type: "address", internalType: "address" },
      {
        name: "signerContract",
        type: "address",
        internalType: "address",
      },
    ],
    outputs: [
      {
        name: "result",
        type: "tuple",
        internalType: "struct PremintResult",
        components: [
          {
            name: "contractAddress",
            type: "address",
            internalType: "address",
          },
          { name: "tokenId", type: "uint256", internalType: "uint256" },
          {
            name: "createdNewContract",
            type: "bool",
            internalType: "bool",
          },
        ],
      },
    ],
    stateMutability: "payable",
  },
  {
    type: "function",
    name: "collectPremintV2",
    inputs: [
      {
        name: "contractConfig",
        type: "tuple",
        internalType: "struct ContractCreationConfig",
        components: [
          {
            name: "contractAdmin",
            type: "address",
            internalType: "address",
          },
          {
            name: "contractURI",
            type: "string",
            internalType: "string",
          },
          {
            name: "contractName",
            type: "string",
            internalType: "string",
          },
        ],
      },
      {
        name: "premintConfig",
        type: "tuple",
        internalType: "struct PremintConfigV2",
        components: [
          {
            name: "tokenConfig",
            type: "tuple",
            internalType: "struct TokenCreationConfigV2",
            components: [
              {
                name: "tokenURI",
                type: "string",
                internalType: "string",
              },
              {
                name: "maxSupply",
                type: "uint256",
                internalType: "uint256",
              },
              {
                name: "maxTokensPerAddress",
                type: "uint64",
                internalType: "uint64",
              },
              {
                name: "pricePerToken",
                type: "uint96",
                internalType: "uint96",
              },
              {
                name: "mintStart",
                type: "uint64",
                internalType: "uint64",
              },
              {
                name: "mintDuration",
                type: "uint64",
                internalType: "uint64",
              },
              {
                name: "royaltyBPS",
                type: "uint32",
                internalType: "uint32",
              },
              {
                name: "payoutRecipient",
                type: "address",
                internalType: "address",
              },
              {
                name: "fixedPriceMinter",
                type: "address",
                internalType: "address",
              },
              {
                name: "createReferral",
                type: "address",
                internalType: "address",
              },
            ],
          },
          { name: "uid", type: "uint32", internalType: "uint32" },
          { name: "version", type: "uint32", internalType: "uint32" },
          { name: "deleted", type: "bool", internalType: "bool" },
        ],
      },
      { name: "signature", type: "bytes", internalType: "bytes" },
      {
        name: "mintArguments",
        type: "tuple",
        internalType: "struct MintArguments",
        components: [
          {
            name: "mintRecipient",
            type: "address",
            internalType: "address",
          },
          {
            name: "mintComment",
            type: "string",
            internalType: "string",
          },
          {
            name: "mintRewardsRecipients",
            type: "address[]",
            internalType: "address[]",
          },
        ],
      },
      {
        name: "signerContract",
        type: "address",
        internalType: "address",
      },
    ],
    outputs: [
      {
        name: "result",
        type: "tuple",
        internalType: "struct PremintResult",
        components: [
          {
            name: "contractAddress",
            type: "address",
            internalType: "address",
          },
          { name: "tokenId", type: "uint256", internalType: "uint256" },
          {
            name: "createdNewContract",
            type: "bool",
            internalType: "bool",
          },
        ],
      },
    ],
    stateMutability: "payable",
  },
  {
    type: "function",
    name: "contractName",
    inputs: [],
    outputs: [{ name: "", type: "string", internalType: "string" }],
    stateMutability: "pure",
  },
  {
    type: "function",
    name: "contractURI",
    inputs: [],
    outputs: [{ name: "", type: "string", internalType: "string" }],
    stateMutability: "view",
  },
  {
    type: "function",
    name: "contractVersion",
    inputs: [],
    outputs: [{ name: "", type: "string", internalType: "string" }],
    stateMutability: "pure",
  },
  {
    type: "function",
    name: "createToken",
    inputs: [
      { name: "tokenId", type: "uint256", internalType: "uint256" },
      {
        name: "tokenConfig",
        type: "tuple",
        internalType: "struct TokenConfig",
        components: [
          { name: "price", type: "uint256", internalType: "uint256" },
          {
            name: "tokenAddress",
            type: "address",
            internalType: "address",
          },
          {
            name: "redeemHandler",
            type: "address",
            internalType: "address",
          },
        ],
      },
      { name: "defaultMintable", type: "bool", internalType: "bool" },
    ],
    outputs: [],
    stateMutability: "nonpayable",
  },
  {
    type: "function",
    name: "decodeMintRecipientAndComment",
    inputs: [{ name: "minterArguments", type: "bytes", internalType: "bytes" }],
    outputs: [
      { name: "mintTo", type: "address", internalType: "address" },
      { name: "mintComment", type: "string", internalType: "string" },
    ],
    stateMutability: "pure",
  },
  {
    type: "function",
    name: "getEthPrice",
    inputs: [],
    outputs: [{ name: "", type: "uint256", internalType: "uint256" }],
    stateMutability: "view",
  },
  {
    type: "function",
    name: "implementation",
    inputs: [],
    outputs: [{ name: "", type: "address", internalType: "address" }],
    stateMutability: "view",
  },
  {
    type: "function",
    name: "initialize",
    inputs: [
      {
        name: "defaultOwner",
        type: "address",
        internalType: "address",
      },
      {
        name: "zoraSparksSalt",
        type: "bytes32",
        internalType: "bytes32",
      },
      {
        name: "zoraSparksCreationCode",
        type: "bytes",
        internalType: "bytes",
      },
      {
        name: "initialEthTokenId",
        type: "uint256",
        internalType: "uint256",
      },
      {
        name: "initialEthTokenPrice",
        type: "uint256",
        internalType: "uint256",
      },
      { name: "newBaseURI", type: "string", internalType: "string" },
      { name: "newContractURI", type: "string", internalType: "string" },
    ],
    outputs: [
      {
        name: "mints",
        type: "address",
        internalType: "contract IZoraSparks1155",
      },
    ],
    stateMutability: "nonpayable",
  },
  {
    type: "function",
    name: "mintWithERC20",
    inputs: [
      {
        name: "tokenAddress",
        type: "address",
        internalType: "address",
      },
      { name: "quantity", type: "uint256", internalType: "uint256" },
      { name: "recipient", type: "address", internalType: "address" },
    ],
    outputs: [
      {
        name: "mintableTokenId",
        type: "uint256",
        internalType: "uint256",
      },
    ],
    stateMutability: "nonpayable",
  },
  {
    type: "function",
    name: "mintWithEth",
    inputs: [
      { name: "quantity", type: "uint256", internalType: "uint256" },
      { name: "recipient", type: "address", internalType: "address" },
    ],
    outputs: [
      {
        name: "mintableTokenId",
        type: "uint256",
        internalType: "uint256",
      },
    ],
    stateMutability: "payable",
  },
  {
    type: "function",
    name: "mintableEthToken",
    inputs: [],
    outputs: [{ name: "", type: "uint256", internalType: "uint256" }],
    stateMutability: "view",
  },
  {
    type: "function",
    name: "onERC1155BatchReceived",
    inputs: [
      { name: "", type: "address", internalType: "address" },
      { name: "from", type: "address", internalType: "address" },
      { name: "ids", type: "uint256[]", internalType: "uint256[]" },
      { name: "values", type: "uint256[]", internalType: "uint256[]" },
      { name: "data", type: "bytes", internalType: "bytes" },
    ],
    outputs: [{ name: "", type: "bytes4", internalType: "bytes4" }],
    stateMutability: "nonpayable",
  },
  {
    type: "function",
    name: "onERC1155Received",
    inputs: [
      { name: "", type: "address", internalType: "address" },
      { name: "from", type: "address", internalType: "address" },
      { name: "id", type: "uint256", internalType: "uint256" },
      { name: "value", type: "uint256", internalType: "uint256" },
      { name: "data", type: "bytes", internalType: "bytes" },
    ],
    outputs: [{ name: "", type: "bytes4", internalType: "bytes4" }],
    stateMutability: "nonpayable",
  },
  {
    type: "function",
    name: "owner",
    inputs: [],
    outputs: [{ name: "", type: "address", internalType: "address" }],
    stateMutability: "view",
  },
  {
    type: "function",
    name: "pendingOwner",
    inputs: [],
    outputs: [{ name: "", type: "address", internalType: "address" }],
    stateMutability: "view",
  },
  {
    type: "function",
    name: "proxiableUUID",
    inputs: [],
    outputs: [{ name: "", type: "bytes32", internalType: "bytes32" }],
    stateMutability: "view",
  },
  {
    type: "function",
    name: "renounceOwnership",
    inputs: [],
    outputs: [],
    stateMutability: "nonpayable",
  },
  {
    type: "function",
    name: "setDefaultMintable",
    inputs: [
      {
        name: "tokenAddress",
        type: "address",
        internalType: "address",
      },
      { name: "tokenId", type: "uint256", internalType: "uint256" },
    ],
    outputs: [],
    stateMutability: "nonpayable",
  },
  {
    type: "function",
    name: "setMetadataURIs",
    inputs: [
      {
        name: "newContractURI",
        type: "string",
        internalType: "string",
      },
      { name: "newBaseURI", type: "string", internalType: "string" },
      {
        name: "tokenIdsToNotifyUpdate",
        type: "uint256[]",
        internalType: "uint256[]",
      },
    ],
    outputs: [],
    stateMutability: "nonpayable",
  },
  {
    type: "function",
    name: "transferOwnership",
    inputs: [{ name: "newOwner", type: "address", internalType: "address" }],
    outputs: [],
    stateMutability: "nonpayable",
  },
  {
    type: "function",
    name: "upgradeToAndCall",
    inputs: [
      {
        name: "newImplementation",
        type: "address",
        internalType: "address",
      },
      { name: "data", type: "bytes", internalType: "bytes" },
    ],
    outputs: [],
    stateMutability: "payable",
  },
  {
    type: "function",
    name: "uri",
    inputs: [{ name: "tokenId", type: "uint256", internalType: "uint256" }],
    outputs: [{ name: "", type: "string", internalType: "string" }],
    stateMutability: "view",
  },
  {
    type: "function",
    name: "zoraSparks1155",
    inputs: [],
    outputs: [
      {
        name: "",
        type: "address",
        internalType: "contract IZoraSparks1155",
      },
    ],
    stateMutability: "view",
  },
  {
    type: "event",
    name: "Collected",
    inputs: [
      {
        name: "tokenIds",
        type: "uint256[]",
        indexed: true,
        internalType: "uint256[]",
      },
      {
        name: "quantities",
        type: "uint256[]",
        indexed: false,
        internalType: "uint256[]",
      },
      {
        name: "zoraCreator1155Contract",
        type: "address",
        indexed: true,
        internalType: "address",
      },
      {
        name: "zoraCreator1155TokenId",
        type: "uint256",
        indexed: true,
        internalType: "uint256",
      },
    ],
    anonymous: false,
  },
  {
    type: "event",
    name: "DefaultMintableTokenSet",
    inputs: [
      {
        name: "tokenAddress",
        type: "address",
        indexed: false,
        internalType: "address",
      },
      {
        name: "tokenId",
        type: "uint256",
        indexed: false,
        internalType: "uint256",
      },
    ],
    anonymous: false,
  },
  {
    type: "event",
    name: "Initialized",
    inputs: [
      {
        name: "version",
        type: "uint64",
        indexed: false,
        internalType: "uint64",
      },
    ],
    anonymous: false,
  },
  {
    type: "event",
    name: "MintComment",
    inputs: [
      {
        name: "sender",
        type: "address",
        indexed: true,
        internalType: "address",
      },
      {
        name: "tokenContract",
        type: "address",
        indexed: true,
        internalType: "address",
      },
      {
        name: "tokenId",
        type: "uint256",
        indexed: true,
        internalType: "uint256",
      },
      {
        name: "quantity",
        type: "uint256",
        indexed: false,
        internalType: "uint256",
      },
      {
        name: "comment",
        type: "string",
        indexed: false,
        internalType: "string",
      },
    ],
    anonymous: false,
  },
  {
    type: "event",
    name: "OwnershipTransferStarted",
    inputs: [
      {
        name: "previousOwner",
        type: "address",
        indexed: true,
        internalType: "address",
      },
      {
        name: "newOwner",
        type: "address",
        indexed: true,
        internalType: "address",
      },
    ],
    anonymous: false,
  },
  {
    type: "event",
    name: "OwnershipTransferred",
    inputs: [
      {
        name: "previousOwner",
        type: "address",
        indexed: true,
        internalType: "address",
      },
      {
        name: "newOwner",
        type: "address",
        indexed: true,
        internalType: "address",
      },
    ],
    anonymous: false,
  },
  {
    type: "event",
    name: "URIsUpdated",
    inputs: [
      {
        name: "contractURI",
        type: "string",
        indexed: false,
        internalType: "string",
      },
      {
        name: "baseURI",
        type: "string",
        indexed: false,
        internalType: "string",
      },
    ],
    anonymous: false,
  },
  {
    type: "event",
    name: "Upgraded",
    inputs: [
      {
        name: "implementation",
        type: "address",
        indexed: true,
        internalType: "address",
      },
    ],
    anonymous: false,
  },
  {
    type: "error",
    name: "AddressEmptyCode",
    inputs: [{ name: "target", type: "address", internalType: "address" }],
  },
  {
    type: "error",
    name: "AddressInsufficientBalance",
    inputs: [{ name: "account", type: "address", internalType: "address" }],
  },
  {
    type: "error",
    name: "ArrayLengthMismatch",
    inputs: [
      { name: "lengthA", type: "uint256", internalType: "uint256" },
      { name: "lengthB", type: "uint256", internalType: "uint256" },
    ],
  },
  {
    type: "error",
    name: "Burn_NotOwnerOrApproved",
    inputs: [
      { name: "operator", type: "address", internalType: "address" },
      { name: "user", type: "address", internalType: "address" },
    ],
  },
  {
    type: "error",
    name: "CallFailed",
    inputs: [{ name: "reason", type: "bytes", internalType: "bytes" }],
  },
  { type: "error", name: "Call_TokenIdMismatch", inputs: [] },
  { type: "error", name: "CallerNotZoraCreator1155", inputs: [] },
  {
    type: "error",
    name: "CannotMintMoreTokens",
    inputs: [
      { name: "tokenId", type: "uint256", internalType: "uint256" },
      { name: "quantity", type: "uint256", internalType: "uint256" },
      { name: "totalMinted", type: "uint256", internalType: "uint256" },
      { name: "maxSupply", type: "uint256", internalType: "uint256" },
    ],
  },
  {
    type: "error",
    name: "Config_TransferHookNotSupported",
    inputs: [
      {
        name: "proposedAddress",
        type: "address",
        internalType: "address",
      },
    ],
  },
  { type: "error", name: "Create2EmptyBytecode", inputs: [] },
  { type: "error", name: "Create2FailedDeployment", inputs: [] },
  {
    type: "error",
    name: "Create2InsufficientBalance",
    inputs: [
      { name: "balance", type: "uint256", internalType: "uint256" },
      { name: "needed", type: "uint256", internalType: "uint256" },
    ],
  },
  { type: "error", name: "DefaultOwnerCannotBeZero", inputs: [] },
  { type: "error", name: "ERC1155BatchReceivedCallFailed", inputs: [] },
  { type: "error", name: "ERC1155_MINT_TO_ZERO_ADDRESS", inputs: [] },
  {
    type: "error",
    name: "ERC1967InvalidImplementation",
    inputs: [
      {
        name: "implementation",
        type: "address",
        internalType: "address",
      },
    ],
  },
  { type: "error", name: "ERC1967NonPayable", inputs: [] },
  { type: "error", name: "ERC20TransferSlippage", inputs: [] },
  { type: "error", name: "ETHTransferFailed", inputs: [] },
  {
    type: "error",
    name: "ETHWithdrawFailed",
    inputs: [
      { name: "recipient", type: "address", internalType: "address" },
      { name: "amount", type: "uint256", internalType: "uint256" },
    ],
  },
  { type: "error", name: "FailedInnerCall", inputs: [] },
  { type: "error", name: "FirstMinterAddressZero", inputs: [] },
  {
    type: "error",
    name: "FundsWithdrawInsolvent",
    inputs: [
      { name: "amount", type: "uint256", internalType: "uint256" },
      {
        name: "contractValue",
        type: "uint256",
        internalType: "uint256",
      },
    ],
  },
  { type: "error", name: "IncorrectAmountSent", inputs: [] },
  { type: "error", name: "InvalidAdminAction", inputs: [] },
  { type: "error", name: "InvalidInitialization", inputs: [] },
  {
    type: "error",
    name: "InvalidMerkleProof",
    inputs: [
      { name: "mintTo", type: "address", internalType: "address" },
      {
        name: "merkleProof",
        type: "bytes32[]",
        internalType: "bytes32[]",
      },
      { name: "merkleRoot", type: "bytes32", internalType: "bytes32" },
    ],
  },
  { type: "error", name: "InvalidMintSchedule", inputs: [] },
  {
    type: "error",
    name: "InvalidOwnerForAssociatedZoraSparks",
    inputs: [],
  },
  { type: "error", name: "InvalidPremintVersion", inputs: [] },
  { type: "error", name: "InvalidRecipient", inputs: [] },
  { type: "error", name: "InvalidSignature", inputs: [] },
  { type: "error", name: "InvalidSignatureVersion", inputs: [] },
  {
    type: "error",
    name: "InvalidSigner",
    inputs: [{ name: "magicValue", type: "bytes4", internalType: "bytes4" }],
  },
  { type: "error", name: "InvalidTokenPrice", inputs: [] },
  { type: "error", name: "MintNotYetStarted", inputs: [] },
  {
    type: "error",
    name: "MintWithSparksNotSupportedOnContract",
    inputs: [],
  },
  { type: "error", name: "Mint_InsolventSaleTransfer", inputs: [] },
  { type: "error", name: "Mint_InvalidMintArrayLength", inputs: [] },
  { type: "error", name: "Mint_TokenIDMintNotAllowed", inputs: [] },
  { type: "error", name: "Mint_UnknownCommand", inputs: [] },
  { type: "error", name: "Mint_ValueTransferFail", inputs: [] },
  { type: "error", name: "MinterContractAlreadyExists", inputs: [] },
  { type: "error", name: "MinterContractDoesNotExist", inputs: [] },
  { type: "error", name: "NewOwnerNeedsToBeAdmin", inputs: [] },
  { type: "error", name: "NoTokensTransferred", inputs: [] },
  { type: "error", name: "NoUriForNonexistentToken", inputs: [] },
  { type: "error", name: "NonEthRedemption", inputs: [] },
  {
    type: "error",
    name: "NotARedeemHandler",
    inputs: [{ name: "handler", type: "address", internalType: "address" }],
  },
  { type: "error", name: "NotInitializing", inputs: [] },
  { type: "error", name: "NotSelfCall", inputs: [] },
  { type: "error", name: "NotZoraSparks1155", inputs: [] },
  { type: "error", name: "OnlyTransfersFromZoraSparks", inputs: [] },
  {
    type: "error",
    name: "OwnableInvalidOwner",
    inputs: [{ name: "owner", type: "address", internalType: "address" }],
  },
  {
    type: "error",
    name: "OwnableUnauthorizedAccount",
    inputs: [{ name: "account", type: "address", internalType: "address" }],
  },
  { type: "error", name: "PremintDeleted", inputs: [] },
  { type: "error", name: "PremintExecutorCannotBeZero", inputs: [] },
  {
    type: "error",
    name: "ProtocolRewardsWithdrawFailed",
    inputs: [
      { name: "caller", type: "address", internalType: "address" },
      { name: "recipient", type: "address", internalType: "address" },
      { name: "amount", type: "uint256", internalType: "uint256" },
    ],
  },
  { type: "error", name: "ReentrancyGuardReentrantCall", inputs: [] },
  {
    type: "error",
    name: "Renderer_NotValidRendererContract",
    inputs: [],
  },
  {
    type: "error",
    name: "SafeERC20FailedOperation",
    inputs: [{ name: "token", type: "address", internalType: "address" }],
  },
  { type: "error", name: "SaleEnded", inputs: [] },
  { type: "error", name: "SaleHasNotStarted", inputs: [] },
  {
    type: "error",
    name: "Sale_CannotCallNonSalesContract",
    inputs: [
      {
        name: "targetContract",
        type: "address",
        internalType: "address",
      },
    ],
  },
  { type: "error", name: "TokenAlreadyCreated", inputs: [] },
  { type: "error", name: "TokenDoesNotExist", inputs: [] },
  {
    type: "error",
    name: "TokenIdMismatch",
    inputs: [
      { name: "expected", type: "uint256", internalType: "uint256" },
      { name: "actual", type: "uint256", internalType: "uint256" },
    ],
  },
  {
    type: "error",
    name: "TokenMismatch",
    inputs: [
      {
        name: "storedTokenAddress",
        type: "address",
        internalType: "address",
      },
      {
        name: "expectedTokenAddress",
        type: "address",
        internalType: "address",
      },
    ],
  },
  { type: "error", name: "TokenNotMintable", inputs: [] },
  { type: "error", name: "UUPSUnauthorizedCallContext", inputs: [] },
  {
    type: "error",
    name: "UUPSUnsupportedProxiableUUID",
    inputs: [{ name: "slot", type: "bytes32", internalType: "bytes32" }],
  },
  {
    type: "error",
    name: "UnknownUserAction",
    inputs: [{ name: "selector", type: "bytes4", internalType: "bytes4" }],
  },
  {
    type: "error",
    name: "UpgradeToMismatchedContractName",
    inputs: [
      { name: "expected", type: "string", internalType: "string" },
      { name: "actual", type: "string", internalType: "string" },
    ],
  },
  {
    type: "error",
    name: "UserExceedsMintLimit",
    inputs: [
      { name: "user", type: "address", internalType: "address" },
      { name: "limit", type: "uint256", internalType: "uint256" },
      {
        name: "requestedAmount",
        type: "uint256",
        internalType: "uint256",
      },
    ],
  },
  {
    type: "error",
    name: "UserMissingRoleForToken",
    inputs: [
      { name: "user", type: "address", internalType: "address" },
      { name: "tokenId", type: "uint256", internalType: "uint256" },
      { name: "role", type: "uint256", internalType: "uint256" },
    ],
  },
  { type: "error", name: "WrongValueSent", inputs: [] },
  {
    type: "error",
    name: "premintSignerContractFailedToRecoverSigner",
    inputs: [],
  },
  {
    type: "error",
    name: "premintSignerContractNotAContract",
    inputs: [],
  },
] as const;
