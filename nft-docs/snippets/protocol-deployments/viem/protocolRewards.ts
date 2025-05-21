import { publicClient, walletClient, account } from "./config";
import {
  protocolRewardsABI,
  protocolRewardsAddress,
} from "@zoralabs/protocol-deployments";

// read the balance of an account on the ProtocolRewards contract
const accountBalance = await publicClient.readContract({
  abi: protocolRewardsABI,
  address:
    protocolRewardsAddress[
      publicClient.chain.id as keyof typeof protocolRewardsAddress
    ],
  functionName: "balanceOf",
  args: [account],
});

// account that will receive the withdrawn funds
const recipient = "0x393FF77D5FA5BaB6f6204E6FBA0019D3F25ab133";

// withdraw amount is half of the balance
const withdrawAmount = (accountBalance || 0n) / 2n;

// write to the withdraw function on the ProtocolRewards contract to withdraw funds
// to the recipient
await walletClient.writeContract({
  abi: protocolRewardsABI,
  address:
    protocolRewardsAddress[
      publicClient.chain.id as keyof typeof protocolRewardsAddress
    ],
  functionName: "withdraw",
  args: [recipient, withdrawAmount],
  // account to execute the transaction
  account,
});
