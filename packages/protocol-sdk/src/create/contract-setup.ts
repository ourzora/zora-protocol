import { Address, Hex, PublicClient } from "viem";
import {
  contracts1155,
  zoraCreator1155FactoryImplABI,
  zoraCreator1155FactoryImplAddress,
  zoraCreator1155ImplABI,
} from "@zoralabs/protocol-deployments";
import { NewContractParams } from "./types";

type contracts1155Address = keyof typeof contracts1155.addresses;
export function new1155ContractVersion(chainId: number): string {
  // todo: get from subgraph
  const address = contracts1155.addresses[chainId as contracts1155Address];
  if (!address) {
    throw new Error(`No contract address for chainId ${chainId}`);
  }

  return address.CONTRACT_1155_IMPL_VERSION;
}

export async function getContractInfoExistingContract({
  publicClient,
  contractAddress,
}: {
  publicClient: Pick<PublicClient, "readContract">;
  contractAddress: Address;
  // Account that is the creator of the contract
}): Promise<{
  contractVersion: string;
  contractName: string;
  nextTokenId: bigint;
}> {
  // Check if contract exists either from metadata or the static address passed in.
  // If a static address is passed in, this fails if that contract does not exist.
  let contractVersion: string;
  try {
    contractVersion = await publicClient.readContract({
      abi: zoraCreator1155ImplABI,
      address: contractAddress,
      functionName: "contractVersion",
    });
  } catch (e: any) {
    // This logic branch is hit if the contract doesn't exist
    //  falling back to contractExists to false.
    throw new Error(`Contract does not exist at ${contractAddress}`);
  }

  const nextTokenId = await publicClient.readContract({
    address: contractAddress,
    abi: zoraCreator1155ImplABI,
    functionName: "nextTokenId",
  });

  const contractName = await publicClient.readContract({
    address: contractAddress,
    abi: zoraCreator1155ImplABI,
    functionName: "name",
  });

  return {
    contractVersion,
    contractName,
    nextTokenId,
  };
}

export async function getDeterministicContractAddress({
  publicClient,
  account,
  setupActions,
  contract,
  chainId,
}: {
  account: Address;
  publicClient: Pick<PublicClient, "readContract">;
  setupActions: Hex[];
  contract: NewContractParams;
  chainId: number;
  // Account that is the creator of the contract
}): Promise<Address> {
  const contractAddress = await publicClient.readContract({
    abi: zoraCreator1155FactoryImplABI,
    address:
      zoraCreator1155FactoryImplAddress[
        chainId as keyof typeof zoraCreator1155FactoryImplAddress
      ],
    functionName: "deterministicContractAddressWithSetupActions",
    args: [
      account,
      contract.uri,
      contract.name,
      contract.defaultAdmin || account,
      setupActions,
    ],
  });

  return contractAddress;
}
