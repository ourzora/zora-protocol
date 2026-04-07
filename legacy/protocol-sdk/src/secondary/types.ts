import { Address, Account } from "viem";

export type PriceBreakdown = {
  // Price per individual token
  perToken: bigint;
  // Total price for all tokens
  total: bigint;
};

export type QuotePrice = {
  // Price breakdown in wei
  wei: PriceBreakdown;
  // Price breakdown in sparks
  sparks: PriceBreakdown;
  // Function to get price breakdown in USDC
  usdc: () => Promise<{
    // Price per individual token in USDC
    perToken: number;
    // Total price in USDC
    total: number;
  }>;
};

export type GetQuoteOutput = {
  // Amount needed to pay for the swap
  amount: bigint;
  poolBalance: {
    // Balance of ERC20Z tokens in the pool
    erc20z: bigint;
    // Balance of WETH in the pool
    weth: bigint;
  };
  // Detailed price information
  price: QuotePrice;
};

export type BuyWithSlippageInput = {
  // Address of the 1155 contract to interact with
  contract: Address;
  // 1155 token is to buy or sell
  tokenId: bigint;
  // Amount of tokens to buy or sell
  quantity: bigint;
  // Account to use for the transaction
  account: Address | Account;
  // Slippage percentage (optional), defaults to 0.005 (0.5%)
  slippage?: number;
  // Optional recipient address (if different from buyer/seller)
  recipient?: Address;
  // Optional comment to add to the swap
  comment?: string;
};

// Same structure as BuyWithSlippageInput
export type SellWithSlippageInput = BuyWithSlippageInput;

// Base type for shared properties
export type SecondaryInfo = {
  // Boolean if the secondary market has been launched
  secondaryActivated: boolean;
  // The Uniswap pool address
  pool: Address;
  // The ERC20z address
  erc20z: Address;
  // The ERC20Z name
  name: string;
  // The ERC20Z symbol
  symbol: string;
  // Earliest time in seconds a token can be minted
  saleStart: bigint;
  // Latest time in seconds a token can be minted. Gets set after the market countdown has started.
  saleEnd?: bigint;
  // The amount of time after the `minimumMarketEth` is reached until the secondary market can be launched, in seconds.
  marketCountdown?: bigint;
  // minimum quantity of tokens that must have been minted to launch the countdown.
  minimumMintsForCountdown?: bigint;
  // mints so far
  mintCount: bigint;
};
