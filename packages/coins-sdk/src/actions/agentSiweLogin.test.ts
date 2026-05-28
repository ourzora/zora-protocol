import { describe, expect, it, vi, beforeEach } from "vitest";
import { privateKeyToAccount, generatePrivateKey } from "viem/accounts";
import { parseSiweMessage } from "viem/siwe";

import { agentSiweLogin } from "./agentSiweLogin";
import { setApiKey } from "../api/api-key";
import { setGraphQLBaseUrl } from "../api/agent";

const mockFetch = vi.fn();
global.fetch = mockFetch;

function okResponse(data: Record<string, unknown>) {
  return {
    ok: true,
    status: 200,
    json: async () => ({ data }),
  };
}

describe("agentSiweLogin", () => {
  beforeEach(() => {
    mockFetch.mockReset();
    setApiKey("test-api-key");
    setGraphQLBaseUrl("https://api.zora.co/universal/graphql");
  });

  it("builds a SIWE message with zora.co domain and Base chainId", async () => {
    const account = privateKeyToAccount(generatePrivateKey());

    mockFetch.mockResolvedValueOnce(
      okResponse({
        agentSiweLogin: {
          accessToken: "privy-jwt",
          expiresAt: Math.floor(Date.now() / 1000) + 3600,
        },
      }),
    );

    const result = await agentSiweLogin({ account });

    expect(result.accessToken).toBe("privy-jwt");

    const body = JSON.parse(mockFetch.mock.calls[0][1].body);
    expect(body.variables.input.walletAddress).toBe(account.address);

    const parsed = parseSiweMessage(body.variables.input.message);
    expect(parsed.domain).toBe("zora.co");
    expect(parsed.chainId).toBe(8453);
    expect(parsed.address?.toLowerCase()).toBe(account.address.toLowerCase());
    expect(parsed.uri).toBe("https://zora.co");
    expect(parsed.nonce).toMatch(/^[0-9a-f]+$/);
  });

  it("signs the SIWE message and forwards the signature", async () => {
    const account = privateKeyToAccount(generatePrivateKey());

    mockFetch.mockResolvedValueOnce(
      okResponse({
        agentSiweLogin: {
          accessToken: "tok",
          expiresAt: 9999999999,
        },
      }),
    );

    await agentSiweLogin({ account });

    const body = JSON.parse(mockFetch.mock.calls[0][1].body);
    expect(body.variables.input.signature).toMatch(/^0x[0-9a-f]+$/i);
    expect(body.variables.input.signature.length).toBeGreaterThan(2);
  });

  it("throws when the backend returns a GraphQL error", async () => {
    const account = privateKeyToAccount(generatePrivateKey());
    mockFetch.mockResolvedValueOnce({
      ok: true,
      json: async () => ({
        errors: [{ message: "wallet is not an agent account" }],
      }),
    });

    await expect(agentSiweLogin({ account })).rejects.toThrow(
      /wallet is not an agent account/,
    );
  });
});
