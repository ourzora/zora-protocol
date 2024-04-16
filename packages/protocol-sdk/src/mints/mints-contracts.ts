import {
  zoraMints1155Config,
  zoraMintsManagerImplABI,
  zoraMintsManagerImplAddress,
  zoraMintsManagerImplConfig,
} from "@zoralabs/protocol-deployments";
import { AbiParametersToPrimitiveTypes, ExtractAbiFunction } from "abitype";
import {
  MintArguments as PremintMintArguments,
  PremintConfigV2,
} from "src/premint/contract-types";
import { ContractCreationConfig } from "src/preminter";
import { makeSimulateContractParamaters } from "src/utils";
import {
  Account,
  Address,
  ContractFunctionRevertedError,
  Hex,
  PublicClient,
  ReadContractParameters,
  SignTypedDataParameters,
  TypedData,
  decodeErrorResult,
  encodeFunctionData,
  zeroAddress,
} from "viem";

const addressOrAccountAddress = (address: Address | Account) =>
  typeof address === "string" ? address : address.address;

/**
 * Constructs the parameters to mint a MINT with ETH on the ZoraMintsManager based on the price of the currently mintable ETH token.
 *
 * @param quantity - The number of mints to be created.
 * @param recipient - The address that will receive the mints.
 * @param chainId - The ID of the blockchain network where the contract is deployed.
 * @param pricePerMint - The price for each mint in ETH. Must match the price of the defualt mintable ETH token.
 * @param account - The address or account that is creating the mints.
 *
 * @returns The parameters for the `mintWithEth` function call, including the ABI, contract address, function name, arguments, value, and account.
 */
export const mintWithEthParams = ({
  quantity,
  recipient,
  chainId,
  pricePerMint,
  account,
}: {
  quantity: bigint;
  recipient?: Address;
  chainId: keyof typeof zoraMints1155Config.address;
  pricePerMint: bigint;
  account: Address | Account;
}) =>
  makeSimulateContractParamaters({
    abi: zoraMintsManagerImplConfig.abi,
    address: zoraMintsManagerImplConfig.address[chainId],
    functionName: "mintWithEth",
    args: [quantity, recipient || addressOrAccountAddress(account)],
    value: pricePerMint * quantity,
    account,
  });

const getPaidMintValue = (quantities: bigint[], pricePerMint?: bigint) => {
  if (!pricePerMint || pricePerMint === 0n) return;

  return quantities.reduce((a, b) => a + b, 0n) * pricePerMint;
};

/**
 * Constructs the parameters to get the total mints balance of an account on the ZoraMints1155 contract.
 * @param account - The address of the account to check the balance of.
 * @returns The parameters for the `balanceOfAccount` function call, including the ABI, contract address, function name, and arguments.
 */
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

/**
 * Constructs parameters to collect a Zora Creator 1155 token using MINTs an account owns.
 * @param tokenIds - The MINT token ids to use to collect the Zora Creator 1155 token with.
 * @param quantities - The quantities of each MINT token to use to collect the Zora Creator 1155 token with.  The sum of these quantities will be the total quantity of the Zora Creator 1155 token collected.
 * @param chainId - The ID of the chain where the MINTs are to be used
 * @param paidMintPricePerToken - If this is for a paid mint, this is the price in eth per each token to be collected
 * @param account - The account that will be executing the transaction, and whos MINTs will be used
 * @param mintArguments - The minterArguments, mintRewardsRecipients, and mintComment
 * @param minter - The IMinter1155 used by the Zora Creator 1155 contract to mint the tokens
 * @param zoraCreator1155Contract - The Zora Creator 1155 contract address to mint tokens on
 * @param zoraCreator1155TokenId - The token id on the Zora Creator contract to mint
 */
