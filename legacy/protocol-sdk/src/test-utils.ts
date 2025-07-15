import {
  zoraCreator1155FactoryImplABI,
  zoraCreator1155FactoryImplAddress,
} from "@zoralabs/protocol-deployments";
import {
  Address,
  PublicClient,
  encodeAbiParameters,
  keccak256,
  toBytes,
  parseAbiParameters,
  Chain,
  WalletClient,
  SimulateContractReturnType,
  Account,
} from "viem";
import { NewContractParams } from "./create/types";
import { retries } from "./apis/http-api-base";
import { SimulateContractParametersWithAccount } from "./types";

export const getFixedPricedMinter = async ({
  publicClient,
  chainId,
}: {
  publicClient: PublicClient;
  chainId: keyof typeof zoraCreator1155FactoryImplAddress;
}) =>
  await publicClient.readContract({
    abi: zoraCreator1155FactoryImplABI,
    address: zoraCreator1155FactoryImplAddress[chainId],
    functionName: "fixedPriceMinter",
  });

export const fixedPriceMinterMinterArguments = ({
  mintRecipient,
}: {
  mintRecipient: Address;
}) => encodeAbiParameters(parseAbiParameters("address"), [mintRecipient]);

const demoContractMetadataURI = "ipfs://DUMMY/contract.json";

export function randomNewContract(): NewContractParams {
  return {
    name: `testContract-${Math.round(Math.random() * 1_000_000)}`,
    uri: demoContractMetadataURI,
  };
}

export const randomNonce = () =>
  keccak256(toBytes(Math.round(Math.random() * 1000)));
export const thirtySecondsFromNow = () =>
  BigInt(Math.round(new Date().getTime() / 1000)) + 30n;

export async function simulateAndWriteContractWithRetries({
  parameters,
  walletClient,
  publicClient,
}: {
  parameters: SimulateContractParametersWithAccount;
  walletClient: WalletClient;
  publicClient: PublicClient;
}) {
  const { request } = await publicClient.simulateContract(parameters);
  return await writeContractWithRetries({
    request,
    walletClient,
    publicClient,
  });
}

export async function writeContractWithRetries({
  request,
  walletClient,
  publicClient,
}: {
  request: SimulateContractReturnType<any, any, any, Chain, Account>["request"];
  walletClient: WalletClient;
  publicClient: PublicClient;
}) {
  let tryCount = 1;
  const tryFn = async () => {
    if (tryCount > 1) {
      console.log("retrying try #", tryCount);
    }
    const hash = await walletClient.writeContract(request);
    const receipt = await publicClient.waitForTransactionReceipt({ hash });

    if (receipt.status !== "success") {
      console.log("failed try #", tryCount);
      tryCount++;
      throw new Error("transaction failed");
    }

    return receipt;
  };

  const shouldRetry = () => {
    return true;
  };

  return await retries(tryFn, 3, 1000, shouldRetry);
}
