import "viem/window";

// ---cut---
import { zoraSepolia } from "viem/chains";
import {
  http,
  custom,
  createPublicClient,
  createWalletClient,
  Chain,
} from "viem";
import {
  createBundlerClient,
  toCoinbaseSmartAccount,
} from "viem/account-abstraction";
import { privateKeyToAccount } from "viem/accounts";

export const chain = zoraSepolia;
export const chainId = zoraSepolia.id;

export const publicClient = createPublicClient({
  // this will determine which chain to interact with
  chain: chain as Chain,
  transport: http(),
});

export const walletClient = createWalletClient({
  chain: chain as Chain,
  transport: custom(window.ethereum!),
});

export const bundlerClient = createBundlerClient({
  client: publicClient,
  transport: http("https://public.pimlico.io/v2/1/rpc"),
});

export const creatorAccount = (await walletClient.getAddresses())[0]!;
export const minterAccount = (await walletClient.getAddresses())[1]!;
export const randomAccount = (await walletClient.getAddresses())[2]!;
export const commenterAccount = (await walletClient.getAddresses())[3]!;
export const sparkerAccount = (await walletClient.getAddresses())[4]!;
export const smartWalletOwner = privateKeyToAccount(
  "0x387c307228bee9b7639f73f3aecb1eebcba919f061ca92cb7001727f5b30a0ec",
);

export const contractAddress1155 = "0xD42557F24034b53e7340A40bb5813eF9Ba88F2b4";
export const tokenId1155 = 3n;

export const smartWalletAccount = await toCoinbaseSmartAccount({
  client: publicClient,
  owners: [],
});
