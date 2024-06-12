import {
  createPremintClient,
  getDataFromPremintReceipt,
} from "./premint/premint-client";
import { create1155CreatorClient } from "./create/1155-create-helper";
import { createMintClient } from "./mint/mint-client";
import { ClientConfig } from "./utils";
import { IPremintAPI, PremintAPIClient } from "./premint/premint-api-client";
import { SubgraphMintGetter } from "./mint/subgraph-mint-getter";
import { IMintGetter } from "./mint/types";

type PremintClient = ReturnType<typeof createPremintClient>;
type OnChainCreatorClient = ReturnType<typeof create1155CreatorClient>;
type MintClient = ReturnType<typeof createMintClient>;

export type CreatorClient = {
  createPremint: PremintClient["createPremint"];
  updatePremint: PremintClient["updatePremint"];
  deletePremint: PremintClient["deletePremint"];
  create1155: OnChainCreatorClient["createNew1155Token"];
};

export type CollectorClient = {
  getPremint: PremintClient["getPremint"];
  getCollectDataFromPremintReceipt: PremintClient["getDataFromPremintReceipt"];
  mint: MintClient["mint"];
  getMintCosts: MintClient["getMintCosts"];
};

export type CreatorClientConfig = ClientConfig & {
  /** API for submitting and getting premints.  Defaults to the Zora Premint API */
  premintApi?: IPremintAPI;
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
  const premintClient = createPremintClient(clientConfig);

  return {
    createPremint: (p) => premintClient.createPremint(p),
    updatePremint: (p) => premintClient.updatePremint(p),
    deletePremint: (p) => premintClient.deletePremint(p),
    create1155: (p) =>
      create1155CreatorClient(clientConfig).createNew1155Token(p),
  };
}

export type CollectorClientConfig = ClientConfig & {
  /** API for getting premints.  Defaults to the Zora Premint API */
  premintGetter?: IPremintAPI;
  /** API for getting onchain mints.  Defaults to the Zora Creator Subgraph */
  mintGetter?: IMintGetter;
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
    params.premintGetter || new PremintAPIClient(params.chain.id);
  const mintGetterToUse =
    params.mintGetter || new SubgraphMintGetter(params.chain.id);
  const mintClient = createMintClient({
    chain: params.chain,
    publicClient: params.publicClient,
    premintGetter: premintGetterToUse,
    mintGetter: mintGetterToUse,
  });

  return {
    getPremint: (p) =>
      premintGetterToUse.getSignature({
        collectionAddress: p.address,
        uid: p.uid,
      }),
    getCollectDataFromPremintReceipt: (p) =>
      getDataFromPremintReceipt(p, params.chain),
    mint: (p) => mintClient.mint(p),
    getMintCosts: (p) => mintClient.getMintCosts(p),
  };
}
