import { Address } from "viem";
import {
  RewardsToken,
  CreatorERC20zQueryResult,
} from "../rewards/subgraph-queries";

const mockResult = ({
  erz20z,
  secondaryActivated,
}: {
  erz20z: Address;
  secondaryActivated: boolean;
}): RewardsToken => ({
  salesStrategies: [
    {
      zoraTimedMinter: {
        secondaryActivated,
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
  erc20z: { secondaryActivated: boolean; erz20z: Address }[];
}): CreatorERC20zQueryResult => ({
  zoraCreateTokens: erc20z.map(mockResult),
});
