import { describe, expect, it, vi } from "vitest";
import { type Address, getAddress } from "viem";
import { privateKeyToAccount } from "viem/accounts";
import type { PaymentRequired, PaymentRequirements } from "@x402/core/types";
import {
  parseAcceptsInput,
  resolvePayment,
  signPayment,
  X402_VERSION,
} from "./index.js";
import {
  type ReadOnlyClient,
  selectForFetch,
  selectPayableRequirement,
} from "./select.js";
import { resolveX402Signer } from "./signer.js";

const USDC: Address = getAddress("0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913");
const OTHER: Address = getAddress("0x1111111111166b7FE7bd91427724B487980aFc69");
const PAY_TO: Address = getAddress(
  "0xAbCdEf0123456789AbCdEf0123456789AbCdEf01",
);

// Deterministic test key (well-known anvil account #0) — never holds real funds.
const TEST_KEY =
  "0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80";
const account = privateKeyToAccount(TEST_KEY);

function requirement(
  overrides: Partial<PaymentRequirements> = {},
): PaymentRequirements {
  return {
    scheme: "exact",
    network: "eip155:8453",
    amount: "1000000", // 1 USDC (6 decimals)
    payTo: PAY_TO,
    maxTimeoutSeconds: 60,
    asset: USDC,
    extra: { name: "USD Coin", version: "2" },
    ...overrides,
  } as PaymentRequirements;
}

function paymentRequired(accepts: PaymentRequirements[]): PaymentRequired {
  return {
    x402Version: X402_VERSION,
    resource: { url: "https://api.example.com/data", description: "Test" },
    accepts,
  };
}

/** Mock public client whose balanceOf returns a fixed value per asset. */
function clientWithBalances(balances: Record<string, bigint>): ReadOnlyClient {
  return {
    readContract: vi.fn(async ({ address }: { address: Address }) => {
      return balances[getAddress(address)] ?? 0n;
    }),
  } as unknown as ReadOnlyClient;
}

describe("selectPayableRequirement", () => {
  const walletAddress = account.address;

  it("selects a Base exact entry the wallet can cover", async () => {
    const result = await selectPayableRequirement({
      accepts: [requirement()],
      publicClient: clientWithBalances({ [USDC]: 5_000_000n }),
      walletAddress,
    });
    expect(result.kind).toBe("selected");
    if (result.kind === "selected") {
      expect(result.requirement.network).toBe("eip155:8453");
      expect(result.requirement.asset).toBe(USDC);
    }
  });

  it("normalizes base and chain-id networks to eip155:8453", async () => {
    for (const network of ["base", "8453", "BASE"]) {
      const result = await selectPayableRequirement({
        accepts: [
          requirement({ network: network as PaymentRequirements["network"] }),
        ],
        publicClient: clientWithBalances({ [USDC]: 5_000_000n }),
        walletAddress,
      });
      expect(result.kind).toBe("selected");
      if (result.kind === "selected")
        expect(result.requirement.network).toBe("eip155:8453");
    }
  });

  it("skips non-Base and non-exact entries", async () => {
    const result = await selectPayableRequirement({
      accepts: [
        requirement({
          network: "solana:5eykt4Us" as PaymentRequirements["network"],
        }),
        requirement({ scheme: "upto" }),
      ],
      publicClient: clientWithBalances({ [USDC]: 5_000_000n }),
      walletAddress,
    });
    expect(result.kind).toBe("none");
  });

  it("returns none when balance is insufficient", async () => {
    const result = await selectPayableRequirement({
      accepts: [requirement({ amount: "10000000" })],
      publicClient: clientWithBalances({ [USDC]: 1n }),
      walletAddress,
    });
    expect(result.kind).toBe("none");
  });

  it("rejects a zero-amount requirement even with a funded wallet", async () => {
    const result = await selectPayableRequirement({
      accepts: [requirement({ amount: "0" })],
      publicClient: clientWithBalances({ [USDC]: 5_000_000n }),
      walletAddress,
    });
    expect(result.kind).toBe("none");
  });

  it("honors an explicit asset preference", async () => {
    const result = await selectPayableRequirement({
      accepts: [requirement({ asset: USDC }), requirement({ asset: OTHER })],
      publicClient: clientWithBalances({ [USDC]: 5_000_000n, [OTHER]: 5n }),
      walletAddress,
      preferredAsset: OTHER,
    });
    // OTHER preferred but balance too low -> falls back to next payable (USDC).
    expect(result.kind).toBe("selected");
    if (result.kind === "selected") expect(result.requirement.asset).toBe(USDC);
  });
});

