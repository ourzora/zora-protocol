import {
  PremintClient,
  getDataFromPremintReceipt,
} from "./premint/premint-client";
import { Create1155Client } from "./create/1155-create-helper";
import { MintClient } from "./mint/mint-client";
import { ClientConfig } from "./utils";
import { IPremintAPI, PremintAPIClient } from "./premint/premint-api-client";
import { SubgraphMintGetter } from "./mint/subgraph-mint-getter";
import { IOnchainMintGetter } from "./mint/types";
import {
  IContractGetter,
  SubgraphContractGetter,
} from "./create/contract-getter";
import { RewardsClient } from "./rewards/rewards-client";
import {
  IRewardsGetter,
  SubgraphRewardsGetter,
} from "./rewards/subgraph-rewards-getter";
import { SecondaryClient } from "./secondary/secondary-client";

export type CreatorClient = {
  createPremint: PremintClient["createPremint"];
  updatePremint: PremintClient["updatePremint"];
  deletePremint: PremintClient["deletePremint"];
  create1155: Create1155Client["createNew1155"];
  create1155OnExistingContract: Create1155Client["createNew1155OnExistingContract"];
  withdrawRewards: RewardsClient["withdrawRewards"];
  getRewardsBalances: RewardsClient["getRewardsBalances"];
};

export type CollectorClient = {
  getPremint: PremintClient["getPremint"];
  getCollectDataFromPremintReceipt: PremintClient["getDataFromPremintReceipt"];
  mint: MintClient["mint"];
  getMintCosts: MintClient["getMintCosts"];
  getToken: MintClient["get"];
  getTokensOfContract: MintClient["getOfContract"];
  buy1155OnSecondary: SecondaryClient["buy1155OnSecondary"];
  sell1155OnSecondary: SecondaryClient["sell1155OnSecondary"];
  getSecondaryInfo: SecondaryClient["getSecondaryInfo"];
};

export type CreatorClientConfig = ClientConfig & {
  /** API for submitting and getting premints.  Defaults to the Zora Premint API */
  premintApi?: IPremintAPI;
  contractGetter?: IContractGetter;
  rewardsGetter?: IRewardsGetter;
};

/**
 * Builds the sdk for creating/managing 1155 contracts and tokens
 *
 * @param clientConfig - Configuration for the client {@link CreatorClientConfig}
 * @returns CreatorClient {@link CreatorClient}
 * */
export function createCreatorClient(
  clientConfig: CreatorClientConfig,
): CreatorClient {
  const premintClient = new PremintClient({
    chainId: clientConfig.chainId,
    publicClient: clientConfig.publicClient,
    premintApi:
      clientConfig.premintApi || new PremintAPIClient(clientConfig.chainId),
  });

  const create1155CreatorClient = new Create1155Client({
    chainId: clientConfig.chainId,
    publicClient: clientConfig.publicClient,
    contractGetter:
      clientConfig.contractGetter ||
      new SubgraphContractGetter(clientConfig.chainId),
  });

  const rewardsClient = new RewardsClient({
    chainId: clientConfig.chainId,
    publicClient: clientConfig.publicClient,
    rewardsGetter:
      clientConfig.rewardsGetter ||
      new SubgraphRewardsGetter(clientConfig.chainId),
  });

  return {
    createPremint: (p) => premintClient.createPremint(p),
    updatePremint: (p) => premintClient.updatePremint(p),
    deletePremint: (p) => premintClient.deletePremint(p),
    create1155: (p) => create1155CreatorClient.createNew1155(p),
    create1155OnExistingContract: (p) =>
      create1155CreatorClient.createNew1155OnExistingContract(p),
    getRewardsBalances: (p) => rewardsClient.getRewardsBalances(p),
    withdrawRewards: (p) => rewardsClient.withdrawRewards(p),
  };
}

export type CollectorClientConfig = ClientConfig & {
  /** API for getting premints.  Defaults to the Zora Premint API */
  premintGetter?: IPremintAPI;
  /** API for getting onchain mints.  Defaults to the Zora Creator Subgraph */
  mintGetter?: IOnchainMintGetter;
};

/**
 * Builds the sdk for collecting Premints, 1155, and 721 tokens.
 *
 * @param clientConfig - Configuration for the client {@link CollectorClientConfig}
 * @returns CollectorClient {@link CollectorClient}
 */
export function createCollectorClient(
  params: CollectorClientConfig,
): CollectorClient {
  const premintGetterToUse =
    params.premintGetter || new PremintAPIClient(params.chainId);
  const mintGetterToUse =
    params.mintGetter || new SubgraphMintGetter(params.chainId);
  const mintClient = new MintClient({
    publicClient: params.publicClient,
    premintGetter: premintGetterToUse,
    mintGetter: mintGetterToUse,
    chainId: params.chainId,
  });
  const secondaryClient = new SecondaryClient({
    publicClient: params.publicClient,
    chainId: params.chainId,
  });

  return {
    getPremint: (p) =>
      premintGetterToUse.get({
        collectionAddress: p.address,
        uid: p.uid,
      }),
    getCollectDataFromPremintReceipt: (p) =>
      getDataFromPremintReceipt(p, params.chainId),
    getToken: (p) => mintClient.get(p),
    getTokensOfContract: (p) => mintClient.getOfContract(p),
    mint: (p) => mintClient.mint(p),
    getMintCosts: (p) => mintClient.getMintCosts(p),
    buy1155OnSecondary: (p) => secondaryClient.buy1155OnSecondary(p),
    sell1155OnSecondary: (p) => secondaryClient.sell1155OnSecondary(p),
    getSecondaryInfo: (p) => secondaryClient.getSecondaryInfo(p),
  };
}
