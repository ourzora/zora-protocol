import { Address } from "viem";
import { WalletClient } from "viem";
import { PublicClient } from "viem";
import { base, baseSepolia, mainnet } from "viem/chains";

export type ChainId =
  | typeof base.id
  | typeof baseSepolia.id
  | typeof mainnet.id;

export type WowTransactionBaseArgs = {
  /**
   * Supported chain id
   */
  chainId: ChainId;
  /**
   * Public client
   */
  publicClient: PublicClient;
  /**
   * Wallet client
   */
  walletClient: WalletClient;
  /**
   * Token address of the Wow token
   */
  tokenAddress: Address;
  /**
   * User address of the buyer
   */
  tokenRecipientAddress: Address;

  /**
   * Uniswap pool address of the Wow token
   * If none is provided, the pool address will be fetched from the token contract,
   * passing in a pool address will skip this fetch
   */
  poolAddress?: Address;
  /**
   * Comment for the transaction
   */
  comment?: string;
  /**
   * Original token quote
   * If the quote has changed since the consumer fetched it, a SlippageExceededError will be thrown
   */
  originalTokenQuote: bigint;
  /**
   * Slippage in bps
   */
  slippageBps: bigint;
  /**
   * Referrer address
   */
  referrerAddress?: Address;
};
