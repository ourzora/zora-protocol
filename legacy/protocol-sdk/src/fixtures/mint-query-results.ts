import { Address, parseEther, zeroAddress } from "viem";
import { TokenQueryResult } from "../mint/subgraph-queries";
import { zoraTimedSaleStrategyAddress } from "@zoralabs/protocol-deployments";
import { SALE_END_FOREVER } from "../create/minter-defaults";

export const mockTimedSaleStrategyTokenQueryResult = ({
  tokenId,
  contractAddress,
  contractVersion,
  chainId,
  saleEnd = SALE_END_FOREVER,
}: {
  tokenId: bigint;
  contractAddress: Address;
  contractVersion: string;
  chainId: number;
  saleEnd?: bigint;
}): TokenQueryResult => ({
  contract: {
    address: contractAddress,
    contractVersion,
    // not used:
    mintFeePerQuantity: "0",
    name: "",
    contractURI: "",
    salesStrategies: [],
  },
  creator: zeroAddress,
  maxSupply: "1000",
  tokenStandard: "ERC1155",
  totalMinted: "0",
  uri: "",
  tokenId: tokenId.toString(),
  salesStrategies: [
    {
      type: "ZORA_TIMED",
      zoraTimedMinter: {
        address:
          zoraTimedSaleStrategyAddress[
            chainId as keyof typeof zoraTimedSaleStrategyAddress
          ],
        mintFee: parseEther("0.000111").toString(),
        saleEnd: saleEnd.toString(),
        saleStart: "0",
        erc20Z: {
          // not needed
          id: zeroAddress,
          // note needed
          pool: zeroAddress,
        },
        secondaryActivated: false,
      },
    },
  ],
});
