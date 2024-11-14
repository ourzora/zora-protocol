import {
  protocolRewardsABI,
  protocolRewardsAddress,
  erc20ZRoyaltiesABI,
  erc20ZRoyaltiesAddress,
  wethAddress,
} from "@zoralabs/protocol-deployments";
import { makeContractParameters, PublicClient } from "src/utils";
import { PublicClient as PublicClientWithMulticall } from "viem";
import { Account, Address, encodeFunctionData, parseAbi } from "viem";
import { IRewardsGetter } from "./subgraph-rewards-getter";
import {
  multicall3Abi,
  multicall3Address,
  Multicall3Call3,
} from "src/apis/multicall3";

// Aggregates unclaimed fees and separates ETH from other ERC20 tokens
function aggregateUnclaimedFees(
  unclaimedFees: readonly {
    token0: `0x${string}`;
    token1: `0x${string}`;
    token0Amount: bigint;
    token1Amount: bigint;
  }[],
  wethAddress: Address,
) {
  let ethBalance = 0n;
  // Aggregate unclaimed fees by token address
  const unclaimedFeesAggregate = unclaimedFees.reduce(
    (acc, fee) => {
      const addFee = (token: `0x${string}`, amount: bigint) => {
        if (token === wethAddress) {
          ethBalance += amount;
        } else if (acc[token]) {
          acc[token] += amount;
        } else {
          acc[token] = amount;
        }
      };
      // Apply 75% fee to each token amount
      addFee(fee.token0, (fee.token0Amount * 75n) / 100n);
      addFee(fee.token1, (fee.token1Amount * 75n) / 100n);
      return acc;
    },
    {} as Record<string, bigint>,
  );

  return {
    eth: (ethBalance * 75n) / 100n, // Apply 75% fee to ETH balance
    erc20: unclaimedFeesAggregate,
  };
}

// Define the return type for getRewardsBalance
type RewardsBalance = {
  // The total balance, in eth of protocol rewards
  protocolRewards: bigint;
  // The secondary royalties balance.
  secondaryRoyalties: {
    // The balance, in eth, of secondary royalties
    eth: bigint;
    // The balance, aggregated by erc20 address, of secondary royalties
    erc20: Record<Address, bigint>;
  };
};

export const getRewardsBalance = async ({
  account, // The account to check rewards for (Address or Account object)
  publicClient, // The public client for making blockchain queries
  chainId, // The ID of the blockchain network
  rewardsGetter, // Interface for getting ERC20Z tokens for a creator
}: {
  account: Account | Address;
  publicClient: PublicClient;
  chainId: number;
  rewardsGetter: IRewardsGetter;
}): Promise<RewardsBalance> => {
  const address = typeof account === "string" ? account : account.address;
  const erc20ZsAndSecondaryActivated = await rewardsGetter.getErc20ZzForCreator(
    { address },
  );

  const validErc20Zs = erc20ZsAndSecondaryActivated
    .filter(({ secondaryActivated }) => secondaryActivated)
    .map(({ erc20z }) => erc20z);

  // Perform multicall to get protocol rewards balance and unclaimed fees
  const result = await (publicClient as PublicClientWithMulticall).multicall({
    contracts: [
      {
        address:
          protocolRewardsAddress[
            chainId as keyof typeof protocolRewardsAddress
          ],
        abi: protocolRewardsABI,
        functionName: "balanceOf",
        args: [address],
      },
      {
        address:
          erc20ZRoyaltiesAddress[
            chainId as keyof typeof erc20ZRoyaltiesAddress
          ],
        abi: erc20ZRoyaltiesABI,
        functionName: "getUnclaimedFeesBatch",
        args: [validErc20Zs],
      },
    ],
    multicallAddress: multicall3Address,
    allowFailure: false,
  });

  const protocolRewardsBalance = result[0];

  const wethAddressForChain = wethAddress[chainId as keyof typeof wethAddress];

  // Aggregate unclaimed fees
  const unclaimedFeesAggregate = aggregateUnclaimedFees(
    result[1],
    wethAddressForChain,
  );

  return {
    protocolRewards: protocolRewardsBalance,
    secondaryRoyalties: unclaimedFeesAggregate,
  };
};

