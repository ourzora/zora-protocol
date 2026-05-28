import { describe, expect, it, vi, beforeEach, afterEach } from "vitest";
import { privateKeyToAccount, generatePrivateKey } from "viem/accounts";
import { base } from "viem/chains";

import { createAgentAccount } from "./createAgentAccount";
import { setApiKey, setPrivyJwt } from "../api/api-key";
import { setGraphQLBaseUrl } from "../api/agent";

const mockFetch = vi.fn();
global.fetch = mockFetch;

function okGraphQLResponse(data: Record<string, unknown>) {
  return {
    ok: true,
    status: 200,
    json: async () => ({ data }),
  };
}

function errorGraphQLResponse(message: string) {
  return {
    ok: true,
    status: 200,
    json: async () => ({ errors: [{ message }] }),
  };
}

describe("createAgentAccount", () => {
  beforeEach(() => {
    mockFetch.mockReset();
    setApiKey("test-api-key");
    setPrivyJwt(undefined);
    setGraphQLBaseUrl("https://api.zora.co/universal/graphql");
  });

  afterEach(() => {
    setApiKey(undefined);
  });

  it("signs the EIP-712 payload and posts the mutation", async () => {
    const account = privateKeyToAccount(generatePrivateKey());

    mockFetch.mockResolvedValueOnce(
      okGraphQLResponse({
        createAgentAccount: {
          accountId: "0x123",
          username: "my-bot",
          handle: "my-bot",
          bio: "Automated Zora agent.",
          accountType: "agent",
          displayName: "my-bot",
          avatar: null,
        },
      }),
    );

    const result = await createAgentAccount({
      account,
      username: "my-bot",
    });

    expect(result.username).toBe("my-bot");
    expect(result.accountType).toBe("agent");

    expect(mockFetch).toHaveBeenCalledOnce();
    const [url, init] = mockFetch.mock.calls[0];
    expect(url).toBe("https://api.zora.co/universal/graphql");
    expect(init.method).toBe("POST");
    expect(init.headers["Content-Type"]).toBe("application/json");
    expect(init.headers["api-key"]).toBe("test-api-key");

    const body = JSON.parse(init.body);
    expect(body.query).toContain("CreateAgentAccount");
    expect(body.variables.input.walletAddress).toBe(account.address);
    expect(body.variables.input.username).toBe("my-bot");
    expect(body.variables.input.signature).toMatch(/^0x[0-9a-f]+$/i);
    expect(body.variables.input.nonce).toMatch(/^0x[0-9a-f]{64}$/);
    expect(body.variables.input.expiresAt).toBeGreaterThan(
      body.variables.input.issuedAt,
    );
  });

  it("generates a fresh nonce on each invocation", async () => {
    const account = privateKeyToAccount(generatePrivateKey());

    mockFetch.mockResolvedValue(
      okGraphQLResponse({
        createAgentAccount: {
          accountId: "0x123",
          username: "u",
          handle: "u",
          bio: "",
          accountType: "agent",
          displayName: null,
          avatar: null,
        },
      }),
    );

    await createAgentAccount({ account, username: "u1" });
    await createAgentAccount({ account, username: "u2" });

    const nonce1 = JSON.parse(mockFetch.mock.calls[0][1].body).variables.input
      .nonce;
    const nonce2 = JSON.parse(mockFetch.mock.calls[1][1].body).variables.input
      .nonce;
    expect(nonce1).not.toBe(nonce2);
  });

  it("forwards optional profile fields", async () => {
    const account = privateKeyToAccount(generatePrivateKey());

    mockFetch.mockResolvedValueOnce(
      okGraphQLResponse({
        createAgentAccount: {
          accountId: "0x1",
          username: "u",
          handle: "u",
          bio: "custom",
          accountType: "agent",
          displayName: "Custom",
          avatar: null,
        },
      }),
    );

    await createAgentAccount({
      account,
      username: "u",
      displayName: "Custom",
      bio: "custom",
      avatarUri: "ipfs://bafy123",
    });

    const body = JSON.parse(mockFetch.mock.calls[0][1].body);
    expect(body.variables.input.displayName).toBe("Custom");
    expect(body.variables.input.bio).toBe("custom");
    expect(body.variables.input.avatarUri).toBe("ipfs://bafy123");
  });

  it("includes Authorization header when Privy JWT is set", async () => {
    setPrivyJwt("jwt-test-token");
    const account = privateKeyToAccount(generatePrivateKey());

    mockFetch.mockResolvedValueOnce(
      okGraphQLResponse({
        createAgentAccount: {
          accountId: "0x1",
          username: "u",
          handle: "u",
          bio: "",
          accountType: "agent",
          displayName: null,
          avatar: null,
        },
      }),
    );

    await createAgentAccount({ account, username: "u" });

    const headers = mockFetch.mock.calls[0][1].headers;
    expect(headers["Authorization"]).toBe("Bearer jwt-test-token");
    expect(headers["api-key"]).toBe("test-api-key");
  });

  it("throws when the GraphQL response contains errors", async () => {
    const account = privateKeyToAccount(generatePrivateKey());
    mockFetch.mockResolvedValueOnce(errorGraphQLResponse("username unavailable"));

    await expect(
      createAgentAccount({ account, username: "taken" }),
    ).rejects.toThrow(/username unavailable/);
  });

  it("respects setGraphQLBaseUrl for staging", async () => {
    setGraphQLBaseUrl("https://api.staging.zora.co/universal/graphql");
    const account = privateKeyToAccount(generatePrivateKey());

    mockFetch.mockResolvedValueOnce(
      okGraphQLResponse({
        createAgentAccount: {
          accountId: "0x1",
          username: "u",
          handle: "u",
          bio: "",
          accountType: "agent",
          displayName: null,
          avatar: null,
        },
      }),
    );

    await createAgentAccount({ account, username: "u" });
    expect(mockFetch.mock.calls[0][0]).toBe(
      "https://api.staging.zora.co/universal/graphql",
    );
  });

  it("signed payload binds chainId to Base", async () => {
    const account = privateKeyToAccount(generatePrivateKey());
    // Use a spy on signTypedData to capture the typed-data object
    const spy = vi.spyOn(account, "signTypedData");
    mockFetch.mockResolvedValueOnce(
      okGraphQLResponse({
        createAgentAccount: {
          accountId: "0x1",
          username: "u",
          handle: "u",
          bio: "",
          accountType: "agent",
          displayName: null,
          avatar: null,
        },
      }),
    );

    await createAgentAccount({ account, username: "u" });

    expect(spy).toHaveBeenCalledOnce();
    const callArgs = spy.mock.calls[0][0];
    expect(callArgs.domain.chainId).toBe(base.id);
    expect(callArgs.domain.name).toBe("Zora Agent Account");
    expect(callArgs.primaryType).toBe("CreateAgentAccount");
  });
});
