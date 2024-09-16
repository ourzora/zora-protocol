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
  // Slippage percentage (optional), defaults to 0.0005 (0.5%)
  slippage?: number;
  // Optional recipient address (if different from buyer/seller)
  recipient?: Address;
};

// Same structure as BuyWithSlippageInput
export type SellWithSlippageInput = BuyWithSlippageInput;

export type SecondaryInfo = {
  // Whether the secondary market is activated
  secondaryActivated: boolean;
  // Address of the liquidity pool for the erc20z to WETH pair
  pool: Address;
  // Address of the erc20z token
  erc20z: Address;
  // Timestamp when the secondary market will end
  saleEnd?: bigint;
};
