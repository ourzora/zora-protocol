import { describe, it, expect, vi, beforeEach, afterEach } from "vitest";
import { privateKeyToAccount } from "viem/accounts";
import {
  createPrivyAccount,
  refreshPrivySession,
  PrivySessionExpiredError,
  findEmbeddedWallet,
  parseSetCookie,
  accessTokenExpiry,
  sendEmailCode,
  linkEmailWithCode,
  hasLinkedEmail,
  ZORA_PRIVY_APP_ID,
} from "./privy.js";

// Anvil test account #0 — a known-valid secp256k1 key.
const TEST_PK =
  "0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80" as const;
const EXPECTED_ADDRESS = privateKeyToAccount(TEST_PK).address;
// viem's createSiweMessage requires the nonce to be alphanumeric and >= 8 chars
// (as real Privy nonces are).
const VALID_NONCE = "abcdef1234567890";

/** A JWT-shaped string carrying `payload` as its (decodable) middle segment. */
function jwt(payload: Record<string, unknown>): string {
  const b64 = Buffer.from(JSON.stringify(payload)).toString("base64url");
  return `eyJhbGciOiJIUzI1NiJ9.${b64}.sig`;
}

const ACCESS_EXP = 1_900_000_000; // seconds since epoch
const ACCESS_JWT = jwt({ exp: ACCESS_EXP });

function jsonResponse(body: unknown, status = 200, setCookies?: string[]) {
  return {
    ok: status >= 200 && status < 300,
    status,
    json: async () => body,
    headers: setCookies
      ? { getSetCookie: () => setCookies, get: () => null }
      : undefined,
  };
}

