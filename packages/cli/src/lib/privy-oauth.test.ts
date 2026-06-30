import { describe, it, expect, vi, beforeEach, afterEach } from "vitest";
import { createHash } from "node:crypto";
import {
  createCodeVerifier,
  createStateCode,
  deriveCodeChallenge,
  resolveSocialProvider,
  initOAuthLink,
  linkOAuthWithCode,
  hasLinkedOAuthProvider,
  SOCIAL_PROVIDERS,
  ZORA_PRIVY_APP_ID,
} from "./privy.js";

function jsonResponse(body: unknown, status = 200) {
  return {
    ok: status >= 200 && status < 300,
    status,
    json: async () => body,
    headers: undefined,
  };
}

describe("PKCE helpers", () => {
  it("creates a base64url verifier and state of stable length", () => {
    const verifier = createCodeVerifier();
    const state = createStateCode();
    // base64url of 36 bytes => 48 chars, no padding or non-url chars.
    expect(verifier).toMatch(/^[A-Za-z0-9_-]{48}$/);
    expect(state).toMatch(/^[A-Za-z0-9_-]{48}$/);
    expect(verifier).not.toBe(createCodeVerifier());
  });

  it("derives the S256 challenge as base64url(sha256(verifier))", () => {
    const verifier = "test-verifier";
    const expected = createHash("sha256")
      .update(verifier, "utf8")
      .digest()
      .toString("base64url");
    expect(deriveCodeChallenge(verifier)).toBe(expected);
  });
});

describe("resolveSocialProvider", () => {
  it("resolves known providers case- and @-insensitively", () => {
    expect(resolveSocialProvider("twitter")).toBe(SOCIAL_PROVIDERS.twitter);
    expect(resolveSocialProvider("  TikTok ")).toBe(SOCIAL_PROVIDERS.tiktok);
    expect(resolveSocialProvider("@TWITTER")).toBe(SOCIAL_PROVIDERS.twitter);
  });

  it("returns undefined for unsupported providers", () => {
    // Instagram is intentionally unsupported here — Zora links it via a
    // separate bio-verification flow, not Privy OAuth.
    expect(resolveSocialProvider("instagram")).toBeUndefined();
    expect(resolveSocialProvider("myspace")).toBeUndefined();
  });
});

describe("initOAuthLink", () => {
  const fetchMock = vi.fn();
  beforeEach(() => {
    fetchMock.mockReset();
    vi.stubGlobal("fetch", fetchMock);
  });
  afterEach(() => vi.unstubAllGlobals());

  it("posts a PKCE init and returns the authorization URL", async () => {
    fetchMock.mockResolvedValueOnce(
      jsonResponse({ url: "https://x.com/i/oauth2/authorize?foo=bar" }),
    );

    const result = await initOAuthLink({
      provider: "twitter",
      redirectTo: "http://localhost:8976",
      accessToken: "access-jwt",
      cookie: "privy-token=abc",
      clientId: "client-abc",
    });

    expect(result.authorizationUrl).toBe(
      "https://x.com/i/oauth2/authorize?foo=bar",
    );
    expect(result.stateCode).toMatch(/^[A-Za-z0-9_-]{48}$/);
    expect(result.codeVerifier).toMatch(/^[A-Za-z0-9_-]{48}$/);

    const [url, init] = fetchMock.mock.calls[0];
    expect(url).toBe("https://auth.privy.io/api/v1/oauth/init");
    expect(init.method).toBe("POST");
    expect(init.headers["privy-app-id"]).toBe(ZORA_PRIVY_APP_ID);
    expect(init.headers["privy-client-id"]).toBe("client-abc");
    expect(init.headers.Authorization).toBe("Bearer access-jwt");
    expect(init.headers.Cookie).toBe("privy-token=abc");

    const body = JSON.parse(init.body);
    expect(body).toMatchObject({
      provider: "twitter",
      redirect_to: "http://localhost:8976",
      state_code: result.stateCode,
    });
    // The challenge must be the S256 derivation of the returned verifier.
    expect(body.code_challenge).toBe(deriveCodeChallenge(result.codeVerifier));
  });

  it("throws when Privy returns no URL", async () => {
    fetchMock.mockResolvedValueOnce(jsonResponse({ error: "nope" }, 400));
    await expect(
      initOAuthLink({
        provider: "tiktok",
        redirectTo: "http://localhost:8976",
      }),
    ).rejects.toThrow(/oauth\/init failed \(HTTP 400\): nope/);
  });
});

describe("linkOAuthWithCode", () => {
  const fetchMock = vi.fn();
  beforeEach(() => {
    fetchMock.mockReset();
    vi.stubGlobal("fetch", fetchMock);
  });
  afterEach(() => vi.unstubAllGlobals());

  it("exchanges the code with code_type 'raw' and returns linked accounts", async () => {
    fetchMock.mockResolvedValueOnce(
      jsonResponse({
        oauth_tokens: {},
        user: {
          linked_accounts: [{ type: "twitter_oauth", username: "zora" }],
        },
      }),
    );

    const result = await linkOAuthWithCode({
      accessToken: "access-jwt",
      authorizationCode: "auth-code",
      stateCode: "state-123",
      codeVerifier: "verifier-123",
      cookie: "privy-token=abc",
      clientId: "client-abc",
    });

    expect(result.linkedAccounts).toEqual([
      { type: "twitter_oauth", username: "zora" },
    ]);

    const [url, init] = fetchMock.mock.calls[0];
    expect(url).toBe("https://auth.privy.io/api/v1/oauth/link");
    expect(init.headers.Authorization).toBe("Bearer access-jwt");
    expect(init.headers.Cookie).toBe("privy-token=abc");
    expect(init.headers["privy-client-id"]).toBe("client-abc");
    expect(JSON.parse(init.body)).toEqual({
      authorization_code: "auth-code",
      code_type: "raw",
      state_code: "state-123",
      code_verifier: "verifier-123",
    });
  });

  it("throws on a non-2xx link response", async () => {
    fetchMock.mockResolvedValueOnce(
      jsonResponse({ error: "already linked elsewhere" }, 409),
    );
    await expect(
      linkOAuthWithCode({
        accessToken: "a",
        authorizationCode: "c",
        stateCode: "s",
        codeVerifier: "v",
      }),
    ).rejects.toThrow(/oauth\/link failed \(HTTP 409\): already linked/);
  });
});

describe("hasLinkedOAuthProvider", () => {
  it("matches on the provider's linked-account type", () => {
    const accounts = [{ type: "twitter_oauth" }, { type: "email" }];
    expect(hasLinkedOAuthProvider(accounts, SOCIAL_PROVIDERS.twitter)).toBe(
      true,
    );
    expect(hasLinkedOAuthProvider(accounts, SOCIAL_PROVIDERS.tiktok)).toBe(
      false,
    );
  });
});
