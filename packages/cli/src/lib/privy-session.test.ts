import { describe, it, expect, beforeEach, afterEach, vi } from "vitest";
import { privateKeyToAccount } from "viem/accounts";

// In-memory stand-in for the on-disk session store (config.ts is exercised
// separately in config.test.ts). `vi.hoisted` lets the mock factory share state.
const store = vi.hoisted(() => ({
  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  session: undefined as any,
}));

vi.mock("./config.js", () => ({
  getPrivySession: () => store.session,
  savePrivySession: vi.fn((s: Record<string, unknown>) => {
    store.session = { ...s, version: 1 };
  }),
}));

// Keep the real constants + PrivySessionExpiredError; mock only the network calls.
vi.mock("./privy.js", async (importOriginal) => {
  const actual = await importOriginal<typeof import("./privy.js")>();
  return {
    ...actual,
    createPrivyAccount: vi.fn(),
    refreshPrivySession: vi.fn(),
  };
});

import {
  ensurePrivySession,
  refreshPrivyLinkedAccounts,
  type PrivySession,
} from "./privy-session.js";
import {
  createPrivyAccount,
  refreshPrivySession,
  PrivySessionExpiredError,
  ZORA_PRIVY_APP_ID,
  DEFAULT_SIWE_ORIGIN,
} from "./privy.js";
import { savePrivySession } from "./config.js";

const TEST_PK =
  "0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80" as const;
const ADDRESS = privateKeyToAccount(TEST_PK).address;

const HOUR = 60 * 60 * 1000;

/** A SIWE result (createPrivyAccount's return shape). */
function siweResult(overrides: Record<string, unknown> = {}) {
  return {
    address: ADDRESS,
    did: "did:privy:new",
    accessToken: "siwe-access",
    accessTokenExpiresAt: Date.now() + HOUR,
    refreshToken: "siwe-refresh",
    identityToken: "siwe-id",
    isNewUser: true,
    linkedAccounts: [{ type: "wallet", address: "0xsiwe" }],
    ...overrides,
  };
}

/** A stored session fixture matching the default app + origin for TEST_PK. */
function stored(overrides: Record<string, unknown> = {}) {
  return {
    version: 1,
    address: ADDRESS,
    appId: ZORA_PRIVY_APP_ID,
    origin: DEFAULT_SIWE_ORIGIN,
    did: "did:privy:cached",
    accessToken: "cached-access",
    accessTokenExpiresAt: Date.now() + 10 * 60 * 1000,
    refreshToken: "cached-refresh",
    identityToken: "cached-id",
    ...overrides,
  };
}

let warnSpy: ReturnType<typeof vi.spyOn>;

beforeEach(() => {
  store.session = undefined;
  vi.clearAllMocks();
  // tryRefresh warns on a failed refresh before falling back to SIWE; silence it
  // here (and assert it where relevant) so test output stays clean.
  warnSpy = vi.spyOn(console, "warn").mockImplementation(() => {});
});

afterEach(() => {
  warnSpy.mockRestore();
});