describe("parseAcceptsInput", () => {
  it("accepts a bare requirements array", () => {
    const parsed = parseAcceptsInput(JSON.stringify([requirement()]));
    expect(parsed.accepts).toHaveLength(1);
    expect(parsed.x402Version).toBe(X402_VERSION);
  });

  it("accepts a full 402 response object and reads its version", () => {
    const parsed = parseAcceptsInput(
      JSON.stringify({
        x402Version: 2,
        resource: { url: "https://x.test" },
        accepts: [requirement()],
      }),
    );
    expect(parsed.accepts).toHaveLength(1);
    expect(parsed.x402Version).toBe(2);
    expect(parsed.resource.url).toBe("https://x.test");
  });

  it("throws on input that is neither JSON nor a valid header", () => {
    expect(() => parseAcceptsInput("not json")).toThrow();
  });

  it("throws when no accepts array is present", () => {
    expect(() => parseAcceptsInput(JSON.stringify({ foo: 1 }))).toThrow();
  });
});

describe("resolvePayment (selection + cap, no signing)", () => {
  it("selects a payable Base entry", async () => {
    const result = await resolvePayment({
      paymentRequired: paymentRequired([requirement()]),
      publicClient: clientWithBalances({ [USDC]: 5_000_000n }),
      address: account.address,
    });
    expect(result.kind).toBe("selected");
    if (result.kind === "selected") expect(result.requirement.asset).toBe(USDC);
  });

  it("returns none above --max-value (without signing)", async () => {
    const result = await resolvePayment({
      paymentRequired: paymentRequired([requirement({ amount: "2000000" })]),
      publicClient: clientWithBalances({ [USDC]: 5_000_000n }),
      address: account.address,
      maxValue: 1_000_000n,
    });
    expect(result.kind).toBe("none");
    if (result.kind === "none") expect(result.reason).toMatch(/max-value/);
  });

  it("returns none when nothing is payable", async () => {
    const result = await resolvePayment({
      paymentRequired: paymentRequired([requirement()]),
      publicClient: clientWithBalances({ [USDC]: 0n }),
      address: account.address,
    });
    expect(result.kind).toBe("none");
  });
});

describe("signPayment (EOA signing)", () => {
  const signer = resolveX402Signer(account, undefined, false);

  it("signs a chosen requirement into a valid PAYMENT-SIGNATURE header", async () => {
    const { header } = await signPayment({
      paymentRequired: paymentRequired([requirement()]),
      requirement: requirement(),
      signer,
    });

    // Header is base64 JSON of an x402 v2 PaymentPayload.
    const decoded = JSON.parse(Buffer.from(header, "base64").toString("utf-8"));
    expect(decoded.x402Version).toBe(2);
    expect(decoded.accepted.scheme).toBe("exact");
    expect(decoded.accepted.network).toBe("eip155:8453");
    expect(decoded.payload.signature).toMatch(/^0x[0-9a-fA-F]+$/);

    const auth = decoded.payload.authorization;
    expect(getAddress(auth.from)).toBe(account.address);
    expect(getAddress(auth.to)).toBe(PAY_TO);
    expect(auth.value).toBe("1000000");
    expect(BigInt(auth.validBefore)).toBeGreaterThan(BigInt(auth.validAfter));
    expect(auth.nonce).toMatch(/^0x[0-9a-fA-F]{64}$/);
  });
});

describe("selectForFetch", () => {
  it("picks the first Base exact entry and normalizes the network", () => {
    const chosen = selectForFetch(
      [requirement({ network: "base" as PaymentRequirements["network"] })],
      {},
    );
    expect(chosen.network).toBe("eip155:8453");
    expect(chosen.asset).toBe(USDC);
  });

  it("honors an asset preference", () => {
    const chosen = selectForFetch(
      [requirement({ asset: USDC }), requirement({ asset: OTHER })],
      { preferredAsset: OTHER },
    );
    expect(chosen.asset).toBe(OTHER);
  });

  it("throws when the amount exceeds --max-value", () => {
    expect(() =>
      selectForFetch([requirement({ amount: "2000000" })], {
        maxValue: 1_000_000n,
      }),
    ).toThrow(/max-value/);
  });

  it("throws when no Base exact entry is offered", () => {
    expect(() =>
      selectForFetch(
        [
          requirement({
            network: "solana:x" as PaymentRequirements["network"],
          }),
        ],
        {},
      ),
    ).toThrow(/No 'exact'/);
  });
});
