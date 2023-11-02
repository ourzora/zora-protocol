import {
  Address,
  Chain,
  PublicClient,
  WalletClient,
  encodeAbiParameters,
  parseAbi,
  parseAbiParameters,
  zeroAddress,
} from "viem";
import { ClientBase } from "./client-base";
import { MintAPIClient, MintableGetTokenResponse } from "./mint-api-client";
import {
  zoraCreator1155ImplABI,
  zoraCreatorFixedPriceSaleStrategyAddress,
} from "@zoralabs/protocol-deployments";

class MintError extends Error {}
class MintInactiveError extends Error {}

export const Errors = {
  MintError,
  MintInactiveError,
};

type MintArguments = {
  quantityToMint: number;
  mintComment?: string;
  mintReferral?: Address;
  mintToAddress: Address;
};

type MintParameters = {
  mintArguments: MintArguments;
  publicClient: PublicClient;
  mintable: MintableGetTokenResponse;
  sender: Address;
};

const zora721Abi = parseAbi([
  "function mintWithRewards(address recipient, uint256 quantity, string calldata comment, address mintReferral) external payable",
  "function zoraFeeForAmount(uint256 amount) public view returns (address, uint256)",
] as const);

export class MintClient extends ClientBase {
  apiClient: typeof MintAPIClient;

  constructor(chain: Chain, apiClient?: typeof MintAPIClient) {
    super(chain);

    if (!apiClient) {
      apiClient = MintAPIClient;
    }
    this.apiClient = apiClient;
  }

  async mintToken({
    publicClient,
    sender,
    address,
    tokenId,
    mintArguments,
  }: {
    publicClient: PublicClient;
    address: Address;
    sender: Address;
    tokenId?: bigint | number | string;
    mintArguments: MintArguments;
  }) {
    if (tokenId) {
      tokenId = BigInt(tokenId);
    }

    const mintable = await this.apiClient.getMintable(
      {
        chain_name: this.network.zoraBackendChainName,
        collection_address: address,
      },
      { token_id: tokenId?.toString() },
    );

    if (!mintable.feed_item.is_active) {
      throw new MintInactiveError("Minting token is inactive");
    }

    if (!mintable.feed_item.mint_context) {
      throw new MintError("No minting context data from zora API");
    }

    if (
      !["zora_create", "zora_create_1155"].includes(
        mintable.feed_item.mint_context?.mint_context_type!,
      )
    ) {
      throw new MintError(
        `Mintable type ${mintable.feed_item.mint_context.mint_context_type} is currently unsupported.`,
      );
    }

    if (
      mintable.feed_item.mint_context.mint_context_type === "zora_create_1155"
    ) {
      return {
        send: await this.mintZora1155({
          publicClient: this.getPublicClient(publicClient),
          mintArguments,
          sender,
          mintable,
        }),
        mintable,
      };
    }
    if (mintable.feed_item.mint_context.mint_context_type === "zora_create") {
      return {
        send: await this.mintZora721({
          publicClient: this.getPublicClient(publicClient),
          mintArguments,
          sender,
          mintable,
        }),
        mintable,
      };
    }

    throw new Error("Mintable type not found or recognized.");
  }

  private async mintZora1155({
    mintable,
    sender,
    publicClient,
    mintArguments,
  }: MintParameters) {
    const mintQuantity = BigInt(mintArguments.quantityToMint);

    const address = mintable.feed_item.collection.address as Address;

    const mintFee = await publicClient.readContract({
      abi: zoraCreator1155ImplABI,
      functionName: "mintFee",
      address,
    });

    const tokenFixedPriceMinter = await this.apiClient.getSalesConfigFixedPrice(
      {
        contractAddress: mintable.feed_item.contract_address,
        tokenId: mintable.feed_item.token_id!,
        chainId: this.network.chainId,
      },
    );

    return async (walletClient: WalletClient) => {
      const { request } = await publicClient.simulateContract({
        abi: zoraCreator1155ImplABI,
        functionName: "mintWithRewards",
        account: sender,
        value:
          (mintFee + BigInt(mintable.feed_item.cost.native_price.raw)) *
          mintQuantity,
        address,
        /* args: minter, tokenId, quantity, minterArguments, mintReferral */
        args: [
          (tokenFixedPriceMinter ||
            zoraCreatorFixedPriceSaleStrategyAddress[999]) as Address,
          BigInt(mintable.feed_item.token_id!),
          mintQuantity,
          encodeAbiParameters(parseAbiParameters("address, string"), [
            mintArguments.mintToAddress,
            mintArguments.mintComment || "",
          ]),
          mintArguments.mintReferral || zeroAddress,
        ],
      });
      return await walletClient.writeContract(request);
    };
  }

  private async mintZora721({
    mintable,
    publicClient,
    sender,
    mintArguments,
  }: MintParameters) {
    const [_, mintFee] = await publicClient.readContract({
      abi: zora721Abi,
      address: mintable.feed_item.contract_address as Address,
      functionName: "zoraFeeForAmount",
      args: [BigInt(mintArguments.quantityToMint)],
    });

    return async (walletClient: WalletClient) => {
      const { request } = await publicClient.simulateContract({
        abi: zora721Abi,
        address: mintable.feed_item.contract_address as Address,
        account: sender,
        functionName: "mintWithRewards",
        value:
          mintFee +
          BigInt(mintable.feed_item.cost.native_price.raw) *
            BigInt(mintArguments.quantityToMint),
        /* args: mint recipient, quantity to mint, mint comment, mintReferral */
        args: [
          mintArguments.mintToAddress,
          BigInt(mintArguments.quantityToMint),
          mintArguments.mintComment || "",
          mintArguments.mintReferral || zeroAddress,
        ],
      });
      return await walletClient.writeContract(request);
    };
  }
}
