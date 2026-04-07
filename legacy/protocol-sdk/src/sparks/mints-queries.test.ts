import { describe, expect, it } from "vitest";
import {
  MintAccountBalance,
  selectMintsToCollectWithFromQueryResult,
  sumBalances,
} from "./mints-queries";

describe("MINTs queries", () => {
  describe("selectMintsToCollectWithFromQueryResult", () => {
    it("should return the optimum tokenIds and quantities to collect", async () => {
      // account has 3 of token 1, 4 of token 2, 10 of token 3
      // token 1 price is 2, token 2 price is 1, token 3 price is 3
      // we want to collect 10 tokens
      // we should return token 2 with 4 tokens, token 1 with 3 tokens, and token 3 with 3 tokens
      const mintTokenBalances: MintAccountBalance[] = [
        {
          mintToken: {
            id: "1",
            pricePerToken: "2",
          },
          balance: "3",
        },
        {
          mintToken: {
            id: "2",
            pricePerToken: "1",
          },
          balance: "4",
        },
        {
          mintToken: {
            id: "3",
            pricePerToken: "3",
          },
          balance: "10",
        },
      ];

      const result = selectMintsToCollectWithFromQueryResult(
        mintTokenBalances,
        10n,
      );

      const expectedResult = {
        tokenIds: [2n, 1n, 3n],
        quantities: [4n, 3n, 3n],
      };

      expect(result).toEqual(expectedResult);
    });

    it("should throw an error if not enough tokens to collect with", () => {
      const mintTokenBalances: MintAccountBalance[] = [
        {
          mintToken: {
            id: "1",
            pricePerToken: "2",
          },
          balance: "3",
        },
        {
          mintToken: {
            id: "2",
            pricePerToken: "1",
          },
          balance: "4",
        },
      ];
      const quantityToCollect = 8n;

      expect(() => {
        selectMintsToCollectWithFromQueryResult(
          mintTokenBalances,
          quantityToCollect,
        );
      }).toThrowError("Not enough MINTs to collect with");
    });
  });

  describe("sumBalances", () => {
    it("should return the sum of the balances", async () => {
      // account has 3 of token 1, 4 of token 2, 10 of token 3
      // token 1 price is 2, token 2 price is 1, token 3 price is 3
      // we want to collect 10 tokens
      // we should return token 2 with 4 tokens, token 1 with 3 tokens, and token 3 with 3 tokens
      const mintTokenBalances: Pick<MintAccountBalance, "balance">[] = [
        {
          balance: "3",
        },
        {
          balance: "4",
        },
        {
          balance: "10",
        },
      ];

      const result = sumBalances(mintTokenBalances);

      const expectedResult = 3n + 4n + 10n;

      expect(result).toEqual(expectedResult);
    });
  });
});