describe("createPrivyAccount", () => {
  const fetchMock = vi.fn();

  beforeEach(() => {
    fetchMock.mockReset();
    vi.stubGlobal("fetch", fetchMock);
  });
  afterEach(() => {
    vi.unstubAllGlobals();
  });

  it("runs the SIWE handshake and returns the Privy session", async () => {
    fetchMock
      .mockResolvedValueOnce(jsonResponse({ nonce: VALID_NONCE }))
      .mockResolvedValueOnce(
        jsonResponse(
          {
            token: ACCESS_JWT,
            identity_token: "the.identity.jwt",
            user: { id: "did:privy:abc" },
            is_new_user: true,
          },
          200,
          [
            "privy-refresh-token=refresh-abc; Path=/; HttpOnly; Secure",
            "privy-token=ignored; Path=/",
          ],
        ),
      );

    const result = await createPrivyAccount({ privateKey: TEST_PK });

    expect(result).toEqual({
      address: EXPECTED_ADDRESS,
      did: "did:privy:abc",
      accessToken: ACCESS_JWT,
      accessTokenExpiresAt: ACCESS_EXP * 1000,
      refreshToken: "refresh-abc",
      identityToken: "the.identity.jwt",
      isNewUser: true,
      linkedAccounts: [],
      // Privy's session cookies, accumulated across the handshake (main's
      // `cookie` field) — used by authenticated write endpoints like email link.
      cookie: "privy-refresh-token=refresh-abc; privy-token=ignored",
    });

    expect(fetchMock).toHaveBeenCalledTimes(2);

    const [initUrl, initInit] = fetchMock.mock.calls[0];
    expect(initUrl).toBe("https://auth.privy.io/api/v1/siwe/init");
    expect(initInit.method).toBe("POST");
    expect(initInit.headers["privy-app-id"]).toBe(ZORA_PRIVY_APP_ID);
    expect(initInit.headers.origin).toBe("https://zora.com");
    expect(initInit.headers["User-Agent"]).toContain("Mozilla/5.0");
    expect(JSON.parse(initInit.body)).toEqual({ address: EXPECTED_ADDRESS });

    const [authUrl, authInit] = fetchMock.mock.calls[1];
    expect(authUrl).toBe("https://auth.privy.io/api/v1/siwe/authenticate");
    const authBody = JSON.parse(authInit.body);
    expect(authBody).toMatchObject({
      chainId: "eip155:8453",
      walletClientType: "metamask",
      connectorType: "injected",
      mode: "login-or-sign-up",
    });
    expect(authBody.message).toContain(VALID_NONCE);
    expect(authBody.message).toContain(EXPECTED_ADDRESS);
    expect(authBody.signature).toMatch(/^0x[0-9a-f]+$/i);
  });

  it("leaves refreshToken undefined when no cookie is set", async () => {
    fetchMock
      .mockResolvedValueOnce(jsonResponse({ nonce: VALID_NONCE }))
      .mockResolvedValueOnce(
        jsonResponse({ token: ACCESS_JWT, user: { id: "did:privy:abc" } }),
      );

    const result = await createPrivyAccount({ privateKey: TEST_PK });
    expect(result.refreshToken).toBeUndefined();
  });

  it("honors a custom appId, origin, and chainId", async () => {
    fetchMock
      .mockResolvedValueOnce(jsonResponse({ nonce: VALID_NONCE }))
      .mockResolvedValueOnce(
        jsonResponse({ token: ACCESS_JWT, user: { id: "did:privy:z" } }),
      );

    await createPrivyAccount({
      privateKey: TEST_PK,
      appId: "custom-app",
      origin: "https://example.test",
      chainId: 1,
      walletClientType: "coinbase_wallet",
      connectorType: "embedded",
    });

    const initHeaders = fetchMock.mock.calls[0][1].headers;
    expect(initHeaders["privy-app-id"]).toBe("custom-app");
    expect(initHeaders.origin).toBe("https://example.test");
    const authBody = JSON.parse(fetchMock.mock.calls[1][1].body);
    expect(authBody.chainId).toBe("eip155:1");
    expect(authBody.message).toContain("example.test");
    expect(authBody.walletClientType).toBe("coinbase_wallet");
    expect(authBody.connectorType).toBe("embedded");
  });

  it("throws when siwe/init fails", async () => {
    fetchMock.mockResolvedValueOnce(jsonResponse({ error: "nope" }, 403));
    await expect(createPrivyAccount({ privateKey: TEST_PK })).rejects.toThrow(
      "siwe/init failed (HTTP 403)",
    );
  });

  it("throws when siwe/init returns no nonce", async () => {
    fetchMock.mockResolvedValueOnce(jsonResponse({}, 200));
    await expect(createPrivyAccount({ privateKey: TEST_PK })).rejects.toThrow(
      "siwe/init failed",
    );
  });

  it("throws when siwe/authenticate fails", async () => {
    fetchMock
      .mockResolvedValueOnce(jsonResponse({ nonce: VALID_NONCE }))
      .mockResolvedValueOnce(jsonResponse({ error: "bad sig" }, 401));
    await expect(createPrivyAccount({ privateKey: TEST_PK })).rejects.toThrow(
      "siwe/authenticate failed (HTTP 401)",
    );
  });

  it("throws when authenticate response is missing a token or user", async () => {
    fetchMock
      .mockResolvedValueOnce(jsonResponse({ nonce: VALID_NONCE }))
      .mockResolvedValueOnce(jsonResponse({ token: "t" }, 200));
    await expect(createPrivyAccount({ privateKey: TEST_PK })).rejects.toThrow(
      "siwe/authenticate failed",
    );
  });

  it("accumulates Set-Cookie from init + authenticate into the session cookie", async () => {
    fetchMock
      .mockResolvedValueOnce(
        jsonResponse({ nonce: VALID_NONCE }, 200, [
          "privy-token=abc; Path=/; HttpOnly",
        ]),
      )
      .mockResolvedValueOnce(
        jsonResponse({ token: "t", user: { id: "did:privy:z" } }, 200, [
          "privy-session=xyz; Path=/; Secure",
        ]),
      );

    const result = await createPrivyAccount({ privateKey: TEST_PK });
    expect(result.cookie).toBe("privy-token=abc; privy-session=xyz");
    // the authenticate call carries the cookie that init set
    expect(fetchMock.mock.calls[1][1].headers.Cookie).toBe("privy-token=abc");
  });
});

