import { afterEach, describe, expect, it, vi } from "vitest";
import {
  decodeAbiParameters,
  hashMessage,
  recoverAddress,
  toHex,
  type Address,
  type Hex,
} from "viem";
import { privateKeyToAccount } from "viem/accounts";
import { toReplaySafeHash } from "./signer.js";

const PRIVATE_KEY =
  "0x59c6995e998f97a5a0044966f0945389dc9e86dae88c7a8412f4603b6b78690d" as const;
const EXTERNAL = privateKeyToAccount(PRIVATE_KEY).address;
// A distinct embedded owner (anvil acct #2) — must differ from EXTERNAL so the
// owner-index lookup can tell them apart.
const EMBEDDED = "0x3C44CdDdB6a900fa2b585dd299e03d12FA4293BC" as Address;
const CONFIGURED_SCW = "0x1111111111166b7FE7bd91427724B487980aFc69" as Address;
const PREDICTED_SCW = "0x2222222222222222222222222222222222222222" as Address;

// A Privy session as ensurePrivySession returns it. `linkedAccountsKnown: true`
// models a fresh SIWE sign-in (the linked accounts were read); the cache/refresh
// paths return `false` with empty linked accounts — see the cache-path tests.
const FRESH_SESSION = {
  address: EXTERNAL,
  did: "did:privy:test",
  appId: "app",
  origin: "https://zora.co",
  accessToken: "privy.jwt.token",
  accessTokenExpiresAt: Number.MAX_SAFE_INTEGER,
  refreshToken: "refresh.token",
  linkedAccounts: [],
  linkedAccountsKnown: true,
  isNewUser: false,
  source: "siwe" as const,
};
const CACHED_SESSION = {
  ...FRESH_SESSION,
  linkedAccountsKnown: false,
  source: "cache" as const,
};

// ensurePrivySession hits auth.privy.io / disk; stub it. findEmbeddedWallet is
// pure, but stubbed too so tests don't depend on the linked-account shape.
vi.mock("../lib/privy.js", () => ({
  findEmbeddedWallet: vi.fn(() => EMBEDDED),
}));

vi.mock("../lib/privy-session.js", () => ({
  ensurePrivySession: vi.fn(async () => FRESH_SESSION),
}));

vi.mock("../lib/config.js", () => ({
  getAgentWallet: vi.fn(() => undefined),
  getSmartWalletAddress: vi.fn(() => CONFIGURED_SCW),
  saveSmartWalletAddress: vi.fn(),
}));

import { findEmbeddedWallet } from "../lib/privy.js";
import { ensurePrivySession } from "../lib/privy-session.js";
import { getAgentWallet, getSmartWalletAddress } from "../lib/config.js";
import { createSmartWalletAuth } from "./identity.js";
import { createCliSmartWalletProvider } from "./cli-auth-provider.js";

// A lightweight ChainClient injected for the predict/deployed fallback path.
const fakeClient = (deployed: boolean) => ({
  readContract: vi.fn(async () => PREDICTED_SCW),
  getCode: vi.fn(async () => (deployed ? ("0x1234" as Hex) : ("0x" as Hex))),
  call: vi.fn(),
});

afterEach(() => vi.clearAllMocks());