export const withdrawProtocolRewards = ({
  withdrawFor,
  chainId,
}: {
  // Account to execute the transaction
  withdrawFor: Address;
  chainId: number;
}) => {
  return makeContractParameters({
    abi: protocolRewardsABI,
    functionName: "withdrawFor",
    address:
      protocolRewardsAddress[chainId as keyof typeof protocolRewardsAddress],
    args: [withdrawFor, 0n],
  });
};

const makeClaimSecondaryRoyaltiesCalls = async ({
  claimFor,
  chainId,
  rewardsGetter,
}: {
  claimFor: Address;
  chainId: number;
  rewardsGetter: IRewardsGetter;
}) => {
  const erc20ZsAndSecondaryActivated = await rewardsGetter.getErc20ZzForCreator(
    { address: claimFor },
  );

  const erc20z = erc20ZsAndSecondaryActivated
    .filter(({ secondaryActivated }) => secondaryActivated)
    .map(({ erc20z }) => erc20z);

  const royaltiesAddress =
    erc20ZRoyaltiesAddress[chainId as keyof typeof erc20ZRoyaltiesAddress];

  if (erc20z.length === 0) {
    return [];
  }

  return erc20z.map((erc20z) => ({
    target: royaltiesAddress,
    callData: encodeFunctionData({
      abi: erc20ZRoyaltiesABI,
      functionName: "claimFor",
      args: [erc20z],
    }),
    allowFailure: false,
  }));
};

export async function withdrawSecondaryRoyalties({
  claimFor,
  chainId,
  rewardsGetter,
}: {
  claimFor: Address;
  chainId: number;
  rewardsGetter: IRewardsGetter;
}) {
  const calls = await makeClaimSecondaryRoyaltiesCalls({
    claimFor,
    chainId,
    rewardsGetter,
  });

  return makeContractParameters({
    abi: multicall3Abi,
    functionName: "aggregate3",
    address: multicall3Address,
    args: [calls],
  });
}

// Extract protocol rewards withdrawal call creation
const createProtocolRewardsCall = (
  chainId: number,
  withdrawFor: Address,
): Multicall3Call3 => ({
  target:
    protocolRewardsAddress[chainId as keyof typeof protocolRewardsAddress],
  callData: encodeFunctionData({
    abi: protocolRewardsABI,
    functionName: "withdrawFor",
    args: [withdrawFor, 0n],
  }),
  allowFailure: false,
});

// Extract multicall parameters creation
const createMulticallParameters = (
  calls: Multicall3Call3[],
  account: Address | Account,
) =>
  makeContractParameters({
    abi: parseAbi(multicall3Abi),
    functionName: "aggregate3",
    address: multicall3Address,
    args: [calls],
    account,
  });

// Main withdrawRewards function
export const withdrawRewards = async ({
  account,
  withdrawFor,
  claimSecondaryRoyalties = true,
  chainId,
  rewardsGetter,
}: {
  account: Address | Account;
  withdrawFor: Address;
  claimSecondaryRoyalties?: boolean;
  chainId: number;
  rewardsGetter: IRewardsGetter;
}) => {
  if (!claimSecondaryRoyalties) {
    return {
      ...withdrawProtocolRewards({ chainId, withdrawFor }),
      account,
    };
  }

  const protocolRewardsCall = createProtocolRewardsCall(chainId, withdrawFor);
  const secondaryRoyaltiesCalls = await makeClaimSecondaryRoyaltiesCalls({
    chainId,
    claimFor: withdrawFor,
    rewardsGetter,
  });

  const allCalls = [protocolRewardsCall, ...secondaryRoyaltiesCalls];
  return createMulticallParameters(allCalls, account);
};
