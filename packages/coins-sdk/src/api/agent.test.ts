import { describe, expect, it, vi, beforeEach, afterEach } from "vitest";

import {
  setGraphQLBaseUrl,
  getGraphQLBaseUrl,
  createAgentAccountMutation,
} from "./agent";
import { setApiKey, setPrivyJwt, getAuthMeta } from "./api-key";

const mockFetch = vi.fn();
global.fetch = mockFetch;

describe("getAuthMeta", () => {
  beforeEach(() => {
    setApiKey(undefined);
    setPrivyJwt(undefined);
  });

  it("returns empty when neither api key nor JWT is set", () => {
    expect(getAuthMeta()).toEqual({});
  });

  it("injects only api-key when JWT is missing", () => {
    setApiKey("k");
    expect(getAuthMeta()).toEqual({ headers: { "api-key": "k" } });
  });

  it("injects only Authorization when api key is missing", () => {
    setPrivyJwt("j");
    expect(getAuthMeta()).toEqual({
      headers: { Authorization: "Bearer j" },
    });
  });

  it("injects both when both are set", () => {
    setApiKey("k");
    setPrivyJwt("j");
    expect(getAuthMeta()).toEqual({
      headers: { "api-key": "k", Authorization: "Bearer j" },
    });
  });
});

describe("setGraphQLBaseUrl", () => {
  afterEach(() => {
    setGraphQLBaseUrl("https://api.zora.co/universal/graphql");
  });

  it("overrides the default URL", () => {
    setGraphQLBaseUrl("https://staging.example.com/graphql");
    expect(getGraphQLBaseUrl()).toBe("https://staging.example.com/graphql");
  });
});

describe("createAgentAccountMutation", () => {
  beforeEach(() => {
    mockFetch.mockReset();
    setApiKey("k");
    setPrivyJwt(undefined);
    setGraphQLBaseUrl("https://api.zora.co/universal/graphql");
  });

  it("throws on non-2xx HTTP status", async () => {
    mockFetch.mockResolvedValueOnce({
      ok: false,
      status: 500,
      statusText: "Internal Server Error",
    });

    await expect(
      createAgentAccountMutation({
        walletAddress: "0xabc",
        username: "u",
        signature: "0xsig",
        nonce: "0x" + "0".repeat(64),
        issuedAt: 1,
        expiresAt: 2,
      }),
    ).rejects.toThrow(/500/);
  });

  it("throws when response is missing both data and errors", async () => {
    mockFetch.mockResolvedValueOnce({
      ok: true,
      json: async () => ({}),
    });

    await expect(
      createAgentAccountMutation({
        walletAddress: "0xabc",
        username: "u",
        signature: "0xsig",
        nonce: "0x" + "0".repeat(64),
        issuedAt: 1,
        expiresAt: 2,
      }),
    ).rejects.toThrow(/missing data/);
  });
});
