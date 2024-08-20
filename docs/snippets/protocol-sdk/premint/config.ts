import "viem/window";

// ---cut---
import { zora } from "viem/chains";
import {
  http,
  custom,
  createPublicClient,
  createWalletClient,
  Address,
  Chain,
} from "viem";

export const chain = zora;
export const chainId = chain.id;

export const publicClient = createPublicClient({
  // this will determine which chain to interact with
  chain: chain as Chain,
  transport: http(),
});

export const walletClient = createWalletClient({
  chain: zora as Chain,
  transport: custom(window.ethereum!),
});

const [creatorAccount, minterAccount] = (await walletClient.getAddresses()) as [
  Address,
  Address,
];

export { creatorAccount, minterAccount };
