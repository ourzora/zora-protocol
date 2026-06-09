import { Buffer } from "node:buffer";
import type { Address, LocalAccount } from "viem";
import {
  BASE_CHAIN_ID,
  ipfsUpload,
  trpcRequest,
  type ChainClient,
} from "./zora-client.js";
import { pickFirstPostCard, type FirstPostCard } from "./first-post-cards.js";
import type { RawUserOperation } from "./user-op.js";
import { signSimulateSubmit, type FinalizeResult } from "./submit.js";

export interface FirstPostResult extends FinalizeResult {
  greeting: string;
  ticker: string;
  imageUri: string;
  contractUri: string;
}

/**
 * Publish the agent's first post — a Zora content coin whose media is a bundled
 * greeting card. Uploads the card image + metadata to IPFS, builds the (sponsored)
 * content-coin UserOp, then signs + submits it exactly like the creator coin.
 * With `dryRun`, the card + metadata are uploaded but nothing is minted.
 */
export async function createFirstPost(params: {
  token: string;
  account: LocalAccount;
  client: ChainClient;
  smartWallet: Address;
  owners: Address[];
  dryRun: boolean;
  /** Override the random card (e.g. for tests). */
  card?: FirstPostCard;
}): Promise<FirstPostResult> {
  const { token, account, client, smartWallet, owners, dryRun } = params;
  const card = params.card ?? pickFirstPostCard();
  const png = Buffer.from(card.pngBase64, "base64");

  const imageUri = await ipfsUpload(token, "first-post.png", png, "image/png");
  const metadata = {
    name: card.greeting,
    description: card.greeting,
    symbol: card.ticker,
    image: imageUri,
    content: { uri: imageUri, mime: "image/png" },
  };
  const contractUri = await ipfsUpload(
    token,
    "metadata.json",
    Buffer.from(JSON.stringify(metadata)),
    "application/json",
  );

  const { data, error } = await trpcRequest(
    token,
    "create.createCreateERC20UserOperationV2",
    {
      json: {
        chainId: BASE_CHAIN_ID,
        ownerAddress: smartWallet.toLowerCase(),
        adminAddresses: [...owners, smartWallet],
        name: card.greeting,
        ticker: card.ticker,
        contractURI: contractUri,
        value: "0",
        customPairCurrencyAddress: null,
        disableGasSponsorship: false,
      },
      meta: { values: { value: ["bigint"] } },
    },
  );
  if (!data) {
    throw new Error(
      `createCreateERC20UserOperationV2 failed: ${error ?? "no UserOp returned"}`,
    );
  }

  const finalize = await signSimulateSubmit({
    token,
    account,
    client,
    raw: data as RawUserOperation,
    dryRun,
  });
  return {
    ...finalize,
    greeting: card.greeting,
    ticker: card.ticker,
    imageUri,
    contractUri,
  };
}
