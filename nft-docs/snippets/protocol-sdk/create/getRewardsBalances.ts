import { useAccount, usePublicClient } from "wagmi";
import { getRewardsBalances } from "@zoralabs/protocol-sdk";

// use wagmi hooks to get the chainId, publicClient, and account
const publicClient = usePublicClient()!;
const { address } = useAccount();

// get the rewards balance for the given account
const rewardsBalance = await getRewardsBalances({
  account: address!,
  publicClient,
});

// get the protocol rewards balance of the account in ETH
const protocolRewardsBalance = rewardsBalance.protocolRewards;
// get the secondary roylaties balance in ETH
const secondaryRoyaltiesBalanceEth = rewardsBalance.secondaryRoyalties.eth;
// get the secondary royalties balance for an erc20 token
const secondaryRoyaltiesBalancesByErc20 =
  rewardsBalance.secondaryRoyalties.erc20;

console.log({
  protocolRewardsBalance,
  secondaryRoyaltiesBalanceEth,
  secondaryRoyaltiesBalancesByErc20,
});
