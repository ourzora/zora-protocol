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
export const chainId = zora.id;

export const publicClient = createPublicClient({
  // this will determine which chain to interact with
  chain: zora as Chain,
  transport: http(),
});

export const walletClient = createWalletClient({
  chain: zora,
  transport: custom(window.ethereum!),
});

const [minterAccount] = (await walletClient.getAddresses()) as [Address];

export { minterAccount };
