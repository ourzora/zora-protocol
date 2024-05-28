import { zora } from "viem/chains";
import { http, custom, createPublicClient, createWalletClient } from "viem";

export const chain = zora;

export const publicClient = createPublicClient({
  // this will determine which chain to interact with
  chain: zora,
  transport: http(),
});

export const walletClient = createWalletClient({
  chain: zora,
  transport: custom(window.ethereum!),
});
