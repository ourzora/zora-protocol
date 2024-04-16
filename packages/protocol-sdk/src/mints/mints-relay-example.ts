import {
  Address,
  Hex,
  PublicClient,
  SignTypedDataParameters,
  TypedData,
  WalletClient,
  recoverTypedDataAddress,
} from "viem";
import axios from "axios";
import { paths, TransactionStepItem } from "@reservoir0x/relay-sdk";
import { PermitSafeTransferBatch } from "./mints-contracts";
import {
  mintsEthUnwrapperAndCallerABI,
  mintsEthUnwrapperAndCallerAddress,
} from "@zoralabs/protocol-deployments";
import { makeCallWithEthSafeTransferData } from "./mints-eth-unwrapper-and-caller";

type RelayCallBody =
  paths["/execute/call"]["post"]["requestBody"]["content"]["application/json"];
type RelayCallResponse =
  paths["/execute/call"]["post"]["responses"]["200"]["content"]["application/json"];

const postToRelay = async ({
  data,
}: {
  data: RelayCallBody;
}): Promise<RelayCallResponse> => {
  const request = {
    url: "https://api.relay.link/execute/call",
    method: "post",
    data,
  };

  return (await axios.post(request.url, request.data))
    .data as RelayCallResponse;
};

export const getRelayCall = async ({
  tx,
  depositingAccount,
  originChainId,
  toChainId,
}: {
  tx: {
    to: Address;
    value: bigint;
    data: Hex;
  };
  depositingAccount: Address;
  originChainId: number;
  toChainId: number;
}) => {
  const data: RelayCallBody = {
    user: depositingAccount,
    txs: [
      {
        to: tx.to,
        value: tx.value.toString(),
        data: tx.data,
      },
    ],
    originChainId: originChainId,
    destinationChainId: toChainId,
  };

  const response = await postToRelay({
    data,
  });

  if (response.steps!.length !== 1) {
    throw new Error("should only be a single step.");
  }

  const step = response.steps![0]!;

  if (step.items!.length !== 1) {
    throw new Error("should only be a single item.");
  }

  const stepItem = step.items![0]! as TransactionStepItem;

  const relayCall = stepItem.data!;

  // compute relay fee by subtracting cross-chain call value,
  // from value to send to relay
  const relayFee = BigInt(relayCall.value) - tx.value;

  return {
    relayCall,
    relayFee,
  };
};

// call relay to get the relay call data
// then sign a message with an executing account
// signaling intent to pay the fee later, with a 30 second deadline
export const makeAndSignSponsoredRelayCall = async ({
  originChainId,
  toChainId,
  tx,
  executingAccount,
  walletClient,
}: {
  // the chain to call from (current chain)
  originChainId: keyof typeof mintsEthUnwrapperAndCallerAddress;
  // the chain that the call will be executed on
  toChainId: number;
  // the tx to call on the other chain:
  tx: {
    to: Address;
    value: bigint;
    data: Hex;
  };
  executingAccount: Address;
  walletClient: WalletClient;
}) => {
  // call relay to get the cross-chain calldata
  const { relayCall: relayCall, relayFee: relayFee } = await getRelayCall({
    originChainId,
    toChainId,
    tx,
    depositingAccount: mintsEthUnwrapperAndCallerAddress[originChainId],
  });

  // build call to forward the relay call to the other chain that will be
  // set as the `safeTransferData` in the permit
  const safeTransferData = makeCallWithEthSafeTransferData({
    address: relayCall.to,
    call: relayCall.data,
    value: BigInt(relayCall.value),
  });

  const deadline = BigInt(new Date().getTime() + 30 * 1000);

  // build and sign a message indicating intent to execute this call
  // and pay the relay fee
  const typedData = permitWithAdditionalValueTypedDataDefinition({
    additionalValueToSend: relayFee,
    chainId: originChainId,
    // make a deadline 30 seconds from now:
    deadline,
    safeTransferData,
  });

  // have the account that is to execute the transaction later
  // sign the typed data
  const signature = await walletClient.signTypedData({
    ...typedData,
    account: executingAccount,
  });

  return {
    safeTransferData,
    additionalValueToSend: relayFee,
    signature,
    deadline,
  };
};

