import { Address, PublicClient, WalletClient, zeroAddress } from "viem";
import ERC20FactoryABI from "./abi/ERC20Factory";

import { addresses } from "./addresses";

interface DeployWowTokenArgs {
  chainId: 8453 | 84532;
  userAddress: Address;
  cid: `ipfs://${string}`;
  name: string;
  symbol: string;
  value?: bigint;
}

export const deployWowToken = async (
  args: DeployWowTokenArgs,
  publicClient: PublicClient,
  walletClient: WalletClient,
) => {
  const { chainId, userAddress, cid, name, symbol, value = 0n } = args;
  const { request } = await publicClient.simulateContract({
    account: userAddress,
    address: addresses[chainId].WowFactory as Address,
    abi: ERC20FactoryABI,
    functionName: "deploy",
    args: [userAddress, zeroAddress, cid, name, symbol],
    value,
  });
  return await walletClient.writeContract(request);
};
