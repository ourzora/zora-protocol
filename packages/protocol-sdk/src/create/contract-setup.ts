import { Address, PublicClient } from "viem";
import { ContractType } from "./types";
import {
  contracts1155,
  zoraCreator1155FactoryImplABI,
  zoraCreator1155FactoryImplAddress,
  zoraCreator1155ImplABI,
} from "@zoralabs/protocol-deployments";

type contracts1155Address = keyof typeof contracts1155.addresses;
function new1155ContractVersion(chainId: number): string {
  const address = contracts1155.addresses[chainId as contracts1155Address];
  if (!address) {
    throw new Error(`No contract address for chainId ${chainId}`);
  }

  return address.CONTRACT_1155_IMPL_VERSION;
}

export async function getContractInfo({
  publicClient,
  chainId,
  contract,
  account,
}: {
  publicClient: Pick<PublicClient, "readContract">;
  chainId: number;
  contract: ContractType;
  // Account that is the creator of the contract
  account: Address;
}): Promise<{
  contractExists: boolean;
  contractAddress: Address;
  contractVersion: string;
  nextTokenId: bigint;
}> {
  // Check if contract exists either from metadata or the static address passed in.
  // If a static address is passed in, this fails if that contract does not exist.
  const contractAddress =
    typeof contract === "string"
      ? contract
      : await publicClient.readContract({
          abi: zoraCreator1155FactoryImplABI,
          // Since this address is deterministic we can hardcode a chain id safely here.
          address:
            zoraCreator1155FactoryImplAddress[
              chainId as keyof typeof zoraCreator1155FactoryImplAddress
            ],
          functionName: "deterministicContractAddress",
          args: [
            account,
            contract.uri,
            contract.name,
            contract.defaultAdmin || account,
          ],
        });

  let contractVersion: string;
  let contractExists: boolean;
  try {
    contractVersion = await publicClient.readContract({
      abi: zoraCreator1155ImplABI,
      address: contractAddress,
      functionName: "contractVersion",
    });
    contractExists = true;
  } catch (e: any) {
    // This logic branch is hit if the contract doesn't exist
    //  falling back to contractExists to false.
    contractVersion = new1155ContractVersion(chainId);
    contractExists = false;
  }

  const nextTokenId = contractExists
    ? await publicClient.readContract({
        address: contractAddress,
        abi: zoraCreator1155ImplABI,
        functionName: "nextTokenId",
      })
    : 1n;

  return {
    contractExists,
    contractAddress,
    contractVersion,
    nextTokenId,
  };
}
