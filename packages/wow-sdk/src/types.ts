import { Address, Transport } from "viem";
import { PublicClient } from "viem";
import { base, baseSepolia, mainnet } from "viem/chains";

export type ChainId =
  | typeof base.id
  | typeof baseSepolia.id
  | typeof mainnet.id;

export type SupportedChain = typeof base | typeof baseSepolia | typeof mainnet;

export type WowTransactionBaseArgs = {
  /**
   * Public client
   */
  publicClient: PublicClient<Transport, SupportedChain>;
  /**
   * Address of the account to use for the transaction
   */
  account: Address;
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
   * Slippage in bps, defaults to 100 bps
   */
  slippageBps?: bigint;
  /**
   * Referrer address
   */
  referrerAddress?: Address;
};
