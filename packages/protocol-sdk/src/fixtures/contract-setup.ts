import { Address, Chain, PublicClient, WalletClient } from "viem";
import { simulateAndWriteContractWithRetries } from "src/anvil";
import { createCreatorClient } from "src/sdk";
import {
  demoContractMetadataURI,
  demoTokenMetadataURI,
} from "src/create/1155-create-helper.test";
import { SubgraphMintGetter } from "src/mint/subgraph-mint-getter";
import { SubgraphRewardsGetter } from "../rewards/subgraph-rewards-getter";

export async function setupContractAndToken({
  chain,
  publicClient,
  creatorAccount,
  walletClient,
}: {
  chain: Chain;
  publicClient: PublicClient;
  creatorAccount: Address;
  walletClient: WalletClient;
}) {
  const rewardsGetter = new SubgraphRewardsGetter(chain.id);
  const creatorClient = createCreatorClient({
    chainId: chain.id,
    publicClient,
    rewardsGetter,
  });

  const mintGetter = new SubgraphMintGetter(chain.id);
  // create a new 1155 contract

  const { contractAddress, parameters, newTokenId } =
    await creatorClient.create1155({
      contract: {
        uri: demoContractMetadataURI,
        name: `Test 1155-${Math.round(Math.random() * 100_000_000_000)}`,
      },
      token: {
        tokenMetadataURI: demoTokenMetadataURI,
      },
      account: creatorAccount,
    });

  await simulateAndWriteContractWithRetries({
    parameters,
    walletClient,
    publicClient,
  });

  return {
    creatorClient,
    contractAddress,
    newTokenId,
    mintGetter,
    rewardsGetter,
  };
}
