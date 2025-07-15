import { IPublicClient } from "src/types";
import { IRewardsGetter } from "./subgraph-rewards-getter";
import { Account, Address } from "viem";
import { getRewardsBalances, withdrawRewards } from "./rewards-queries";

export type WithdrawRewardsParams = {
  // account is the address that is withdrawing the rewards
  account: Address | Account;
  // withdrawFor is the address that is receiving the rewards
  withdrawFor: Address;
  // claimSecondaryRoyalties is an optional flag to claim secondary royalties. Defaults to `true`.
  claimSecondaryRoyalties?: boolean;
};

export type GetRewardsBalancesParams = {
  // The address or account to get the rewards balance for
  account: Address | Account;
};

/**
 * @deprecated Please use functions directly without creating a client.
 * Example: Instead of `new RewardsClient().withdrawRewards()`, use `withdrawRewards()`
 * Import the functions you need directly from their respective modules:
 * import { withdrawRewards, getRewardsBalances } from '@zoralabs/protocol-sdk'
 */
export class RewardsClient {
  // Private properties to store chain ID, public client, and rewards getter
  private readonly publicClient: IPublicClient;
  private readonly rewardsGetter: IRewardsGetter;

  constructor({
    publicClient,
    rewardsGetter,
  }: {
    publicClient: IPublicClient;
    rewardsGetter: IRewardsGetter;
  }) {
    // Initialize the private properties
    this.publicClient = publicClient;
    this.rewardsGetter = rewardsGetter;
  }

  /** Withdraws rewards for a given account */
  async withdrawRewards({
    account,
    withdrawFor,
    claimSecondaryRoyalties,
  }: WithdrawRewardsParams) {
    return await withdrawRewards({
      rewardsGetter: this.rewardsGetter,
      withdrawFor,
      claimSecondaryRoyalties,
      account,
      publicClient: this.publicClient,
    });
  }

  /** Retrieves the rewards balances for a given account */
  async getRewardsBalances(params: GetRewardsBalancesParams) {
    return getRewardsBalances({
      account: params.account,
      publicClient: this.publicClient,
      rewardsGetter: this.rewardsGetter,
    });
  }
}