describe("refreshPrivySession", () => {
  const fetchMock = vi.fn();

  beforeEach(() => {
    fetchMock.mockReset();
    vi.stubGlobal("fetch", fetchMock);
  });
  afterEach(() => {
    vi.unstubAllGlobals();
  });

  it("exchanges the refresh token for a fresh access + rotated refresh token", async () => {
    fetchMock.mockResolvedValueOnce(
      jsonResponse({
        token: ACCESS_JWT,
        refresh_token: "rotated-refresh",
        identity_token: "id-jwt",
        user: {
          id: "did:privy:abc",
          linked_accounts: [{ type: "wallet", address: "0xabc" }],
        },
      }),
    );

    const result = await refreshPrivySession({ refreshToken: "old-refresh" });

    expect(result).toEqual({
      accessToken: ACCESS_JWT,
      accessTokenExpiresAt: ACCESS_EXP * 1000,
      refreshToken: "rotated-refresh",
      identityToken: "id-jwt",
      did: "did:privy:abc",
      linkedAccounts: [{ type: "wallet", address: "0xabc" }],
    });

    const [url, init] = fetchMock.mock.calls[0];
    expect(url).toBe("https://auth.privy.io/api/v1/sessions");
    expect(init.method).toBe("POST");
    expect(init.headers["privy-app-id"]).toBe(ZORA_PRIVY_APP_ID);
    expect(init.headers.origin).toBe("https://zora.com");
    expect(init.headers["User-Agent"]).toContain("Mozilla/5.0");
    expect(init.headers.Cookie).toBe("privy-refresh-token=old-refresh");
    expect(JSON.parse(init.body)).toEqual({ refresh_token: "old-refresh" });
  });

  it("reads a rotated refresh token from Set-Cookie when absent from the body", async () => {
    fetchMock.mockResolvedValueOnce(
      jsonResponse({ token: ACCESS_JWT }, 200, [
        "privy-refresh-token=cookie-refresh; Path=/; HttpOnly",
      ]),
    );

    const result = await refreshPrivySession({ refreshToken: "old-refresh" });
    expect(result.refreshToken).toBe("cookie-refresh");
  });

  it("keeps the sent refresh token when none is returned", async () => {
    fetchMock.mockResolvedValueOnce(jsonResponse({ token: ACCESS_JWT }));
    const result = await refreshPrivySession({ refreshToken: "old-refresh" });
    expect(result.refreshToken).toBe("old-refresh");
  });

  it('ignores the "deprecated" body sentinel and uses the rotated cookie', async () => {
    // Privy returns refresh_token: "deprecated" in the body and the real rotated
    // token only in the Set-Cookie. Using the body sentinel would 400 the next
    // refresh, so the cookie must win.
    fetchMock.mockResolvedValueOnce(
      jsonResponse({ token: ACCESS_JWT, refresh_token: "deprecated" }, 200, [
        "privy-refresh-token=real-rotated-token; Path=/; HttpOnly",
      ]),
    );
    const result = await refreshPrivySession({ refreshToken: "old-refresh" });
    expect(result.refreshToken).toBe("real-rotated-token");
  });

  it('never returns the "deprecated" sentinel as the refresh token', async () => {
    // Body sentinel, no cookie → fall back to the token we sent, never "deprecated".
    fetchMock.mockResolvedValueOnce(
      jsonResponse({ token: ACCESS_JWT, refresh_token: "deprecated" }),
    );
    const result = await refreshPrivySession({ refreshToken: "old-refresh" });
    expect(result.refreshToken).toBe("old-refresh");
  });

  it("returns undefined linkedAccounts when the response carries no user", async () => {
    fetchMock.mockResolvedValueOnce(jsonResponse({ token: ACCESS_JWT }));
    const result = await refreshPrivySession({ refreshToken: "old-refresh" });
    expect(result.linkedAccounts).toBeUndefined();
    expect(result.did).toBeUndefined();
  });

  it("honors a custom appId and origin", async () => {
    fetchMock.mockResolvedValueOnce(jsonResponse({ token: ACCESS_JWT }));
    await refreshPrivySession({
      refreshToken: "r",
      appId: "custom-app",
      origin: "https://example.test",
    });
    const init = fetchMock.mock.calls[0][1];
    expect(init.headers["privy-app-id"]).toBe("custom-app");
    expect(init.headers.origin).toBe("https://example.test");
  });

  it("throws PrivySessionExpiredError when the token is rejected", async () => {
    fetchMock.mockResolvedValueOnce(jsonResponse({ error: "expired" }, 401));
    const err = await refreshPrivySession({ refreshToken: "old" }).catch(
      (e) => e,
    );
    expect(err).toBeInstanceOf(PrivySessionExpiredError);
    expect(err.status).toBe(401);
  });

  it("throws a distinct (non-expired) error on a 200 with no token", async () => {
    // A malformed 2xx body must not be reported as a rejected/expired token.
    fetchMock.mockResolvedValueOnce(jsonResponse({ user: { id: "x" } }, 200));
    const err = await refreshPrivySession({ refreshToken: "old" }).catch(
      (e) => e,
    );
    expect(err).toBeInstanceOf(Error);
    expect(err).not.toBeInstanceOf(PrivySessionExpiredError);
    expect(err.message).toMatch(/no token/i);
  });
});

