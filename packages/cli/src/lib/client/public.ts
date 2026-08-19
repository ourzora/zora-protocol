import {
  CustomTransport,
  PublicClient,
  createPublicClient as viemCreatePublicClient,
} from "viem";
import { base } from "viem/chains";
import { createCliRpcTransport } from "./rpc.js";

/**
 * Creates a viem public client for the base chain
 */
export const createPublicClient = (): PublicClient<
  CustomTransport,
  typeof base
> => {
  const chain = base;
  const transport = createCliRpcTransport(chain.id);

  return viemCreatePublicClient({
    chain,
    transport,
  });
};
