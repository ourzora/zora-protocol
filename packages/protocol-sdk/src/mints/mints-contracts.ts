import {
  zoraMints1155Config,
  zoraMintsManagerImplABI,
  zoraMintsManagerImplConfig,
  mintsEthUnwrapperAndCallerConfig,
  iUnwrapAndForwardActionABI,
} from "@zoralabs/protocol-deployments";
import { AbiParametersToPrimitiveTypes, ExtractAbiFunction } from "abitype";
import {
  MintArguments as PremintMintArguments,
  PremintConfigV2,
} from "src/premint/contract-types";
import { ContractCreationConfig } from "src/preminter";
import {
  Account,
  Address,
  ContractFunctionRevertedError,
  Hex,
  ReadContractParameters,
  SignTypedDataParameters,
  SimulateContractParameters,
  TypedData,
  decodeErrorResult,
  encodeAbiParameters,
  encodeFunctionData,
  parseAbiParameters,
  zeroAddress,
} from "viem";

export function mintWithEthParams({
  quantity,
  recipient,
  chainId,
  pricePerMint,
  account,
}: {
  quantity: bigint;
  recipient: Address;
  chainId: keyof typeof zoraMints1155Config.address;
  pricePerMint: bigint;
  account: Address | Account;
}): SimulateContractParameters<
  typeof zoraMintsManagerImplConfig.abi,
  "mintWithEth"
> {
  return {
    abi: zoraMintsManagerImplConfig.abi,
    address: zoraMintsManagerImplConfig.address[chainId],
    functionName: "mintWithEth",
    args: [quantity, recipient],
    value: pricePerMint * quantity,
    account,
  };
}

const getPaidMintValue = (quantities: bigint[], pricePerMint?: bigint) => {
  if (!pricePerMint || pricePerMint === 0n) return;

  return quantities.reduce((a, b) => a + b, 0n) * pricePerMint;
};

export const fixedPriceMinterMinterArguments = ({
  mintRecipient,
}: {
  mintRecipient: Address;
}) => encodeAbiParameters(parseAbiParameters("address"), [mintRecipient]);

export const mintsBalanceOfAccountParams = ({
  account,
  chainId,
}: {
  account: Address;
  chainId: keyof typeof zoraMints1155Config.address;
}): ReadContractParameters<
  typeof zoraMints1155Config.abi,
  "balanceOfAccount"
> => ({
  abi: zoraMints1155Config.abi,
  address: zoraMints1155Config.address[chainId],
  functionName: "balanceOfAccount",
  args: [account],
});

type CollectOnManagerParams = {
  tokenIds: bigint[];
  quantities: bigint[];
  zoraCreator1155Contract: Address;
  zoraCreator1155TokenId: bigint;
  minter: Address;
  mintArguments: CollectMintArguments;
};

export const encodeCollectOnManager = ({
  zoraCreator1155Contract,
  minter,
  zoraCreator1155TokenId,
  mintArguments,
}: CollectOnManagerParams) =>
  encodeFunctionData({
    abi: zoraMintsManagerImplConfig.abi,
    functionName: "collect",
    args: [
      zoraCreator1155Contract,
      minter,
      zoraCreator1155TokenId,
      mintArguments,
    ],
  });

export function collectWithMintsParams({
  tokenIds,
  quantities,
  chainId,
  pricePerToken,
  account,
  ...rest
}: {
  paidMintValue?: bigint;
  chainId: keyof typeof zoraMints1155Config.address;
  pricePerToken?: bigint;
  account: Address | Account;
} & CollectOnManagerParams): SimulateContractParameters<
  typeof zoraMints1155Config.abi,
  "transferBatchToManagerAndCall"
> {
  const call = encodeCollectOnManager({
    tokenIds,
    quantities,
    ...rest,
  });

  return {
    abi: zoraMints1155Config.abi,
    address: zoraMints1155Config.address[chainId],
    functionName: "transferBatchToManagerAndCall",
    args: [tokenIds, quantities, call],
    value: getPaidMintValue(quantities, pricePerToken),
    account,
  };
}

