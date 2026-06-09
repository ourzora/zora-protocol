import { describe, it, expect, vi, beforeEach, afterEach } from "vitest";
import { privateKeyToAccount } from "viem/accounts";
import {
  createPrivyAccount,
  findEmbeddedWallet,
  ZORA_PRIVY_APP_ID,
} from "./privy.js";

// Anvil test account #0 — a known-valid secp256k1 key.
const TEST_PK =
  "0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80" as const;
const EXPECTED_ADDRESS = privateKeyToAccount(TEST_PK).address;
// viem's createSiweMessage requires the nonce to be alphanumeric and >= 8 chars
// (as real Privy nonces are).
const VALID_NONCE = "abcdef1234567890";

function jsonResponse(body: unknown, status = 200) {
  return { ok: status >= 200 && status < 300, status, json: async () => body };
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
        jsonResponse({
          token: "the.access.jwt",
          identity_token: "the.identity.jwt",
          user: { id: "did:privy:abc" },
          is_new_user: true,
        }),
      );

    const result = await createPrivyAccount({ privateKey: TEST_PK });

    expect(result).toEqual({
      address: EXPECTED_ADDRESS,
      did: "did:privy:abc",
      accessToken: "the.access.jwt",
      identityToken: "the.identity.jwt",
      isNewUser: true,
      linkedAccounts: [],
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

  it("honors a custom appId, origin, and chainId", async () => {
    fetchMock
      .mockResolvedValueOnce(jsonResponse({ nonce: VALID_NONCE }))
      .mockResolvedValueOnce(
        jsonResponse({ token: "t", user: { id: "did:privy:z" } }),
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
