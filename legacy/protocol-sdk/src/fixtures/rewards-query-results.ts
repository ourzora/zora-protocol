import { Address } from "viem";
import {
  RewardsToken,
  CreatorERC20zQueryResult,
} from "../rewards/subgraph-queries";

const mockResult = ({ erz20z }: { erz20z: Address }): RewardsToken => ({
  salesStrategies: [
    {
      zoraTimedMinter: {
        erc20Z: {
          id: erz20z,
        },
      },
    },
  ],
});

export const mockRewardsQueryResults = ({
  erc20z,
}: {
  erc20z: { erz20z: Address }[];
}): CreatorERC20zQueryResult => ({
  zoraCreateTokens: erc20z.map(mockResult),
});