export const collectWithMintsTypedDataDefinition = ({
  tokenIds,
  quantities,
  chainId,
  account,
  nonce,
  deadline,
  ...rest
}: {
  chainId: keyof typeof zoraMints1155Config.address;
  nonce: bigint;
  deadline: bigint;
  account: Account | Address;
} & CollectOnManagerParams) => {
  const safeTransferData = encodeCollectOnManager({
    tokenIds,
    quantities,
    ...rest,
  });

  return makePermitTransferBatchAndTypeData({
    tokenIds,
    quantities,
    chainId,
    account,
    nonce,
    deadline,
    safeTransferData,
    // will safe transfer to manager contract before doing the
    // collect operation
    to: zoraMintsManagerImplConfig.address[chainId],
  });
};

export const collectPremintWithMintsTypedDataDefinition = ({
  tokenIds,
  quantities,
  chainId,
  account,
  nonce,
  deadline,
  ...rest
}: {
  chainId: keyof typeof zoraMints1155Config.address;
  nonce: bigint;
  deadline: bigint;
  account: Account | Address;
} & PremintOnManagerParams) => {
  const safeTransferData = encodePremintOnManager({
    ...rest,
  });

  return makePermitTransferBatchAndTypeData({
    tokenIds,
    quantities,
    chainId,
    account,
    nonce,
    deadline,
    safeTransferData,
    // will safe transfer to manager contract before doing the
    // collect operation
    to: zoraMintsManagerImplConfig.address[chainId],
  });
};

function makePermitTransferBatchAndTypeData({
  tokenIds,
  quantities,
  chainId,
  account,
  to,
  nonce,
  deadline,
  safeTransferData,
}: {
  tokenIds: bigint[];
  quantities: bigint[];
  chainId: keyof typeof zoraMints1155Config.address;
  nonce: bigint;
  deadline: bigint;
  account: Account | Address;
  to: Address;
  safeTransferData: Hex;
}) {
  const permit: PermitSafeTransferBatch = {
    owner: typeof account === "string" ? account : account.address,
    to,
    tokenIds,
    quantities,
    deadline,
    nonce,
    safeTransferData,
  };

  const typedData = permitBatchTypedDataDefinition({
    chainId,
    permit,
    account,
  });

  return {
    permit,
    typedData,
  };
}

function makePermitTransferTypeData({
  tokenId,
  quantity,
  chainId,
  account,
  to,
  nonce,
  deadline,
  safeTransferData,
}: {
  tokenId: bigint;
  quantity: bigint;
  chainId: keyof typeof zoraMints1155Config.address;
  nonce: bigint;
  deadline: bigint;
  account: Account | Address;
  to: Address;
  safeTransferData: Hex;
}) {
  const permit: PermitSafeTransfer = {
    owner: typeof account === "string" ? account : account.address,
    to,
    tokenId,
    quantity,
    deadline,
    nonce,
    safeTransferData,
  };

  const typedData = permitTransferTypedDataDefinition({
    chainId,
    permit,
    account,
  });

  return {
    permit,
    typedData,
  };
}

type PremintOnManagerParams = {
  tokenIds: bigint[];
  quantities: bigint[];
  contractCreationConfig: ContractCreationConfig;
  premintConfig: PremintConfigV2;
  premintSignature: Hex;
  mintArguments: PremintMintArguments;
  signerContract?: Address;
};

export const encodePremintOnManager = ({
  contractCreationConfig,
  premintConfig,
  premintSignature,
  mintArguments,
  signerContract = zeroAddress,
}: Omit<PremintOnManagerParams, "tokenIds" | "quantities">) =>
  encodeFunctionData({
    abi: zoraMintsManagerImplConfig.abi,
    functionName: "collectPremintV2",
    args: [
      contractCreationConfig,
      premintConfig,
      premintSignature,
      mintArguments,
      signerContract,
    ],
  });

export function collectPremintV2WithMintsParams({
  tokenIds,
  quantities,
  pricePerToken,
  account,
  chainId,
  ...rest
}: {
  pricePerToken?: bigint;
  chainId: keyof typeof zoraMints1155Config.address;
  account: Address | Account;
} & PremintOnManagerParams): SimulateContractParameters<
  typeof zoraMints1155Config.abi,
  "transferBatchToManagerAndCall"
