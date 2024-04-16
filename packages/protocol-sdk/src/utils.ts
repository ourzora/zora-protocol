import {
  Abi,
  Account,
  Address,
  Chain,
  ContractFunctionArgs,
  ContractFunctionName,
  SimulateContractParameters,
} from "viem";

export const makeSimulateContractParamaters = <
  const abi extends Abi | readonly unknown[],
  functionName extends ContractFunctionName<abi, "nonpayable" | "payable">,
  args extends ContractFunctionArgs<
    abi,
    "nonpayable" | "payable",
    functionName
  >,
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
