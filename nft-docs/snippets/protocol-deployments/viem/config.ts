import { zora } from "viem/chains";
import { http, createPublicClient, createWalletClient, Address } from "viem";

export const publicClient = createPublicClient({
  // this will determine which chain to interact with
  chain: zora,
  transport: http(),
});

export const walletClient = createWalletClient({
  chain: zora,
  transport: http(),
});

const [account] = (await walletClient.getAddresses()) as [Address];

export { account };