> {
  const call = encodePremintOnManager({
    ...rest,
  });

  return {
    abi: zoraMints1155Config.abi,
    address: zoraMints1155Config.address[chainId],
    functionName: "transferBatchToManagerAndCall",
    args: [tokenIds, quantities, call],
    value: getPaidMintValue(quantities, pricePerToken),
    account,
  };
}

export type PermitSafeTransferBatch = AbiParametersToPrimitiveTypes<
  ExtractAbiFunction<
    typeof zoraMints1155Config.abi,
    "permitSafeTransferBatch"
  >["inputs"]
>[0];

export type PermitSafeTransfer = AbiParametersToPrimitiveTypes<
  ExtractAbiFunction<
    typeof zoraMints1155Config.abi,
    "permitSafeTransfer"
  >["inputs"]
>[0];

export type CollectMintArguments = AbiParametersToPrimitiveTypes<
  ExtractAbiFunction<typeof zoraMintsManagerImplConfig.abi, "collect">["inputs"]
>[3];
// export type PermitTransferBatchToManager = ExtractAbiFunction<

function makeTypeData<
  const TTypedData extends TypedData | { [key: string]: unknown },
  TPrimaryType extends string,
>(args: SignTypedDataParameters<TTypedData, TPrimaryType>) {
  return args;
}

export function permitBatchTypedDataDefinition({
  permit,
  chainId,
  account,
}: {
  permit: PermitSafeTransferBatch;
  chainId: keyof typeof zoraMints1155Config.address;
  account: Account | Address;
}) {
  return makeTypeData({
    primaryType: "Permit",
    types: {
      Permit: [
        {
          name: "owner",
          type: "address",
        },
        {
          name: "to",
          type: "address",
        },
        {
          name: "tokenIds",
          type: "uint256[]",
        },
        {
          name: "quantities",
          type: "uint256[]",
        },
        {
          name: "safeTransferData",
          type: "bytes",
        },
        {
          name: "nonce",
          type: "uint256",
        },
        {
          name: "deadline",
          type: "uint256",
        },
      ],
    },
    message: permit,
    domain: {
      chainId,
      name: "Mints",
      version: "1",
      verifyingContract: zoraMints1155Config.address[chainId],
    },
    // signing account must be permit owner
    account,
  });
}

export function permitTransferTypedDataDefinition({
  permit,
  chainId,
  account,
}: {
  permit: PermitSafeTransfer;
  chainId: keyof typeof zoraMints1155Config.address;
  account: Account | Address;
}) {
  return makeTypeData({
    primaryType: "PermitSafeTransfer",
    types: {
      PermitSafeTransfer: [
        {
          name: "owner",
          type: "address",
        },
        {
          name: "to",
          type: "address",
        },
        {
          name: "tokenId",
          type: "uint256",
        },
        {
          name: "quantity",
          type: "uint256",
        },
        {
          name: "safeTransferData",
          type: "bytes",
        },
        {
          name: "nonce",
          type: "uint256",
        },
        {
          name: "deadline",
          type: "uint256",
        },
      ],
    },
    message: permit,
    domain: {
      chainId,
      name: "Mints",
      version: "1",
      verifyingContract: zoraMints1155Config.address[chainId],
    },
    // signing account must be permit owner
    account,
  });
}

export const permitTransferBatchToManagerAndCallParams = ({
  permit,
  chainId,
  signature,
}: {
  permit: PermitSafeTransferBatch;
  chainId: keyof typeof zoraMints1155Config.address;
  signature: Hex;
}) => {
  const result: SimulateContractParameters<
    typeof zoraMints1155Config.abi,
    "permitSafeTransferBatch"
  > = {
    abi: zoraMints1155Config.abi,
    address: zoraMints1155Config.address[chainId],
    functionName: "permitSafeTransferBatch",
    args: [permit, signature],
  };

  return result;
};

