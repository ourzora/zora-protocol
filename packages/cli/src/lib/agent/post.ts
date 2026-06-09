import { Buffer } from "node:buffer";
import { getAddress, type Address, type LocalAccount } from "viem";
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
  /** The deployed content-coin address, when minted (resolved from the submit logs). */
  coinAddress?: Address;
}

const NAME_ABI = [
  {
    type: "function",
    name: "name",
    stateMutability: "view",
    inputs: [],
    outputs: [{ type: "string" }],
  },
] as const;

/**
 * Find the deployed coin among the submit logs by matching its on-chain name.
 *
 * Best-effort: makes up to one `readContract` (`name()`) call per unique log
 * address, and returns undefined if none matches (the API omits `logs`, the log
 * shape is unexpected, or the names differ). Callers treat a missing result as
 * "no post URL" — the post itself already succeeded, so the absent link is a
 * skipped convenience, not an error.
 */
async function findDeployedCoin(
  client: ChainClient,
  logs: unknown[],
  expectedName: string,
): Promise<Address | undefined> {
  const seen = new Set<string>();
  for (const log of logs) {
    const address = (log as { address?: string })?.address;
    if (!address || seen.has(address.toLowerCase())) continue;
    seen.add(address.toLowerCase());
    try {
      const name = await client.readContract({
        address: getAddress(address),
        abi: NAME_ABI,
        functionName: "name",
      });
      if (name === expectedName) return getAddress(address);
    } catch {
      // not a coin / no name() — skip
    }
  }
  // No log matched — intentionally silent: the post already succeeded, and the
  // coin URL is a best-effort convenience the caller simply omits when absent.
  return undefined;
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
        // NOTE: `adminAddressess` is misspelled ON PURPOSE. The Zora BFF's zod
        // schema for this mutation keys on that exact (mis)spelling and rejects
        // the request ("expected array, received undefined") if it's renamed to
        // the correct `adminAddresses`. Verified against the live endpoint — do
        // not "fix" the spelling.
        adminAddressess: [...owners, smartWallet],
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
  const coinAddress = finalize.submitted
    ? await findDeployedCoin(
        client,
        finalize.submitted.logs ?? [],
        card.greeting,
      )
    : undefined;
  return {
    ...finalize,
    greeting: card.greeting,
    ticker: card.ticker,
    imageUri,
    contractUri,
    coinAddress,
  };
}
