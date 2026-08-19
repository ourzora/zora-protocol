import { describe, it, expect } from "vitest";
import { render } from "ink-testing-library";
import { CoinDetail } from "./CoinDetail.js";
import type { ResolvedCoin } from "../lib/coin-ref.js";

function makeCoin(overrides: Partial<ResolvedCoin> = {}): ResolvedCoin {
  return {
    name: "TestCoin",
    address: "0x1234567890abcdef1234567890abcdef12345678",
    coinType: "post",
    marketCap: "5000000",
    marketCapDelta24h: "100000",
    volume24h: "250000",
    totalSupply: "1000000000",
    uniqueHolders: 1842,
    createdAt: "2026-03-01T14:30:00Z",
    creatorAddress: "0xcreatoraddr",
    creatorHandle: "alice",
    platformBlocked: false,
    ...overrides,
  };
}

describe("CoinDetail", () => {
  it("renders coin details", () => {
    const { lastFrame } = render(<CoinDetail coin={makeCoin()} />);

    expect(lastFrame()).toContain("TestCoin");
    expect(lastFrame()).toContain("post");
    expect(lastFrame()).toContain("0x1234567890abcdef1234567890abcdef12345678");
    expect(lastFrame()).toContain("$5.0M");
    expect(lastFrame()).toContain("$250.0K");
    expect(lastFrame()).toContain("1,842");
    expect(lastFrame()).toContain("Creator");
    expect(lastFrame()).toContain("alice");
  });

  it("does not show Creator for non-post coins", () => {
    const { lastFrame } = render(
      <CoinDetail coin={makeCoin({ coinType: "creator-coin" })} />,
    );

    expect(lastFrame()).toContain("creator-coin");
    expect(lastFrame()).not.toContain("Creator");
  });

  it("shows creator address when no handle", () => {
    const { lastFrame } = render(
      <CoinDetail coin={makeCoin({ creatorHandle: undefined })} />,
    );

    expect(lastFrame()).toContain("Creator");
    expect(lastFrame()).toContain("0xcreatoraddr");
  });

  it("hides Creator row when neither handle nor address", () => {
    const { lastFrame } = render(
      <CoinDetail
        coin={makeCoin({ creatorHandle: undefined, creatorAddress: undefined })}
      />,
    );

    expect(lastFrame()).not.toContain("Creator");
  });
});
