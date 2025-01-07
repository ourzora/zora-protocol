import { Address, zeroAddress } from "viem";
import ERC20FactoryABI from "./abi/ERC20Factory";

import { addresses } from "./addresses";
import { ChainId } from "./types";

export interface DeployWowTokenArgs {
  chainId: Extract<ChainId, 8453 | 84532>;
  userAddress: Address;
  cid: `ipfs://${string}`;
  name: string;
  symbol: string;
  value?: bigint;
}

export const getDeployTokenParameters = async ({
  chainId,
  userAddress,
  cid,
  name,
  symbol,
  value = 0n,
}: DeployWowTokenArgs) => {
  return {
    account: userAddress,
    address: addresses[chainId].WowFactory as Address,
    abi: ERC20FactoryABI,
    functionName: "deploy" as const,
    args: [userAddress, zeroAddress, cid, name, symbol] as const,
    value,
  } as const;
};