// recovers the signer of the sponsored relay call
// and throws an error if the signer is not the executing account
export const validateSponsoredRelayCall = async ({
  safeTransferData,
  additionalValueToSend,
  deadline,
  chainId,
  // account that should ahve signed the message
  executingAccount,
  signature,
}: {
  safeTransferData: Hex;
  additionalValueToSend: bigint;
  deadline: bigint;
  executingAccount: Address;
  chainId: keyof typeof mintsEthUnwrapperAndCallerAddress;
  signature: Hex;
}) => {
  const typedData = permitWithAdditionalValueTypedDataDefinition({
    additionalValueToSend,
    chainId,
    deadline,
    safeTransferData,
  });

  const recovered = await recoverTypedDataAddress({
    ...typedData,
    signature,
  });

  if (recovered !== executingAccount) {
    throw new Error("Invalid signature");
  }
};

// validate that the executingAccount signed a message
// indicating intent to pay the relay fee, and execute the call
export const validateAndExecuteSponsoredRelayCall = async ({
  permit,
  permitSignature,
  additionalValueToSend,
  deadline,
  chainId,
  // account that should ahve signed the message
  executingAccount,
  sponsoredCallSignature,
  walletClient,
  publicClient,
}: {
  permit: PermitSafeTransferBatch;
  permitSignature: Hex;
  // additional value to send to the unwrapper
  additionalValueToSend: bigint;
  // deadline to execute the call
  deadline: bigint;
  // account that is to execute the call, and must have signed the sponsored call
  executingAccount: Address;
  chainId: keyof typeof mintsEthUnwrapperAndCallerAddress;
  // signature of the sponsored call
  sponsoredCallSignature: Hex;
  publicClient: PublicClient;
  walletClient: WalletClient;
}) => {
  if (deadline < BigInt(new Date().getTime())) {
    throw new Error("Deadline has passed");
  }

  await validateSponsoredRelayCall({
    safeTransferData: permit.safeTransferData,
    additionalValueToSend,
    deadline,
    chainId,
    signature: sponsoredCallSignature,
    executingAccount,
  });

  // now we call a payable function on the mints eth unwrapper and caller contract,
  // with the permit and corresponding signature to transfer the mints to the unwrapper,
  // and call relay with the unwrapped value + relay fee.
  // the payable value on this call is the relay fee, which is added to the unwrapped
  // value of the mints and sent to the other chain.
  // any remaining value from the unwrapped MINTs is refunded to the original caller.
  const simulated = await publicClient.simulateContract({
    abi: mintsEthUnwrapperAndCallerABI,
    address: mintsEthUnwrapperAndCallerAddress[chainId],
    functionName: "permitWithAdditionalValue",
    args: [permit, permitSignature],
    account: executingAccount,
    // we must call this functio
    value: additionalValueToSend,
  });

  // wait for the transaction to succeed.
  const hash = await walletClient.writeContract(simulated.request);

  const receipt = await publicClient.waitForTransactionReceipt({
    hash,
  });

  if (receipt.status !== "success") {
    throw new Error("Transaction failed");
  }
};

function makeTypeData<
  const TTypedData extends TypedData | { [key: string]: unknown },
  TPrimaryType extends string,
>(args: Omit<SignTypedDataParameters<TTypedData, TPrimaryType>, "account">) {
  return args;
}

function permitWithAdditionalValueTypedDataDefinition({
  safeTransferData,
  additionalValueToSend,
  deadline,
  chainId,
}: {
  safeTransferData: Hex;
  additionalValueToSend: bigint;
  deadline: bigint;
  chainId: keyof typeof mintsEthUnwrapperAndCallerAddress;
}) {
  return makeTypeData({
    primaryType: "PermitWithAdditionalValue",
    types: {
      PermitWithAdditionalValue: [
        {
          name: "safeTransferData",
          type: "bytes",
        },
        {
          name: "additionalValueToSend",
          type: "uint256",
        },
        {
          name: "deadline",
          type: "uint256",
        },
      ],
    },
    message: {
      safeTransferData,
      additionalValueToSend: additionalValueToSend,
      deadline: deadline,
    },
    domain: {
      chainId,
      name: "Relay",
      version: "1",
      verifyingContract: mintsEthUnwrapperAndCallerAddress[chainId],
    },
  });
}