export function collectWithMintsParams({
  tokenIds,
  quantities,
  chainId,
  paidMintPricePerToken,
  account,
  mintArguments,
  minter,
  zoraCreator1155Contract,
  zoraCreator1155TokenId,
}: {
  paidMintValue?: bigint;
  chainId: keyof typeof zoraMints1155Config.address;
  paidMintPricePerToken?: bigint;
  account: Address | Account;
} & CollectOnManagerParams) {
  const call = encodeCollectOnManager({
    tokenIds,
    quantities,
    zoraCreator1155Contract,
    zoraCreator1155TokenId,
    minter,
    mintArguments,
  });

  return makeSimulateContractParamaters({
    abi: zoraMints1155Config.abi,
    address: zoraMints1155Config.address[chainId],
    functionName: "transferBatchToManagerAndCall",
    args: [tokenIds, quantities, call],
    // if it is a paid mint, the aadditional value will be sent to the manager contract and forwarded to the creator 1155 contract
    // for the paid mint cost.
    value: getPaidMintValue(quantities, paidMintPricePerToken),
    account,
  });
}

type PermitTransferBatchParameters = {
  tokenIds: bigint[];
  quantities: bigint[];
  chainId: keyof typeof zoraMints1155Config.address;
  nonce: bigint;
  deadline: bigint;
  mintsOwner: Account | Address;
  to: Address;
  safeTransferData: Hex;
};

/**
 * Get the current price to mint a MINT with ETH
 * @param publicClient - The public client to use to read the contract
 */
export function getMintsEthPrice({
  publicClient,
}: {
  publicClient: PublicClient;
}) {
  const chainId = publicClient.chain?.id as
    | keyof typeof zoraMintsManagerImplAddress
    | undefined;
  // if chain id is not in the zoraMintsManagerImplAddress, throw an error:
  if (!chainId || !zoraMintsManagerImplAddress[chainId]) {
    throw new Error(`Chain id ${chainId} not supported`);
  }

  return publicClient.readContract({
    abi: zoraMintsManagerImplABI,
    address: zoraMintsManagerImplAddress[chainId],
    functionName: "getEthPrice",
  });
}

/**
 * Builds the permit data and typed data to sign for permitting a batch transfer of MINTs.
 * @param tokenIds - The token ids to transfer.
 * @param quantities - The quantities of each token to transfer.
 * @param chainId - The ID of the chain where the MINTs are to be used
 * @param mintsOwner - The account that owns the MINTs to be transferred (and the account that is to sign the permit)
 * @param to - The address to transfer the MINTs to.
 * @param nonce - Random nonce of the permit.
 * @param deadline - The deadline of the permit.
 * @param safeTransferData - The data to be sent with the transfer.
 * @returns permit and corresponding typed data to sign.
 */
export function makePermitTransferBatchAndTypeData({
  tokenIds,
  quantities,
  chainId,
  mintsOwner,
  to,
  nonce,
  deadline,
  safeTransferData,
}: PermitTransferBatchParameters) {
  const permit: PermitSafeTransferBatch = {
    owner: typeof mintsOwner === "string" ? mintsOwner : mintsOwner.address,
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
    account: mintsOwner,
  });

  return {
    permit,
    typedData,
  };
}

/**
 * Builds the permit data and typed data to sign for permitting a transfer of a MINTs for a single MINTs token id
 * @param tokenId - The token id to transfer.
 * @param quantity - The quantity of the token to transfer.
 * @param chainId - The ID of the chain where the MINTs are to be used
 * @param mintsOwner - The account that owns the MINTs to be transferred (and the account that is to sign the permit)
 * @param to - The address to transfer the MINTs to.
 * @param nonce - Random nonce of the permit.
 * @param deadline - The deadline of the permit.
 * @param safeTransferData - The data to be sent with the transfer.
 * @returns
 */
