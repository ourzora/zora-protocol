import { zora } from "wagmi/chains";
import { http, createPublicClient, Chain } from "viem";

export const chain = zora;

export const publicClient = createPublicClient({
  chain: chain as Chain,
  transport: http(),
});
