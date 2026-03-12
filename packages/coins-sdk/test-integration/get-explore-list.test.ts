import { describe, it, expect } from "vitest";
import {
  getCoinsTopVolume24h,
  getCoinComments,
  getTrendingAll,
  getTrendingCreators,
  getTrendingPosts,
  getMostValuableTrends,
  getNewTrends,
  getTopVolumeTrends24h,
  getTrendingTrends,
  getExploreList,
} from "../src";

const expectExploreResponse = (result: { data?: unknown }) => {
  expect(result.data).toBeDefined();
};

describe("Coin Onchain Info", () => {
  it("gets latest coin info mainnet with USDC", async () => {
    const coinDetails = await getCoinsTopVolume24h();
    console.log({ coinDetails });
  });
  it("gets latest coin info mainnet debug", async () => {
    const coinComments = await getCoinComments({
      address: "0x72fd6907113101e6e32cee25d5909868504d67f1",
    });

    console.log({ coinComments });
  });
});

describe("Explore trending wrappers", () => {
  it("getTrendingAll returns data", async () => {
    const result = await getTrendingAll();
    expectExploreResponse(result);
  });

  it("getTrendingCreators returns data", async () => {
    const result = await getTrendingCreators();
    expectExploreResponse(result);
  });

  it("getTrendingPosts returns data", async () => {
    const result = await getTrendingPosts();
    expectExploreResponse(result);
  });

  it("getTrendingTrends returns data", async () => {
    const result = await getTrendingTrends();
    expectExploreResponse(result);
  });
});

describe("Explore trend wrappers", () => {
  it("getMostValuableTrends returns data", async () => {
    const result = await getMostValuableTrends();
    expectExploreResponse(result);
  });

  it("getNewTrends returns data", async () => {
    const result = await getNewTrends();
    expectExploreResponse(result);
  });

  it("getTopVolumeTrends24h returns data", async () => {
    const result = await getTopVolumeTrends24h();
    expectExploreResponse(result);
  });
});

describe("getExploreList generic", () => {
  it("works with TRENDING_ALL list type", async () => {
    const result = await getExploreList("TRENDING_ALL");
    expectExploreResponse(result);
  });

  it("works with MOST_VALUABLE list type", async () => {
    const result = await getExploreList("MOST_VALUABLE");
    expectExploreResponse(result);
  });
});
