import {
  Abi,
  Account,
  Address,
  Chain,
  ContractFunctionArgs,
  ContractFunctionName,
  PublicClient as BasePublicClient,
  SimulateContractParameters,
  AbiStateMutability,
} from "viem";

export const makeContractParameters = <
  const abi extends Abi | readonly unknown[],
  stateMutabiliy extends AbiStateMutability,
  functionName extends ContractFunctionName<abi, stateMutabiliy>,
  args extends ContractFunctionArgs<abi, stateMutabiliy, functionName>,
  chainOverride extends Chain | undefined,
  accountOverride extends Account | Address | undefined = undefined,
>(
  args: SimulateContractParameters<
    abi,
    functionName,
    args,
    Chain,
    chainOverride,
    accountOverride
  >,
) => args;

export type PublicClient = Pick<BasePublicClient, "readContract">;

export type ClientConfig = {
  /** The chain that the client is to run on. */
  chainId: number;
  /** Optional public client for the chain.  If not provide, it is created. */
  publicClient: PublicClient;
};

export function setupClient({ chainId, publicClient }: ClientConfig) {
  return {
    chainId,
    publicClient,
  };
}

export function mintRecipientOrAccount({
  mintRecipient,
  minterAccount,
}: {
  mintRecipient?: Address;
  minterAccount: Address | Account;
}): Address {
  return (
    mintRecipient ||
    (typeof minterAccount === "string" ? minterAccount : minterAccount.address)
  );
}

export type Concrete<Type> = {
  [Property in keyof Type]-?: Type[Property];
};
