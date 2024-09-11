import { IPublicClient } from "src/types";
import { IRewardsGetter } from "./subgraph-rewards-getter";
import { Account, Address } from "viem";
import { getRewardsBalance, withdrawRewards } from "./rewards-queries";

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

export class RewardsClient {
  // Private properties to store chain ID, public client, and rewards getter
  private readonly chainId: number;
  private readonly publicClient: IPublicClient;
  private readonly rewardsGetter: IRewardsGetter;

  constructor({
    chainId,
    publicClient,
    rewardsGetter,
  }: {
    chainId: number;
    publicClient: IPublicClient;
    rewardsGetter: IRewardsGetter;
  }) {
    // Initialize the private properties
    this.chainId = chainId;
    this.publicClient = publicClient;
    this.rewardsGetter = rewardsGetter;
  }

  /** Withdraws rewards for a given account */
  async withdrawRewards({
    account,
    withdrawFor,
    claimSecondaryRoyalties,
  }: WithdrawRewardsParams) {
    return {
      parameters: await withdrawRewards({
        chainId: this.chainId,
        rewardsGetter: this.rewardsGetter,
        withdrawFor,
        claimSecondaryRoyalties,
        account,
      }),
    };
  }

  /** Retrieves the rewards balances for a given account */
  async getRewardsBalances(params: GetRewardsBalancesParams) {
    return getRewardsBalance({
      account: params.account,
      chainId: this.chainId,
      publicClient: this.publicClient,
      rewardsGetter: this.rewardsGetter,
    });
  }
}
