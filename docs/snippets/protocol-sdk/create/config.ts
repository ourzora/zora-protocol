import "viem/window";

// ---cut---
import { zora } from "viem/chains";
import {
  http,
  custom,
  createPublicClient,
  createWalletClient,
  Chain,
} from "viem";

export const chain = zora;
export const chainId = zora.id;

export const publicClient = createPublicClient({
  // this will determine which chain to interact with
  chain: chain as Chain,
  transport: http(),
});

export const walletClient = createWalletClient({
  chain: chain as Chain,
  transport: custom(window.ethereum!),
});

export const creatorAccount = (await walletClient.getAddresses())[0]!;
export const minterAccount = (await walletClient.getAddresses())[1]!;
export const randomAccount = (await walletClient.getAddresses())[2]!;
