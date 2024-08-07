import {
  IHttpClient,
  httpClient as defaultHttpClient,
} from "src/apis/http-api-base";
import { paths } from "../apis/generated/allow-list-api-types";
import { Hex } from "viem";
import { AllowList } from "./types";

type AllowListCreateType = paths["/allowlist"]["post"];
type AllowListCreateParameters =
  AllowListCreateType["requestBody"]["content"]["application/json"];
type AllowListCreateResponse = {
  existing?: {
    entries: AllowListCreateParameters["entries"];
    root: string;
    added: string;
  };
  success: boolean;
  root: string;
  associated_id?: string;
};

const ALLOW_LIST_API_BASE = "http://allowlist.zora.co/";
type AllowListAllowedResponse = {
  maxCanMint: number;
  price: string;
  proof: string[];
}[];

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
    entries: allowList.entries.map((entry) => ({
      user: entry.user,
      maxCanMint: entry.maxCanMint,
      price: entry.price.toString(),
    })),
  };

  return (
    await retries(() =>
      post<AllowListCreateResponse>(`${baseUrl}allowlist`, data),
    )
  ).root;
};

function padHex(value: string): Hex {
  if (value.startsWith("0x")) return value as Hex;

  return `0x${value}`;
}

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
    get<AllowListAllowedResponse>(
      `${baseUrl}allowed?user=${address}&root=${merkleRoot}`,
    ),
  );

  const entries = response?.map((x) => ({
    maxCanMint: x.maxCanMint,
    price: BigInt(x.price),
    proof: x.proof.map(padHex),
  }));

  const entry = entries?.sort(
    (a, b) => Number(a.price) - Number(b.price) || b.maxCanMint - a.maxCanMint,
  )[0];

  return {
    accessAllowed: entry && entry?.proof?.length,
    allowListEntry: entry,
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
