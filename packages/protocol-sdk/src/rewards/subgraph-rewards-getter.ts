import { SubgraphGetter } from "src/apis/subgraph-getter";
import { ISubgraphQuerier } from "src/apis/subgraph-querier";
import { Address } from "viem";
import { buildCreatorERC20zs } from "./subgraph-queries";

export interface IRewardsGetter {
  getErc20ZzForCreator: (params: { address: Address }) => Promise<Address[]>;
}

export class SubgraphRewardsGetter
  extends SubgraphGetter
  implements IRewardsGetter
{
  constructor(chainId: number, subgraphQuerier?: ISubgraphQuerier) {
    super(chainId, subgraphQuerier);
  }

  async getErc20ZzForCreator({
    address,
  }: {
    address: Address;
  }): Promise<Address[]> {
    const queryResults = await this.querySubgraphWithRetries(
      buildCreatorERC20zs({ address }),
    );

    return (
      queryResults?.map(
        (result) => result.salesStrategies[0].zoraTimedMinter.erc20Z.id,
      ) || []
    );
  }
}
