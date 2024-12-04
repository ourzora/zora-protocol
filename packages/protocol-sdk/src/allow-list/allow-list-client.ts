import {
  IHttpClient,
  httpClient as defaultHttpClient,
} from "src/apis/http-api-base";
import { Address, decodeAbiParameters, encodeAbiParameters, Hex } from "viem";
import { AllowList } from "./types";

type AllowListCreateParameters = {
  unhashedLeaves: Hex[];
  leafTypeDescriptor: string[];
  packedEncoding: boolean;
};

type AllowListCreateResponse = {
  merkleRoot: Hex;
};

type LanyardResponse = {
  proof: Hex[];
  unhashedLeaf: Hex;
};

const ALLOWLIST_ABI_PARAMETERS = [
  { type: "address", name: "user" },
  { type: "uint256", name: "maxCanMint" },
  { type: "uint256", name: "price" },
];

const ALLOW_LIST_API_BASE = "https://lanyard.org/api/v1/";
type AllowlistEntry = {
  user: Address;
  maxCanMint: number;
  price: bigint;
  priceDecimal: number;
  proof: Hex[];
};

function getZoraEntry(
  lanyardResponse: LanyardResponse | undefined,
  root: string | undefined,
): AllowlistEntry | undefined {
  if (!lanyardResponse || !root) {
    return;
  }

  try {
    const [user, maxCanMint, price] = decodeAbiParameters(
      ALLOWLIST_ABI_PARAMETERS,
      lanyardResponse.unhashedLeaf,
    );

    return {
      user: user as Address,
      maxCanMint: Number(maxCanMint),
      price: price as bigint,
      // This won't realistically overflow.
      priceDecimal: Number(price),
      proof: lanyardResponse.proof,
    };
  } catch (e: any) {
    console.error(e);
    // Silently error here because the format is unexpected
    return;
  }
}

export const createAllowList = async ({
  allowList,
  httpClient = defaultHttpClient,
  baseUrl = ALLOW_LIST_API_BASE,
}: {
  allowList: AllowList;
  httpClient?: IHttpClient;
  baseUrl?: string;
}) => {
  const { post, retries } = httpClient;

  const data: AllowListCreateParameters = {
    unhashedLeaves: allowList.entries.map((entry) =>
      encodeAbiParameters(ALLOWLIST_ABI_PARAMETERS, [
        entry.user,
        entry.maxCanMint,
        entry.price,
      ]),
    ),
    leafTypeDescriptor: ["address", "uint256", "uint256"],
    packedEncoding: false,
  };

  return (
    await retries(() => post<AllowListCreateResponse>(`${baseUrl}tree`, data))
  ).merkleRoot;
};

export const getAllowListEntry = async ({
  merkleRoot,
  address,
  httpClient = defaultHttpClient,
  baseUrl = ALLOW_LIST_API_BASE,
}: {
  merkleRoot: string;
  httpClient?: IHttpClient;
  address: string;
  baseUrl?: string;
}) => {
  const { retries, get } = httpClient;

  const response = await retries(() =>
    get<LanyardResponse>(
      `${baseUrl}proof?address=${address}&root=${merkleRoot}`,
    ),
  );

  const allowListEntry = getZoraEntry(response, merkleRoot);

  return {
    accessAllowed: allowListEntry && allowListEntry?.proof?.length,
    allowListEntry,
  };
};

export interface IAllowListClient {
  createAllowList: typeof createAllowList;
  getAllowListEntry: typeof getAllowListEntry;
}

export const defaultAllowListClient = (): IAllowListClient => ({
  createAllowList,
  getAllowListEntry,
});