describe("accessTokenExpiry", () => {
  it("reads the exp claim (in ms) from a JWT", () => {
    expect(accessTokenExpiry(jwt({ exp: ACCESS_EXP }))).toBe(ACCESS_EXP * 1000);
  });

  it("falls back to ~1h from now for an undecodable token", () => {
    const before = Date.now();
    const expiry = accessTokenExpiry("not.a.jwt");
    expect(expiry).toBeGreaterThanOrEqual(before + 60 * 60 * 1000 - 1000);
    expect(expiry).toBeLessThanOrEqual(Date.now() + 60 * 60 * 1000 + 1000);
  });

  it("falls back when the token has no exp claim", () => {
    const before = Date.now();
    const expiry = accessTokenExpiry(jwt({ sub: "x" }));
    expect(expiry).toBeGreaterThanOrEqual(before + 60 * 60 * 1000 - 1000);
  });

  it("falls back for a token that isn't a JWT", () => {
    const before = Date.now();
    const expiry = accessTokenExpiry("opaque-token");
    expect(expiry).toBeGreaterThanOrEqual(before + 60 * 60 * 1000 - 1000);
  });
});

describe("parseSetCookie", () => {
  it("returns the value of the named cookie", () => {
    expect(
      parseSetCookie(
        ["other=1; Path=/", "privy-refresh-token=abc123; HttpOnly; Secure"],
        "privy-refresh-token",
      ),
    ).toBe("abc123");
  });

  it("returns undefined when the cookie is absent", () => {
    expect(parseSetCookie(["other=1"], "privy-refresh-token")).toBeUndefined();
  });

  it("treats an explicitly-cleared (empty) cookie as undefined", () => {
    expect(
      parseSetCookie(
        ["privy-refresh-token=; Max-Age=0"],
        "privy-refresh-token",
      ),
    ).toBeUndefined();
  });
});

describe("findEmbeddedWallet", () => {
  it("returns the Privy embedded wallet address", () => {
    expect(
      findEmbeddedWallet([
        { type: "wallet", address: "0xExt", wallet_client_type: "metamask" },
        { type: "wallet", address: "0xEmb", wallet_client_type: "privy" },
      ]),
    ).toBe("0xEmb");
  });

  it("returns undefined when there is no embedded wallet", () => {
    expect(
      findEmbeddedWallet([
        { type: "wallet", address: "0xExt", wallet_client_type: "metamask" },
      ]),
    ).toBeUndefined();
    expect(findEmbeddedWallet([])).toBeUndefined();
  });
});

describe("sendEmailCode", () => {
  const fetchMock = vi.fn();

  beforeEach(() => {
    fetchMock.mockReset();
    vi.stubGlobal("fetch", fetchMock);
  });
  afterEach(() => {
    vi.unstubAllGlobals();
  });

  it("POSTs passwordless/init with the email and bearer token", async () => {
    fetchMock.mockResolvedValueOnce(jsonResponse({ success: true }));

    await sendEmailCode({
      accessToken: "the.access.jwt",
      email: "user@example.com",
    });

    expect(fetchMock).toHaveBeenCalledTimes(1);
    const [url, init] = fetchMock.mock.calls[0];
    expect(url).toBe("https://auth.privy.io/api/v1/passwordless/init");
    expect(init.method).toBe("POST");
    expect(init.headers["privy-app-id"]).toBe(ZORA_PRIVY_APP_ID);
    expect(init.headers.origin).toBe("https://zora.com");
    expect(init.headers["User-Agent"]).toContain("Mozilla/5.0");
    expect(init.headers.Authorization).toBe("Bearer the.access.jwt");
    const body = JSON.parse(init.body);
    expect(body).toEqual({ email: "user@example.com" });
    expect(body.token).toBeUndefined();
  });

  it("honors a custom appId, origin, and authBase", async () => {
    fetchMock.mockResolvedValueOnce(jsonResponse({ success: true }));
    await sendEmailCode({
      accessToken: "t",
      email: "user@example.com",
      appId: "custom-app",
      origin: "https://example.test",
      authBase: "https://auth.test",
    });
    const [url, init] = fetchMock.mock.calls[0];
    expect(url).toBe("https://auth.test/api/v1/passwordless/init");
    expect(init.headers["privy-app-id"]).toBe("custom-app");
    expect(init.headers.origin).toBe("https://example.test");
  });

  it("throws when Privy rejects the request", async () => {
    fetchMock.mockResolvedValueOnce(
      jsonResponse({ error: "rate limited" }, 429),
    );
    await expect(
      sendEmailCode({ accessToken: "t", email: "user@example.com" }),
    ).rejects.toThrow("passwordless/init failed (HTTP 429)");
  });

  it("resolves with no value on success", async () => {
    fetchMock.mockResolvedValueOnce(jsonResponse({ success: true }));
    await expect(
      sendEmailCode({ accessToken: "t", email: "user@example.com" }),
    ).resolves.toBeUndefined();
  });

  it("forwards the session cookie", async () => {
    fetchMock.mockResolvedValueOnce(jsonResponse({ success: true }));
    await sendEmailCode({
      accessToken: "t",
      email: "user@example.com",
      cookie: "privy-token=abc",
    });
    expect(fetchMock.mock.calls[0][1].headers.Cookie).toBe("privy-token=abc");
  });
});

