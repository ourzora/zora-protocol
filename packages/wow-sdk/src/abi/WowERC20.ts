export const WowERC20ABI = [
  {
    type: "constructor",
    inputs: [
      {
        name: "_protocolFeeRecipient",
        type: "address",
        internalType: "address",
      },
      {
        name: "_protocolRewards",
        type: "address",
        internalType: "address",
      },
      {
        name: "_weth",
        type: "address",
        internalType: "address",
      },
      {
        name: "_nonfungiblePositionManager",
        type: "address",
        internalType: "address",
      },
      {
        name: "_swapRouter",
        type: "address",
        internalType: "address",
      },
    ],
    stateMutability: "nonpayable",
  },
  {
    type: "receive",
    stateMutability: "payable",
  },
  {
    type: "function",
    name: "MAX_TOTAL_SUPPLY",
    inputs: [],
    outputs: [
      {
        name: "",
        type: "uint256",
        internalType: "uint256",
      },
    ],
    stateMutability: "view",
  },
  {
    type: "function",
    name: "MIN_ORDER_SIZE",
    inputs: [],
    outputs: [
      {
        name: "",
        type: "uint256",
        internalType: "uint256",
      },
    ],
    stateMutability: "view",
  },
  {
    type: "function",
    name: "ORDER_REFERRER_FEE_BPS",
    inputs: [],
    outputs: [
      {
        name: "",
        type: "uint256",
        internalType: "uint256",
      },
    ],
    stateMutability: "view",
  },
  {
    type: "function",
    name: "PLATFORM_REFERRER_FEE_BPS",
    inputs: [],
    outputs: [
      {
        name: "",
        type: "uint256",
        internalType: "uint256",
      },
    ],
    stateMutability: "view",
  },
  {
    type: "function",
    name: "PROTOCOL_FEE_BPS",
    inputs: [],
    outputs: [
      {
        name: "",
        type: "uint256",
        internalType: "uint256",
      },
    ],
    stateMutability: "view",
  },
  {
    type: "function",
    name: "TOKEN_CREATOR_FEE_BPS",
    inputs: [],
    outputs: [
      {
        name: "",
        type: "uint256",
        internalType: "uint256",
      },
    ],
    stateMutability: "view",
  },
  {
    type: "function",
    name: "TOTAL_FEE_BPS",
    inputs: [],
    outputs: [
      {
        name: "",
        type: "uint256",
        internalType: "uint256",
      },
    ],
    stateMutability: "view",
  },
  {
    type: "function",
    name: "WETH",
    inputs: [],
    outputs: [
      {
        name: "",
        type: "address",
        internalType: "address",
      },
    ],
    stateMutability: "view",
  },
  {
    type: "function",
    name: "allowance",
    inputs: [
      {
        name: "owner",
        type: "address",
        internalType: "address",
      },
      {
        name: "spender",
        type: "address",
        internalType: "address",
      },
    ],
    outputs: [
      {
        name: "",
        type: "uint256",
        internalType: "uint256",
      },
    ],
    stateMutability: "view",
  },
  {
    type: "function",
    name: "approve",
    inputs: [
      {
        name: "spender",
        type: "address",
        internalType: "address",
      },
      {
        name: "value",
        type: "uint256",
        internalType: "uint256",
      },
    ],
    outputs: [
      {
        name: "",
        type: "bool",
        internalType: "bool",
      },
    ],
    stateMutability: "nonpayable",
  },
  {
    type: "function",
    name: "balanceOf",
    inputs: [
      {
        name: "account",
        type: "address",
        internalType: "address",
      },
    ],
    outputs: [
      {
        name: "",
        type: "uint256",
        internalType: "uint256",
      },
    ],
    stateMutability: "view",
  },
  {
    type: "function",
    name: "bondingCurve",
    inputs: [],
    outputs: [
      {
        name: "",
        type: "address",
        internalType: "contract BondingCurve",
      },
    ],
    stateMutability: "view",
  },
  {
    type: "function",
    name: "burn",
    inputs: [
      {
        name: "tokensToBurn",
        type: "uint256",
        internalType: "uint256",
      },
    ],
    outputs: [],
    stateMutability: "nonpayable",
  },
  {
    type: "function",
    name: "buy",
    inputs: [
      {
        name: "recipient",
        type: "address",
        internalType: "address",
      },
      {
        name: "refundRecipient",
        type: "address",
        internalType: "address",
      },
      {
        name: "orderReferrer",
        type: "address",
        internalType: "address",
      },
      {
        name: "comment",
        type: "string",
        internalType: "string",
      },
      {
        name: "expectedMarketType",
        type: "uint8",
        internalType: "enum IWow.MarketType",
      },
      {
        name: "minOrderSize",
        type: "uint256",
        internalType: "uint256",
      },
      {
        name: "sqrtPriceLimitX96",
        type: "uint160",
        internalType: "uint160",
      },
    ],
    outputs: [
      {
        name: "",
        type: "uint256",
        internalType: "uint256",
      },
    ],
    stateMutability: "payable",
  },
  {
    type: "function",
    name: "currentExchangeRate",
    inputs: [],
    outputs: [
      {
        name: "",
        type: "uint256",
        internalType: "uint256",
      },
    ],
    stateMutability: "view",
  },
  {
    type: "function",
    name: "decimals",
    inputs: [],
    outputs: [
      {
        name: "",
        type: "uint8",
        internalType: "uint8",
      },
    ],
    stateMutability: "view",
  },
  {
    type: "function",
    name: "getEthBuyQuote",
    inputs: [
      {
        name: "ethOrderSize",
        type: "uint256",
        internalType: "uint256",
      },
    ],
    outputs: [
      {
        name: "",
        type: "uint256",
        internalType: "uint256",
      },
    ],
    stateMutability: "view",
  },
  {
    type: "function",
    name: "getEthSellQuote",
    inputs: [
      {
        name: "ethOrderSize",
        type: "uint256",
        internalType: "uint256",
      },
    ],
    outputs: [
      {
        name: "",
        type: "uint256",
        internalType: "uint256",
      },
    ],
    stateMutability: "view",
  },
  {
    type: "function",
    name: "getTokenBuyQuote",
    inputs: [
      {
        name: "tokenOrderSize",
        type: "uint256",
        internalType: "uint256",
      },
    ],
    outputs: [
      {
        name: "",
        type: "uint256",
        internalType: "uint256",
      },
    ],
    stateMutability: "view",
  },
  {
    type: "function",
    name: "getTokenSellQuote",
    inputs: [
      {
        name: "tokenOrderSize",
        type: "uint256",
        internalType: "uint256",
      },
    ],
    outputs: [
      {
        name: "",
        type: "uint256",
        internalType: "uint256",
      },
    ],
    stateMutability: "view",
  },
  {
    type: "function",
    name: "initialize",
    inputs: [
      {
        name: "_tokenCreator",
        type: "address",
        internalType: "address",
      },
      {
        name: "_platformReferrer",
        type: "address",
        internalType: "address",
      },
      {
        name: "_bondingCurve",
        type: "address",
        internalType: "address",
      },
      {
        name: "_tokenURI",
        type: "string",
        internalType: "string",
      },
      {
        name: "_name",
        type: "string",
        internalType: "string",
      },
      {
        name: "_symbol",
        type: "string",
        internalType: "string",
      },
    ],
    outputs: [],
    stateMutability: "payable",
  },
  {
    type: "function",
    name: "marketType",
    inputs: [],
    outputs: [
      {
        name: "",
        type: "uint8",
        internalType: "enum IWow.MarketType",
      },
    ],
    stateMutability: "view",
  },
  {
    type: "function",
    name: "name",
    inputs: [],
    outputs: [
      {
        name: "",
        type: "string",
        internalType: "string",
      },
    ],
    stateMutability: "view",
  },
  {
    type: "function",
    name: "nonfungiblePositionManager",
    inputs: [],
    outputs: [
      {
        name: "",
        type: "address",
        internalType: "address",
      },
    ],
    stateMutability: "view",
  },
  {
    type: "function",
    name: "onERC721Received",
    inputs: [
      {
        name: "",
        type: "address",
        internalType: "address",
      },
      {
        name: "",
        type: "address",
        internalType: "address",
      },
      {
        name: "",
        type: "uint256",
        internalType: "uint256",
      },
      {
        name: "",
        type: "bytes",
        internalType: "bytes",
      },
    ],
    outputs: [
      {
        name: "",
        type: "bytes4",
        internalType: "bytes4",
      },
    ],
    stateMutability: "view",
  },
  {
    type: "function",
    name: "platformReferrer",
    inputs: [],
    outputs: [
      {
        name: "",
        type: "address",
        internalType: "address",
      },
    ],
    stateMutability: "view",
  },
  {
    type: "function",
    name: "poolAddress",
    inputs: [],
    outputs: [
      {
        name: "",
        type: "address",
        internalType: "address",
      },
    ],
    stateMutability: "view",
  },
  {
    type: "function",
    name: "protocolFeeRecipient",
    inputs: [],
    outputs: [
      {
        name: "",
        type: "address",
        internalType: "address",
      },
    ],
    stateMutability: "view",
  },
  {
    type: "function",
    name: "protocolRewards",
    inputs: [],
    outputs: [
      {
        name: "",
        type: "address",
        internalType: "address",
      },
    ],
    stateMutability: "view",
  },
  {
    type: "function",
    name: "sell",
    inputs: [
      {
        name: "tokensToSell",
        type: "uint256",
        internalType: "uint256",
      },
      {
        name: "recipient",
        type: "address",
        internalType: "address",
      },
      {
        name: "orderReferrer",
        type: "address",
        internalType: "address",
      },
      {
        name: "comment",
        type: "string",
        internalType: "string",
      },
      {
        name: "expectedMarketType",
        type: "uint8",
        internalType: "enum IWow.MarketType",
      },
      {
        name: "minPayoutSize",
        type: "uint256",
        internalType: "uint256",
      },
      {
        name: "sqrtPriceLimitX96",
        type: "uint160",
        internalType: "uint160",
      },
    ],
    outputs: [
      {
        name: "",
        type: "uint256",
        internalType: "uint256",
      },
    ],
    stateMutability: "nonpayable",
  },
  {
    type: "function",
    name: "state",
    inputs: [],
    outputs: [
      {
        name: "",
        type: "tuple",
        internalType: "struct IWow.MarketState",
        components: [
          {
            name: "marketType",
            type: "uint8",
            internalType: "enum IWow.MarketType",
          },
          {
            name: "marketAddress",
            type: "address",
            internalType: "address",
          },
        ],
      },
    ],
    stateMutability: "view",
  },
  {
    type: "function",
    name: "swapRouter",
    inputs: [],
    outputs: [
      {
        name: "",
        type: "address",
        internalType: "address",
      },
    ],
    stateMutability: "view",
  },
  {
    type: "function",
    name: "symbol",
    inputs: [],
    outputs: [
      {
        name: "",
        type: "string",
        internalType: "string",
      },
    ],
    stateMutability: "view",
  },
  {
    type: "function",
    name: "tokenCreator",
    inputs: [],
    outputs: [
      {
        name: "",
        type: "address",
        internalType: "address",
      },
    ],
    stateMutability: "view",
  },
  {
    type: "function",
    name: "tokenURI",
    inputs: [],
    outputs: [
      {
        name: "",
        type: "string",
        internalType: "string",
      },
    ],
    stateMutability: "view",
  },
  {
    type: "function",
    name: "totalSupply",
    inputs: [],
    outputs: [
      {
        name: "",
        type: "uint256",
        internalType: "uint256",
      },
    ],
    stateMutability: "view",
  },
  {
    type: "function",
    name: "transfer",
    inputs: [
      {
        name: "to",
        type: "address",
        internalType: "address",
      },
      {
        name: "value",
        type: "uint256",
        internalType: "uint256",
      },
    ],
    outputs: [
      {
        name: "",
        type: "bool",
        internalType: "bool",
      },
    ],
    stateMutability: "nonpayable",
  },
  {
    type: "function",
    name: "transferFrom",
    inputs: [
      {
        name: "from",
        type: "address",
        internalType: "address",
      },
      {
        name: "to",
        type: "address",
        internalType: "address",
      },
      {
        name: "value",
        type: "uint256",
        internalType: "uint256",
      },
    ],
    outputs: [
      {
        name: "",
        type: "bool",
        internalType: "bool",
      },
    ],
    stateMutability: "nonpayable",
  },
  {
    type: "function",
    name: "uniswapV3SwapCallback",
    inputs: [
      {
        name: "amount0Delta",
        type: "int256",
        internalType: "int256",
      },
      {
        name: "amount1Delta",
        type: "int256",
        internalType: "int256",
      },
      {
        name: "",
        type: "bytes",
        internalType: "bytes",
      },
    ],
    outputs: [],
    stateMutability: "nonpayable",
  },
  {
    type: "event",
    name: "Approval",
    inputs: [
      {
        name: "owner",
        type: "address",
        indexed: true,
        internalType: "address",
      },
      {
        name: "spender",
        type: "address",
        indexed: true,
        internalType: "address",
      },
      {
        name: "value",
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
    name: "Transfer",
    inputs: [
      {
        name: "from",
        type: "address",
        indexed: true,
        internalType: "address",
      },
      {
        name: "to",
        type: "address",
        indexed: true,
        internalType: "address",
      },
      {
        name: "value",
        type: "uint256",
        indexed: false,
        internalType: "uint256",
      },
    ],
    anonymous: false,
  },
  {
    type: "event",
    name: "WowMarketGraduated",
    inputs: [
      {
        name: "tokenAddress",
        type: "address",
        indexed: true,
        internalType: "address",
      },
      {
        name: "poolAddress",
        type: "address",
        indexed: true,
        internalType: "address",
      },
      {
        name: "totalEthLiquidity",
        type: "uint256",
        indexed: false,
        internalType: "uint256",
      },
      {
        name: "totalTokenLiquidity",
        type: "uint256",
        indexed: false,
        internalType: "uint256",
      },
      {
        name: "lpPositionId",
        type: "uint256",
        indexed: false,
        internalType: "uint256",
      },
      {
        name: "marketType",
        type: "uint8",
        indexed: false,
        internalType: "enum IWow.MarketType",
      },
    ],
    anonymous: false,
  },
  {
    type: "event",
    name: "WowTokenBuy",
    inputs: [
      {
        name: "buyer",
        type: "address",
        indexed: true,
        internalType: "address",
      },
      {
        name: "recipient",
        type: "address",
        indexed: true,
        internalType: "address",
      },
      {
        name: "orderReferrer",
        type: "address",
        indexed: true,
        internalType: "address",
      },
      {
        name: "totalEth",
        type: "uint256",
        indexed: false,
        internalType: "uint256",
      },
      {
        name: "ethFee",
        type: "uint256",
        indexed: false,
        internalType: "uint256",
      },
      {
        name: "ethSold",
        type: "uint256",
        indexed: false,
        internalType: "uint256",
      },
      {
        name: "tokensBought",
        type: "uint256",
        indexed: false,
        internalType: "uint256",
      },
      {
        name: "buyerTokenBalance",
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
      {
        name: "marketType",
        type: "uint8",
        indexed: false,
        internalType: "enum IWow.MarketType",
      },
    ],
    anonymous: false,
  },
  {
    type: "event",
    name: "WowTokenCreated",
    inputs: [
      {
        name: "factoryAddress",
        type: "address",
        indexed: true,
        internalType: "address",
      },
      {
        name: "tokenCreator",
        type: "address",
        indexed: true,
        internalType: "address",
      },
      {
        name: "platformReferrer",
        type: "address",
        indexed: false,
        internalType: "address",
      },
      {
        name: "protocolFeeRecipient",
        type: "address",
        indexed: false,
        internalType: "address",
      },
      {
        name: "bondingCurve",
        type: "address",
        indexed: false,
        internalType: "address",
      },
      {
        name: "tokenURI",
        type: "string",
        indexed: false,
        internalType: "string",
      },
      {
        name: "name",
        type: "string",
        indexed: false,
        internalType: "string",
      },
      {
        name: "symbol",
        type: "string",
        indexed: false,
        internalType: "string",
      },
      {
        name: "tokenAddress",
        type: "address",
        indexed: false,
        internalType: "address",
      },
      {
        name: "poolAddress",
        type: "address",
        indexed: false,
        internalType: "address",
      },
    ],
    anonymous: false,
  },
  {
    type: "event",
    name: "WowTokenFees",
    inputs: [
      {
        name: "tokenCreator",
        type: "address",
        indexed: true,
        internalType: "address",
      },
      {
        name: "platformReferrer",
        type: "address",
        indexed: true,
        internalType: "address",
      },
      {
        name: "orderReferrer",
        type: "address",
        indexed: true,
        internalType: "address",
      },
      {
        name: "protocolFeeRecipient",
        type: "address",
        indexed: false,
        internalType: "address",
      },
      {
        name: "tokenCreatorFee",
        type: "uint256",
        indexed: false,
        internalType: "uint256",
      },
      {
        name: "platformReferrerFee",
        type: "uint256",
        indexed: false,
        internalType: "uint256",
      },
      {
        name: "orderReferrerFee",
        type: "uint256",
        indexed: false,
        internalType: "uint256",
      },
      {
        name: "protocolFee",
        type: "uint256",
        indexed: false,
        internalType: "uint256",
      },
    ],
    anonymous: false,
  },
  {
    type: "event",
    name: "WowTokenSell",
    inputs: [
      {
        name: "seller",
        type: "address",
        indexed: true,
        internalType: "address",
      },
      {
        name: "recipient",
        type: "address",
        indexed: true,
        internalType: "address",
      },
      {
        name: "orderReferrer",
        type: "address",
        indexed: true,
        internalType: "address",
      },
      {
        name: "totalEth",
        type: "uint256",
        indexed: false,
        internalType: "uint256",
      },
      {
        name: "ethFee",
        type: "uint256",
        indexed: false,
        internalType: "uint256",
      },
      {
        name: "ethBought",
        type: "uint256",
        indexed: false,
        internalType: "uint256",
      },
      {
        name: "tokensSold",
        type: "uint256",
        indexed: false,
        internalType: "uint256",
      },
      {
        name: "sellerTokenBalance",
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
      {
        name: "marketType",
        type: "uint8",
        indexed: false,
        internalType: "enum IWow.MarketType",
      },
    ],
    anonymous: false,
  },
  {
    type: "event",
    name: "WowTokenTransfer",
    inputs: [
      {
        name: "from",
        type: "address",
        indexed: true,
        internalType: "address",
      },
      {
        name: "to",
        type: "address",
        indexed: true,
        internalType: "address",
      },
      {
        name: "amount",
        type: "uint256",
        indexed: false,
        internalType: "uint256",
      },
      {
        name: "fromTokenBalance",
        type: "uint256",
        indexed: false,
        internalType: "uint256",
      },
      {
        name: "toTokenBalance",
        type: "uint256",
        indexed: false,
        internalType: "uint256",
      },
      {
        name: "totalSupply",
        type: "uint256",
        indexed: false,
        internalType: "uint256",
      },
    ],
    anonymous: false,
  },
  {
    type: "error",
    name: "AddressEmptyCode",
    inputs: [
      {
        name: "target",
        type: "address",
        internalType: "address",
      },
    ],
  },
  {
    type: "error",
    name: "AddressInsufficientBalance",
    inputs: [
      {
        name: "account",
        type: "address",
        internalType: "address",
      },
    ],
  },
  {
    type: "error",
    name: "AddressZero",
    inputs: [],
  },
  {
    type: "error",
    name: "ERC20InsufficientAllowance",
    inputs: [
      {
        name: "spender",
        type: "address",
        internalType: "address",
      },
      {
        name: "allowance",
        type: "uint256",
        internalType: "uint256",
      },
      {
        name: "needed",
        type: "uint256",
        internalType: "uint256",
      },
    ],
  },
  {
    type: "error",
    name: "ERC20InsufficientBalance",
    inputs: [
      {
        name: "sender",
        type: "address",
        internalType: "address",
      },
      {
        name: "balance",
        type: "uint256",
        internalType: "uint256",
      },
      {
        name: "needed",
        type: "uint256",
        internalType: "uint256",
      },
    ],
  },
  {
    type: "error",
    name: "ERC20InvalidApprover",
    inputs: [
      {
        name: "approver",
        type: "address",
        internalType: "address",
      },
    ],
  },
  {
    type: "error",
    name: "ERC20InvalidReceiver",
    inputs: [
      {
        name: "receiver",
        type: "address",
        internalType: "address",
      },
    ],
  },
  {
    type: "error",
    name: "ERC20InvalidSender",
    inputs: [
      {
        name: "sender",
        type: "address",
        internalType: "address",
      },
    ],
  },
  {
    type: "error",
    name: "ERC20InvalidSpender",
    inputs: [
      {
        name: "spender",
        type: "address",
        internalType: "address",
      },
    ],
  },
  {
    type: "error",
    name: "EthAmountTooSmall",
    inputs: [],
  },
  {
    type: "error",
    name: "EthTransferFailed",
    inputs: [],
  },
  {
    type: "error",
    name: "FailedInnerCall",
    inputs: [],
  },
  {
    type: "error",
    name: "InitialOrderSizeTooLarge",
    inputs: [],
  },
  {
    type: "error",
    name: "InsufficientFunds",
    inputs: [],
  },
  {
    type: "error",
    name: "InsufficientLiquidity",
    inputs: [],
  },
  {
    type: "error",
    name: "InvalidInitialization",
    inputs: [],
  },
  {
    type: "error",
    name: "InvalidMarketType",
    inputs: [],
  },
  {
    type: "error",
    name: "MarketAlreadyGraduated",
    inputs: [],
  },
  {
    type: "error",
    name: "MarketNotGraduated",
    inputs: [],
  },
  {
    type: "error",
    name: "NotInitializing",
    inputs: [],
  },
  {
    type: "error",
    name: "OnlyPool",
    inputs: [],
  },
  {
    type: "error",
    name: "OnlyWeth",
    inputs: [],
  },
  {
    type: "error",
    name: "ReentrancyGuardReentrantCall",
    inputs: [],
  },
  {
    type: "error",
    name: "SafeERC20FailedOperation",
    inputs: [
      {
        name: "token",
        type: "address",
        internalType: "address",
      },
    ],
  },
  {
    type: "error",
    name: "SlippageBoundsExceeded",
    inputs: [],
  },
] as const;