export function makePermitTransferTypeData({
  tokenId,
  quantity,
  chainId,
  mintsOwner,
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
  mintsOwner: Account | Address;
  to: Address;
  safeTransferData: Hex;
}) {
  const permit: PermitSafeTransfer = {
    owner: typeof mintsOwner === "string" ? mintsOwner : mintsOwner.address,
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
    account: mintsOwner,
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

const encodePremintOnManager = ({
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

/**
 * Builds a permit, and corresponding typed data to sign
 * to collect a premint or non-premint Using the mints an account owns.
 * @param mintsOwner - The account that owns the MINTs to be transferred (and the account that is to sign the permit)
 * @param chainId - The ID of the chain where the MINTs are to be used
 * @param deadline - The deadline of the permit.
 * @param nonce - Random nonce of the permit.
 * @param tokenIds - The mint token ids to to use
 * @param quantities - The quantities of each token to use to collect the Zora Creator 1155 token with.  The sum of these quantities will be the total quantity of the Zora Creator 1155 token collected.
 * @param premint - If this is for a premint, the configuration of the premint to collect
 * @param collect - If this is for a non-premint, the configuration of the non-premint to collect
 * @returns
 */
export const makePermitToCollectPremintOrNonPremint = ({
  mintsOwner,
  chainId,
  deadline,
  tokenIds,
  // this quantity of MINTs will be used to collect premint
  // and will be burned.  This same quantity is the quantity of
  // premint to collect.
  quantities,
  nonce,
  premint,
  collect,
}: Omit<PermitTransferBatchParameters, "to" | "safeTransferData"> &
  (
    | {
        premint: Parameters<typeof encodePremintOnManager>[0];
        collect?: undefined;
      }
    | {
        premint?: undefined;
        collect: Parameters<typeof encodeCollectOnManager>[0];
      }
  )) => {
  let safeTransferData: Hex;

  if (premint) {
    safeTransferData = encodePremintOnManager(premint);
  } else if (collect) {
    safeTransferData = encodeCollectOnManager(collect);
  } else {
    throw new Error("Invalid operation");
  }

  return makePermitTransferBatchAndTypeData({
    tokenIds,
    quantities,
    chainId,
    mintsOwner,
    nonce,
    deadline,
    safeTransferData,
    to: zoraMintsManagerImplConfig.address[chainId],
  });
};

/**
 * Constructs the parameters to collect a premint using MINTs an account owns.
 * @param tokenIds - The MINT token ids to use to collect the premint with.
 * @param quantities - The quantities of each MINT token to use to collect the premint with.  The sum of these quantities will be the total quantity of the premint collected.
 * @param chainId - The ID of the chain where the MINTs are to be used
 * @param account - The account which's MINTs will be used to collect the premint.
 * @param contractCreationConfig - The premint contract creation config
 * @param premintConfig - The premint config
 * @param premintSignature - The signature for the premint
 * @param mintArguments - The minterArguments, mintRewardsRecipients, and mintComment
 * @param signerContract - The contract that signed the premint, if this is a smart wallet based premint
 * @param paidMintPricePerToken - If this is for a paid mint, this is the price in eth per each token to be collected
 */
export function collectPremintV2WithMintsParams({
  tokenIds,
  quantities,
  paidMintPricePerToken,
  account,
  chainId,
  ...rest
}: {
  paidMintPricePerToken?: bigint;
  chainId: keyof typeof zoraMints1155Config.address;
  account: Address | Account;
} & PremintOnManagerParams) {
  const call = encodePremintOnManager({
    ...rest,
  });

  return makeSimulateContractParamaters({
    abi: zoraMints1155Config.abi,
    address: zoraMints1155Config.address[chainId],
    functionName: "transferBatchToManagerAndCall",
    args: [tokenIds, quantities, call],
    value: getPaidMintValue(quantities, paidMintPricePerToken),
    account,
  });
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

/**
 * Can be used to decode an a CallFailed error from the ZoraMints1155 contract when it has called a function on the ZoraMintsManager.
 * @param error
 * @returns
 */
export function decodeCallFailedError(error: ContractFunctionRevertedError) {
  if (error.data?.errorName !== "CallFailed")
    throw new Error("Not a CallFailed error");

  const internalErrorData = error.data?.args?.[0] as Hex;

  return decodeErrorResult({
    abi: zoraMintsManagerImplABI,
    data: internalErrorData,
  });
}
