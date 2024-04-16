import {
  iUnwrapAndForwardActionABI,
  mintsEthUnwrapperAndCallerAddress,
  zoraMints1155Config,
} from "@zoralabs/protocol-deployments";
import { Account, Address, Hex, encodeFunctionData } from "viem";
import { makePermitTransferBatchAndTypeData } from "./mints-contracts";

type CallWithEthParams = {
  address: Address;
  call: Hex;
  value: bigint;
};

/**
 * Build safeTransferData for the eth unwrapper and caller to call another
 * contract with eth unwrapped from MINTs.
 * @param addressToCall - the address of the contract to call
 * @param functionToCall - the function to call on the contract
 * @param valueToSend - the value to send to the contract
 */
export const makeCallWithEthSafeTransferData = ({
  address: addressToCall,
  call: functionToCall,
  value: valueToSend,
}: CallWithEthParams) =>
  encodeFunctionData({
    abi: iUnwrapAndForwardActionABI,
    functionName: "callWithEth",
    args: [addressToCall, functionToCall, valueToSend],
  });

/**
 * Makes a permit and corresponding typed data definition for unwrapping the eth value
 * of mints and forwarding it to another contract with a call.  Any eth that is not forwarded
 * is refunded to the owner of the MINTs.
 * @param chainId - the id of the chain that the mints are on.
 * @param tokenIds - the token ids of the MINTs to unwrap
 * @param quantities - the quantities of each token id of the MINTs to unwrap
 * @param from - the address that owns the MINTs - this must be the address to sign the permit.
 * @param addressToCall - the address of the contract to call with the unwrapped eth.
 * @param callWithEth - the target contract, function, and value to call with the unwrapped eth.  Any eth not forwarded is refunded to the owner of the MINTs.
 * @param safeTransferData - the safeTransferData to use for the call.  If not provided, it will be generated from callWithEth.
 * @returns a permit and corresponding typed data definition to sign.
 */
export const unwrapAndForwardEthPermitAndTypedDataDefinition = ({
  chainId,
  tokenIds,
  quantities,
  from,
  callWithEth,
  safeTransferData,
  deadline,
  nonce,
}: {
  tokenIds: bigint[];
  quantities: bigint[];
  chainId: keyof typeof zoraMints1155Config.address;
  // mints will be transferred from this address; must match the callers address
  from: Address | Account;
  deadline: bigint;
  nonce: bigint;
} & (
  | {
      callWithEth: CallWithEthParams;
      safeTransferData?: undefined;
    }
  | {
      callWithEth?: undefined;
      safeTransferData: Hex;
    }
)) =>
  makePermitTransferBatchAndTypeData({
    mintsOwner: from,
    chainId,
    deadline,
    tokenIds,
    quantities,
    safeTransferData:
      safeTransferData || makeCallWithEthSafeTransferData(callWithEth),
    to: mintsEthUnwrapperAndCallerAddress[chainId],
    nonce,
  });
