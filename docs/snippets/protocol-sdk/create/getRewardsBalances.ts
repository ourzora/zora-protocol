import { useAccount, useChainId, usePublicClient } from "wagmi";
import { createCreatorClient } from "@zoralabs/protocol-sdk";

// use wagmi hooks to get the chainId, publicClient, and account
const chainId = useChainId();
const publicClient = usePublicClient()!;
const { address } = useAccount();

const creatorClient = createCreatorClient({ chainId, publicClient });

// get the rewards balance for the given account
const rewardsBalance = await creatorClient.getRewardsBalances({
  account: address!,
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
