import { Address, parseEther, PublicClient, zeroAddress } from "viem";
import { ConcreteSalesConfig } from "./types";
import {
  AsyncPrepareMint,
  MintParametersBase,
  OnchainSalesStrategies,
  PrepareMintReturn,
} from "src/mint/types";
import { zoraCreator1155ImplABI } from "@zoralabs/protocol-deployments";
import {
  makePrepareMint1155TokenParams,
  parseMintCosts,
} from "src/mint/mint-transactions";
import { getRequiredErc20Approvals } from "src/mint/mint-queries";

async function toSalesStrategyFromSubgraph({
  minter,
  salesConfig,
  publicClient,
  contractAddress,
}: {
  minter: Address;
  salesConfig: ConcreteSalesConfig;
  publicClient: Pick<PublicClient, "readContract">;
  contractAddress: Address;
}): Promise<OnchainSalesStrategies> {
  if (salesConfig.type === "timed") {
    return {
      saleType: "timed",
      address: minter,
      // for now we hardcode this
      mintFeePerQuantity: parseEther("0.000111"),
      saleStart: salesConfig.saleStart.toString(),
      saleEnd: salesConfig.saleEnd.toString(),
      // the following are not needed for now but we wanna satisfy concrete
      erc20Z: zeroAddress,
      mintFee: 0n,
      pool: zeroAddress,
      secondaryActivated: false,
    };
  }
  if (salesConfig.type === "erc20Mint") {
    return {
      saleType: "erc20",
      address: minter,
      mintFeePerQuantity: 0n,
      saleStart: salesConfig.saleStart.toString(),
      saleEnd: salesConfig.saleEnd.toString(),
      currency: salesConfig.currency,
      pricePerToken: salesConfig.pricePerToken,
      maxTokensPerAddress: salesConfig.maxTokensPerAddress,
    };
  }
  const contractMintFee = await publicClient.readContract({
    abi: zoraCreator1155ImplABI,
    address: contractAddress,
    functionName: "mintFee",
  });
  if (salesConfig.type === "fixedPrice") {
    return {
      saleType: "fixedPrice",
      address: minter,
      maxTokensPerAddress: salesConfig.maxTokensPerAddress,
      mintFeePerQuantity: contractMintFee,
      pricePerToken: salesConfig.pricePerToken,
      saleStart: salesConfig.saleStart.toString(),
      saleEnd: salesConfig.saleEnd.toString(),
    };
  }
  return {
    saleType: "allowlist",
    address: minter,
    saleStart: salesConfig.saleStart.toString(),
    saleEnd: salesConfig.saleEnd.toString(),
    merkleRoot: salesConfig.presaleMerkleRoot,
    mintFeePerQuantity: contractMintFee,
  };
}
export function makeOnchainPrepareMintFromCreate({
  contractAddress,
  tokenId,
  result,
  minter,
  publicClient,
  contractVersion,
}: {
  contractAddress: Address;
  tokenId: bigint;
  result: ConcreteSalesConfig;
  minter: Address;
  publicClient: Pick<PublicClient, "readContract">;
  contractVersion: string;
}): AsyncPrepareMint {
  return async (params: MintParametersBase): Promise<PrepareMintReturn> => {
    const subgraphSalesConfig = await toSalesStrategyFromSubgraph({
      minter,
      contractAddress,
      publicClient,
      salesConfig: result,
    });
    return {
      parameters: makePrepareMint1155TokenParams({
        salesConfigAndTokenInfo: {
          salesConfig: subgraphSalesConfig,
          contractVersion,
        },
        ...params,
        tokenContract: contractAddress,
        tokenId,
      }),
      costs: parseMintCosts({
        allowListEntry: params.allowListEntry,
        quantityToMint: BigInt(params.quantityToMint),
        salesConfig: subgraphSalesConfig,
      }),
      erc20Approval: getRequiredErc20Approvals(params, subgraphSalesConfig),
    };
  };
}