export const safeTransferAndUnwrapTypedDataDefinition = ({
  chainId,
  tokenId,
  quantity,
  from,
  addressToCall,
  functionToCall,
  valueToSend,
  deadline,
  nonce,
}: {
  tokenId: bigint;
  quantity: bigint;
  chainId: keyof typeof zoraMints1155Config.address;
  // mints will be transferred from this address,
  // must match the callers address
  from: Address | Account;
  addressToCall: Address;
  functionToCall: Hex;
  valueToSend: bigint;
  deadline: bigint;
  nonce: bigint;
}) => {
  // this is the call that the wrapper will call
  const callArgument = encodeFunctionData({
    abi: iUnwrapAndForwardActionABI,
    functionName: "callWithEth",
    args: [addressToCall, functionToCall, valueToSend],
  });

  return makePermitTransferTypeData({
    account: from,
    chainId,
    deadline,
    tokenId,
    quantity,
    safeTransferData: callArgument,
    to: mintsEthUnwrapperAndCallerConfig.address[chainId],
    nonce,
  });
};

export const safeTransferBatchAndUnwrapTypedDataDefinition = ({
  chainId,
  tokenIds,
  quantities,
  from,
  addressToCall,
  functionToCall,
  valueToSend,
  deadline,
  nonce,
}: {
  tokenIds: bigint[];
  quantities: bigint[];
  chainId: keyof typeof zoraMints1155Config.address;
  // mints will be transferred from this address,
  // must match the callers address
  from: Address | Account;
  addressToCall: Address;
  functionToCall: Hex;
  valueToSend: bigint;
  deadline: bigint;
  nonce: bigint;
}) => {
  // this is the call that the wrapper will call
  const callArgument = encodeFunctionData({
    abi: iUnwrapAndForwardActionABI,
    functionName: "callWithEth",
    args: [addressToCall, functionToCall, valueToSend],
  });

  return makePermitTransferBatchAndTypeData({
    account: from,
    chainId,
    deadline,
    tokenIds,
    quantities,
    safeTransferData: callArgument,
    to: mintsEthUnwrapperAndCallerConfig.address[chainId],
    nonce,
  });
};

export const safeTransferAndUnwrapEthParams = ({
  chainId,
  tokenIds,
  quantities,
  from,
  addressToCall,
  functionToCall,
  valueToSend,
}: {
  tokenIds: bigint[];
  quantities: bigint[];
  chainId: keyof typeof zoraMints1155Config.address;
  // mints will be transferred from this address,
  // must match the callers address
  from: Address | Account;
  addressToCall: Address;
  functionToCall: Hex;
  valueToSend: bigint;
}) => {
  // this is the encoded calldata for the eth unwrapper to
  // read and execute.
  // for valueToSend, whatever is remaining will be refunded
  // to the recipient.
  const callArgument = encodeFunctionData({
    abi: iUnwrapAndForwardActionABI,
    functionName: "callWithEth",
    args: [addressToCall, functionToCall, valueToSend],
  });

  const result: SimulateContractParameters<
    typeof zoraMints1155Config.abi,
    "safeBatchTransferFrom"
  > = {
    abi: zoraMints1155Config.abi,
    functionName: "safeBatchTransferFrom",
    address: zoraMints1155Config.address[chainId],
    args: [
      typeof from === "string" ? from : from.address,
      // the mints will be transferred to this address, which
      // will burn/redeem their eth value
      mintsEthUnwrapperAndCallerConfig.address[chainId],
      // token ids to transfer/burn/unwrap - must be eth based tokens
      tokenIds,
      // quantities to transfer/burn/unwrap
      quantities,
      // this is the safeTransferData - which gets forwarded to the eth transferrer
      callArgument,
    ],
    // the account whos mints will be transferred from
    account: from,
  };

  return result;
};

export function decodeCallFailedError(error: ContractFunctionRevertedError) {
  if (error.data?.errorName !== "CallFailed")
    throw new Error("Not a CallFailed error");

  const internalErrorData = error.data?.args?.[0] as Hex;

  return decodeErrorResult({
    abi: zoraMintsManagerImplABI,
    data: internalErrorData,
  });
}