describe("createCliSmartWalletProvider", () => {
  it("authenticates via the cached/refreshing Privy session, not a fresh SIWE every time", async () => {
    const provider = await createCliSmartWalletProvider({
      privateKey: PRIVATE_KEY,
    });
    expect(provider.getSmartWalletAddress()).toBe(CONFIGURED_SCW);
    expect(provider.getOwnerAddress()).toBe(EXTERNAL);
    expect(ensurePrivySession).toHaveBeenCalledTimes(1);
  });

  it("places the external EOA at owner index 1, embedded at 0", async () => {
    const provider = await createCliSmartWalletProvider({
      privateKey: PRIVATE_KEY,
    });
    expect(provider.getOwners()).toEqual([
      { ownerAddress: EMBEDDED, ownerIndex: 0 },
      { ownerAddress: EXTERNAL, ownerIndex: 1 },
    ]);
  });

  it("signHash raw-signs the 32-byte hash (no EIP-191 prefix), recovering to the external EOA", async () => {
    const provider = await createCliSmartWalletProvider({
      privateKey: PRIVATE_KEY,
    });
    const hash = hashMessage("gm");
    const signature = await provider.signHash(hash);
    expect(await recoverAddress({ hash, signature })).toBe(EXTERNAL);
  });

  it("end-to-end: createSmartWalletAuth wraps with owner index 1, recovering to the external EOA", async () => {
    const provider = await createCliSmartWalletProvider({
      privateKey: PRIVATE_KEY,
    });
    const { signerSpec } = createSmartWalletAuth(provider);
    const bytes = await signerSpec.signMessage("hello xmtp");

    const [decoded] = decodeAbiParameters(
      [
        {
          components: [
            { name: "ownerIndex", type: "uint8" },
            { name: "signatureData", type: "bytes" },
          ],
          type: "tuple",
        },
      ],
      toHex(bytes),
    ) as [{ ownerIndex: number; signatureData: Hex }];

    expect(decoded.ownerIndex).toBe(1);
    const replaySafeHash = toReplaySafeHash({
      chainId: 8453,
      address: CONFIGURED_SCW,
      hash: hashMessage("hello xmtp"),
    });
    expect(
      await recoverAddress({
        hash: replaySafeHash,
        signature: decoded.signatureData,
      }),
    ).toBe(EXTERNAL);
  });

  it("returns the session's Privy JWT from getAccessToken", async () => {
    const provider = await createCliSmartWalletProvider({
      privateKey: PRIVATE_KEY,
    });
    expect(await provider.getAccessToken()).toBe("privy.jwt.token");
  });

  it("derives + verifies the address on-chain when config has none", async () => {
    vi.mocked(getSmartWalletAddress).mockReturnValueOnce(undefined);
    const client = fakeClient(true);
    const provider = await createCliSmartWalletProvider({
      privateKey: PRIVATE_KEY,
      client,
    });
    expect(provider.getSmartWalletAddress()).toBe(PREDICTED_SCW);
    expect(client.readContract).toHaveBeenCalledTimes(1);
    expect(client.getCode).toHaveBeenCalledTimes(1);
  });

  it("throws when the derived smart wallet is not deployed", async () => {
    vi.mocked(getSmartWalletAddress).mockReturnValueOnce(undefined);
    await expect(
      createCliSmartWalletProvider({
        privateKey: PRIVATE_KEY,
        client: fakeClient(false),
      }),
    ).rejects.toThrow(/not deployed/);
  });

  // A cached or refresh-token session carries no linked accounts. With the smart
  // wallet already configured, that's fine — we never need the embedded owner, so
  // no fresh SIWE is forced just to read it.
  it("works from a cached session (no linked accounts) when the smart wallet is configured", async () => {
    vi.mocked(ensurePrivySession).mockResolvedValueOnce(CACHED_SESSION);
    const provider = await createCliSmartWalletProvider({
      privateKey: PRIVATE_KEY,
    });
    expect(provider.getSmartWalletAddress()).toBe(CONFIGURED_SCW);
    expect(await provider.getAccessToken()).toBe("privy.jwt.token");
    // No embedded owner is known, so the set is the signing EOA alone — and we
    // must not have consulted the (empty) linked accounts to fabricate one.
    expect(provider.getOwners()).toEqual([
      { ownerAddress: EXTERNAL, ownerIndex: 1 },
    ]);
    expect(findEmbeddedWallet).not.toHaveBeenCalled();
  });

  // When the session has no linked accounts, the embedded owner is recovered from
  // the identity `zora agent create` persisted, restoring the full owner set.
  it("falls back to the persisted agent embedded wallet when the session has no linked accounts", async () => {
    vi.mocked(ensurePrivySession).mockResolvedValueOnce(CACHED_SESSION);
    vi.mocked(getAgentWallet).mockReturnValueOnce({
      embeddedWalletAddress: EMBEDDED,
    } as ReturnType<typeof getAgentWallet>);
    const provider = await createCliSmartWalletProvider({
      privateKey: PRIVATE_KEY,
    });
    expect(provider.getOwners()).toEqual([
      { ownerAddress: EMBEDDED, ownerIndex: 0 },
      { ownerAddress: EXTERNAL, ownerIndex: 1 },
    ]);
    expect(findEmbeddedWallet).not.toHaveBeenCalled();
  });

  // Even on a fresh SIWE session (linked accounts were read) the embedded owner
  // can be absent from them; we still recover it from the persisted agent
  // identity rather than dropping it from the owner set.
  it("falls back to the persisted agent embedded wallet when a SIWE session's linked accounts lack one", async () => {
    vi.mocked(findEmbeddedWallet).mockReturnValueOnce(undefined);
    vi.mocked(getAgentWallet).mockReturnValueOnce({
      embeddedWalletAddress: EMBEDDED,
    } as ReturnType<typeof getAgentWallet>);
    const provider = await createCliSmartWalletProvider({
      privateKey: PRIVATE_KEY,
    });
    // The session's linked accounts were consulted first (and came up empty)…
    expect(findEmbeddedWallet).toHaveBeenCalledTimes(1);
    // …then the persisted identity completed the owner set.
    expect(provider.getOwners()).toEqual([
      { ownerAddress: EMBEDDED, ownerIndex: 0 },
      { ownerAddress: EXTERNAL, ownerIndex: 1 },
    ]);
  });

  // The embedded owner is only mandatory when the smart wallet must be derived
  // (nothing configured, nothing persisted) — then there's nothing to act as.
  it("throws guidance when no embedded wallet is available and the smart wallet isn't configured", async () => {
    vi.mocked(getSmartWalletAddress).mockReturnValueOnce(undefined);
    vi.mocked(findEmbeddedWallet).mockReturnValueOnce(undefined);
    await expect(
      createCliSmartWalletProvider({ privateKey: PRIVATE_KEY }),
    ).rejects.toThrow(/agent create/);
  });
});