describe("linkEmailWithCode", () => {
  const fetchMock = vi.fn();

  beforeEach(() => {
    fetchMock.mockReset();
    vi.stubGlobal("fetch", fetchMock);
  });
  afterEach(() => {
    vi.unstubAllGlobals();
  });

  it("POSTs passwordless/link with email+code and returns linked accounts", async () => {
    fetchMock.mockResolvedValueOnce(
      jsonResponse({
        linked_accounts: [
          { type: "email", address: "user@example.com", verified_at: 1 },
          { type: "wallet", address: "0xEmb", wallet_client_type: "privy" },
        ],
      }),
    );

    const result = await linkEmailWithCode({
      accessToken: "the.access.jwt",
      email: "user@example.com",
      code: "123456",
    });

    const [url, init] = fetchMock.mock.calls[0];
    expect(url).toBe("https://auth.privy.io/api/v1/passwordless/link");
    expect(init.method).toBe("POST");
    expect(init.headers.Authorization).toBe("Bearer the.access.jwt");
    expect(JSON.parse(init.body)).toEqual({
      email: "user@example.com",
      code: "123456",
    });
    expect(result).toEqual({
      email: "user@example.com",
      linkedAccounts: [
        { type: "email", address: "user@example.com", verified_at: 1 },
        { type: "wallet", address: "0xEmb", wallet_client_type: "privy" },
      ],
    });
  });

  it("falls back to the input email when the response has no email account", async () => {
    fetchMock.mockResolvedValueOnce(
      jsonResponse({
        linked_accounts: [
          { type: "wallet", address: "0xEmb", wallet_client_type: "privy" },
        ],
      }),
    );
    const result = await linkEmailWithCode({
      accessToken: "t",
      email: "User@Example.com",
      code: "123456",
    });
    expect(result.email).toBe("User@Example.com");
  });

  it("throws on a non-2xx response (wrong or expired code)", async () => {
    fetchMock.mockResolvedValueOnce(
      jsonResponse({ error: "invalid code" }, 400),
    );
    await expect(
      linkEmailWithCode({
        accessToken: "t",
        email: "user@example.com",
        code: "000000",
      }),
    ).rejects.toThrow("passwordless/link failed (HTTP 400)");
  });

  it("throws on a 200 with no linked_accounts", async () => {
    fetchMock.mockResolvedValueOnce(jsonResponse({}, 200));
    await expect(
      linkEmailWithCode({
        accessToken: "t",
        email: "user@example.com",
        code: "123456",
      }),
    ).rejects.toThrow("passwordless/link failed");
  });

  it("forwards the session cookie", async () => {
    fetchMock.mockResolvedValueOnce(
      jsonResponse({
        linked_accounts: [{ type: "email", address: "a@b.com" }],
      }),
    );
    await linkEmailWithCode({
      accessToken: "t",
      email: "a@b.com",
      code: "123456",
      cookie: "privy-token=abc",
    });
    expect(fetchMock.mock.calls[0][1].headers.Cookie).toBe("privy-token=abc");
  });

  it("surfaces Privy's error body in the failure message", async () => {
    fetchMock.mockResolvedValueOnce(
      jsonResponse({ error: "missing or invalid privy app session" }, 401),
    );
    await expect(
      linkEmailWithCode({
        accessToken: "t",
        email: "user@example.com",
        code: "123456",
      }),
    ).rejects.toThrow(
      "passwordless/link failed (HTTP 401): missing or invalid privy app session",
    );
  });
});

describe("hasLinkedEmail", () => {
  it("matches an existing email account case-insensitively", () => {
    expect(
      hasLinkedEmail(
        [{ type: "email", address: "User@Example.com" }],
        "user@example.com",
      ),
    ).toBe(true);
  });

  it("returns false when the email is not linked", () => {
    expect(
      hasLinkedEmail(
        [{ type: "email", address: "other@example.com" }],
        "user@example.com",
      ),
    ).toBe(false);
    expect(hasLinkedEmail([], "user@example.com")).toBe(false);
  });

  it("ignores non-email accounts that coincidentally match", () => {
    expect(
      hasLinkedEmail(
        [{ type: "wallet", address: "user@example.com" }],
        "user@example.com",
      ),
    ).toBe(false);
  });
});
