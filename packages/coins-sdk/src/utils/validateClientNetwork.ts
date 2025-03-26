import { PublicClient } from "viem";
import { base, baseSepolia } from "viem/chains";

export const validateClientNetwork = (
  publicClient: PublicClient<any, any, any, any>,
) => {
  const clientChainId = publicClient?.chain?.id;
  if (clientChainId === base.id) {
    return;
  }
  if (clientChainId === baseSepolia.id) {
    return;
  }

  throw new Error(
    "Client network needs to be base or baseSepolia for current coin deployments.",
  );
};
