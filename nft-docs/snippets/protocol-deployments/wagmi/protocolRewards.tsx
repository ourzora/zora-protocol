import React from "react";
// ---cut---
import {
  useAccount,
  useChainId,
  useReadContract,
  useWriteContract,
} from "wagmi";
import { Address, formatEther } from "viem";
import {
  protocolRewardsABI,
  protocolRewardsAddress,
} from "@zoralabs/protocol-deployments";

export function App() {
  const chainId = useChainId();
  const { address } = useAccount();

  // read the balance of an account on the ProtocolRewards contract
  const { data: accountBalance, isLoading } = useReadContract({
    abi: protocolRewardsABI,
    address:
      protocolRewardsAddress[chainId as keyof typeof protocolRewardsAddress],
    functionName: "balanceOf",
    args: [address as Address],
  });

  // account that will receive the withdrawn funds
  const recipient = "0x393FF77D5FA5BaB6f6204E6FBA0019D3F25ab133";

  // withdraw amount is half of the balance
  const withdrawAmount = (accountBalance || 0n) / 2n;

  const { data: hash, writeContract, isPending, isError } = useWriteContract();

  async function submit(e: React.FormEvent<HTMLFormElement>) {
    e.preventDefault();
    // write to the withdraw function on the ProtocolRewards contract
    writeContract({
      abi: protocolRewardsABI,
      address:
        protocolRewardsAddress[chainId as keyof typeof protocolRewardsAddress],
      functionName: "withdraw",
      args: [recipient, withdrawAmount],
    });
  }

  if (isLoading) return null;
  return (
    <form onSubmit={submit}>
      <p>Account balance: (data)</p>
      <button type="submit" disabled={isPending || isError}>
        Withdraw {formatEther(withdrawAmount)} ETH
      </button>
      {hash && <div>Transaction Hash: {hash}</div>}
    </form>
  );
}
