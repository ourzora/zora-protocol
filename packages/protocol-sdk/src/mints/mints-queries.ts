import { getSubgraphUrl } from "src/apis/chain-constants";
import { Address } from "viem";
import { request, gql } from "graphql-request";

type CollectQueryResult = {
  tokenIds: bigint[];
  quantities: bigint[];
};

export const getMintsAccountBalanceWithPriceQuery = (account: Address) => {
  const query = gql`
    query GetMintAccountBalances($account: String!) {
      mintAccountBalances(where: { account: $account }) {
        balance
        mintToken {
          id
          pricePerToken
        }
      }
    }
  `;

  return {
    query,
    variables: { account },
  };
};

export type MintAccountBalance = {
  balance: string;
  mintToken: {
    id: string;
    pricePerToken: string;
  };
};

export type MintAccountBalancesQueryResult = {
  mintTokenBalances: MintAccountBalance[];
};

/**
 * Given the result of a mint token balances query, selects the best MINTs to use to collect with that will satisfy the quantity,
 * by selecting the lowest priced MINTs first. Throws an error if not enough mints to collect with.
 */
export const selectMintsToCollectWithFromQueryResult = (
  mintAccountBalances: MintAccountBalance[],
  quantityToCollect: bigint,
) => {
  const parsed = mintAccountBalances.map((r) => {
    return {
      tokenId: BigInt(r.mintToken.id),
      quantity: BigInt(r.balance),
      pricePerToken: BigInt(r.mintToken.pricePerToken),
    };
  });

  // now we want to find the best tokens to collect with, sorted by lowest price ascending
  // given its a bigint, lets not do a straight subtraction but sort based on result of comparison gt/lt:
  const sorted = parsed.sort((a, b) => {
    if (a.pricePerToken < b.pricePerToken) {
      return -1;
    }
    return 1;
  });

  // we need to get array of tokenIds and quantities to collect with:
  let remainingQuantity = quantityToCollect;
  const tokenIds: bigint[] = [];
  const quantities: bigint[] = [];

  while (remainingQuantity > 0) {
    const next = sorted.shift();
    if (!next) {
      throw new Error("Not enough MINTs to collect with");
    }

    const quantityToUse =
      remainingQuantity > next.quantity ? next.quantity : remainingQuantity;
    tokenIds.push(next.tokenId);
    quantities.push(quantityToUse);
    remainingQuantity -= quantityToUse;
  }

  return {
    tokenIds,
    quantities,
  };
};

/**
 * Given an array of mint account balances, sums the balances.
 * @param mintAccountBalances
 * @returns Total balance
 */
export const sumBalances = (
  mintAccountBalances: Pick<MintAccountBalance, "balance">[],
) => {
  return mintAccountBalances.reduce((acc, curr) => {
    return acc + BigInt(curr.balance);
  }, BigInt(0));
};

/***
 * Given an account and quantity of MINTs to use to collect with, queries for MINTs
 * owned by an account, and selects the best MINTs to use to collect with that will satisfy that quantity.
 * @param account Account to query for MINTs
 * @param chainId
 * @param quantityToCollect How many MINTs to use to collect with
 * @returns
 */
export const getMINTsToCollectWith = async ({
  account,
  chainId,
  quantityToCollect,
}: {
  account: Address;
  chainId: number;
  quantityToCollect: bigint;
}): Promise<CollectQueryResult> => {
  const subgraphUrl = getSubgraphUrl(chainId);

  const { query, variables } = getMintsAccountBalanceWithPriceQuery(account);

  const result = await request<MintAccountBalancesQueryResult>(
    subgraphUrl,
    query,
    variables,
  );

  return selectMintsToCollectWithFromQueryResult(
    result.mintTokenBalances,
    quantityToCollect,
  );
};

/***
 * Given an account, queries for MINTs owned by an account, and sums the balances.
 * @param account Account to query for MINTs
 * @returns Total MINTs balance of account
 */
export const getMINTsBalance = async ({
  chainId,
  account,
}: {
  account: Address;
  chainId: number;
}) => {
  const subgraphUrl = getSubgraphUrl(chainId);

  const { query, variables } = getMintsAccountBalanceWithPriceQuery(account);

  const result = await request<MintAccountBalancesQueryResult>(
    subgraphUrl,
    query,
    variables,
  );

  return sumBalances(result.mintTokenBalances);
};