describe("ensurePrivySession", () => {
  it("runs SIWE when there is no cached session and persists it", async () => {
    vi.mocked(createPrivyAccount).mockResolvedValue(siweResult());

    const result = await ensurePrivySession({ privateKey: TEST_PK });

    expect(result.source).toBe("siwe");
    expect(result.accessToken).toBe("siwe-access");
    expect(result.refreshToken).toBe("siwe-refresh");
    expect(result.isNewUser).toBe(true);
    expect(refreshPrivySession).not.toHaveBeenCalled();
    expect(savePrivySession).toHaveBeenCalledWith(
      expect.objectContaining({ address: ADDRESS, accessToken: "siwe-access" }),
    );
  });

  it("reuses a still-valid cached access token without any network call", async () => {
    store.session = stored({
      accessTokenExpiresAt: Date.now() + 10 * 60 * 1000,
    });

    const result = await ensurePrivySession({ privateKey: TEST_PK });

    expect(result.source).toBe("cache");
    expect(result.accessToken).toBe("cached-access");
    expect(result.linkedAccountsKnown).toBe(false);
    expect(createPrivyAccount).not.toHaveBeenCalled();
    expect(refreshPrivySession).not.toHaveBeenCalled();
  });

  it("refreshes when the cached access token has expired", async () => {
    store.session = stored({ accessTokenExpiresAt: Date.now() - 1000 });
    vi.mocked(refreshPrivySession).mockResolvedValue({
      accessToken: "fresh-access",
      accessTokenExpiresAt: Date.now() + HOUR,
      refreshToken: "rotated-refresh",
      did: "did:privy:cached",
    });

    const result = await ensurePrivySession({ privateKey: TEST_PK });

    expect(result.source).toBe("refresh");
    expect(result.accessToken).toBe("fresh-access");
    expect(result.refreshToken).toBe("rotated-refresh");
    expect(createPrivyAccount).not.toHaveBeenCalled();
    expect(refreshPrivySession).toHaveBeenCalledWith(
      expect.objectContaining({ refreshToken: "cached-refresh" }),
    );
    // The rotated token is persisted for next time.
    expect(savePrivySession).toHaveBeenCalledWith(
      expect.objectContaining({ refreshToken: "rotated-refresh" }),
    );
  });

  it("treats a token expiring within the skew window as stale", async () => {
    // 30s out — inside the 60s skew — so it should refresh rather than reuse.
    store.session = stored({ accessTokenExpiresAt: Date.now() + 30_000 });
    vi.mocked(refreshPrivySession).mockResolvedValue({
      accessToken: "fresh-access",
      accessTokenExpiresAt: Date.now() + HOUR,
      refreshToken: "rotated-refresh",
    });

    const result = await ensurePrivySession({ privateKey: TEST_PK });
    expect(result.source).toBe("refresh");
  });

  it("falls back to SIWE when the refresh is rejected", async () => {
    store.session = stored({ accessTokenExpiresAt: Date.now() - 1000 });
    vi.mocked(refreshPrivySession).mockRejectedValue(
      new PrivySessionExpiredError(401),
    );
    vi.mocked(createPrivyAccount).mockResolvedValue(siweResult());

    const result = await ensurePrivySession({ privateKey: TEST_PK });

    expect(result.source).toBe("siwe");
    expect(createPrivyAccount).toHaveBeenCalledTimes(1);
    // The rate-limited SIWE fallback is warned so it's diagnosable.
    expect(warnSpy).toHaveBeenCalledWith(
      expect.stringMatching(/refresh failed.*HTTP 401.*SIWE/i),
    );
  });

  it("falls back to SIWE on a transient refresh error", async () => {
    store.session = stored({ accessTokenExpiresAt: Date.now() - 1000 });
    vi.mocked(refreshPrivySession).mockRejectedValue(new Error("network down"));
    vi.mocked(createPrivyAccount).mockResolvedValue(siweResult());

    const result = await ensurePrivySession({ privateKey: TEST_PK });
    expect(result.source).toBe("siwe");
    expect(warnSpy).toHaveBeenCalledWith(
      expect.stringMatching(/refresh failed.*network down/i),
    );
  });

  it("runs SIWE when the expired cache has no refresh token", async () => {
    store.session = stored({
      accessTokenExpiresAt: Date.now() - 1000,
      refreshToken: undefined,
    });
    vi.mocked(createPrivyAccount).mockResolvedValue(siweResult());

    const result = await ensurePrivySession({ privateKey: TEST_PK });

    expect(result.source).toBe("siwe");
    expect(refreshPrivySession).not.toHaveBeenCalled();
  });

  it("ignores a cached session belonging to a different address", async () => {
    store.session = stored({
      address: "0x000000000000000000000000000000000000dEaD",
      accessTokenExpiresAt: Date.now() + 10 * 60 * 1000,
    });
    vi.mocked(createPrivyAccount).mockResolvedValue(siweResult());

    const result = await ensurePrivySession({ privateKey: TEST_PK });

    // Mismatch → no reuse, no refresh; a full SIWE instead.
    expect(result.source).toBe("siwe");
    expect(refreshPrivySession).not.toHaveBeenCalled();
  });

  it("ignores a cached session for a different appId", async () => {
    store.session = stored({
      appId: "some-other-app",
      accessTokenExpiresAt: Date.now() + 10 * 60 * 1000,
    });
    vi.mocked(createPrivyAccount).mockResolvedValue(siweResult());

    const result = await ensurePrivySession({ privateKey: TEST_PK });
    expect(result.source).toBe("siwe");
  });
});

describe("refreshPrivyLinkedAccounts", () => {
  function liveSession(overrides: Partial<PrivySession> = {}): PrivySession {
    return {
      address: ADDRESS,
      did: "did:privy:x",
      appId: ZORA_PRIVY_APP_ID,
      origin: DEFAULT_SIWE_ORIGIN,
      accessToken: "access",
      accessTokenExpiresAt: Date.now() + HOUR,
      refreshToken: "refresh",
      linkedAccounts: [],
      linkedAccountsKnown: false,
      isNewUser: false,
      source: "siwe",
      ...overrides,
    };
  }

  it("uses the refresh when it returns linked accounts (no SIWE)", async () => {
    vi.mocked(refreshPrivySession).mockResolvedValue({
      accessToken: "fresh-access",
      accessTokenExpiresAt: Date.now() + HOUR,
      refreshToken: "rotated",
      linkedAccounts: [{ type: "wallet", address: "0xemb" }],
    });

    const result = await refreshPrivyLinkedAccounts(liveSession(), {
      privateKey: TEST_PK,
    });

    expect(result.source).toBe("refresh");
    expect(result.linkedAccountsKnown).toBe(true);
    expect(result.linkedAccounts).toEqual([
      { type: "wallet", address: "0xemb" },
    ]);
    expect(createPrivyAccount).not.toHaveBeenCalled();
  });

  it("re-authenticates when the refresh omits linked accounts", async () => {
    vi.mocked(refreshPrivySession).mockResolvedValue({
      accessToken: "fresh-access",
      accessTokenExpiresAt: Date.now() + HOUR,
      refreshToken: "rotated",
      // no linkedAccounts → can't be used for embedded-wallet polling
    });
    vi.mocked(createPrivyAccount).mockResolvedValue(siweResult());

    const result = await refreshPrivyLinkedAccounts(liveSession(), {
      privateKey: TEST_PK,
    });

    expect(result.source).toBe("siwe");
    expect(createPrivyAccount).toHaveBeenCalledTimes(1);
  });

  it("re-authenticates directly when the session has no refresh token", async () => {
    vi.mocked(createPrivyAccount).mockResolvedValue(siweResult());

    const result = await refreshPrivyLinkedAccounts(
      liveSession({ refreshToken: undefined }),
      { privateKey: TEST_PK },
    );

    expect(result.source).toBe("siwe");
    expect(refreshPrivySession).not.toHaveBeenCalled();
  });

  it("re-authenticates when the refresh is rejected", async () => {
    vi.mocked(refreshPrivySession).mockRejectedValue(
      new PrivySessionExpiredError(401),
    );
    vi.mocked(createPrivyAccount).mockResolvedValue(siweResult());

    const result = await refreshPrivyLinkedAccounts(liveSession(), {
      privateKey: TEST_PK,
    });
    expect(result.source).toBe("siwe");
  });
});
