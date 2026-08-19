import { describe, it, expect, vi, beforeEach } from "vitest";
import type { GraphqlResult } from "./zora-client.js";

const graphqlRequest = vi.fn();
vi.mock("./zora-client.js", () => ({ graphqlRequest }));

const { createApiKey } = await import("./api-key.js");

/** Build a GraphqlResult, defaulting the fields createApiKey doesn't read. */
function result(partial: Partial<GraphqlResult>): GraphqlResult {
  return { status: 200, data: undefined, text: "", ...partial };
}

beforeEach(() => graphqlRequest.mockReset());

describe("createApiKey", () => {
  it("returns the apiKey from a successful response", async () => {
    graphqlRequest.mockResolvedValue(
      result({ data: { createApiKey: { apiKey: "zora_api_abc123" } } }),
    );

    expect(await createApiKey("tok", "AGENT_API_KEY")).toBe("zora_api_abc123");
  });

  it("forwards the token, operation name, and variables", async () => {
    graphqlRequest.mockResolvedValue(
      result({ data: { createApiKey: { apiKey: "zora_api_x" } } }),
    );

    await createApiKey("tok-123", "AGENT_API_KEY", ["a.com", "b.com"]);

    expect(graphqlRequest).toHaveBeenCalledTimes(1);
    const [token, query, operationName, variables] =
      graphqlRequest.mock.calls[0];
    expect(token).toBe("tok-123");
    expect(query).toContain("createApiKey");
    expect(operationName).toBe("CreateApiKeyMutation");
    expect(variables).toEqual({
      apiKeyName: "AGENT_API_KEY",
      hosts: ["a.com", "b.com"],
    });
  });

  it("passes hosts as null when none are provided", async () => {
    graphqlRequest.mockResolvedValue(
      result({ data: { createApiKey: { apiKey: "zora_api_x" } } }),
    );

    await createApiKey("tok", "AGENT_API_KEY");

    expect(graphqlRequest.mock.calls[0][3]).toEqual({
      apiKeyName: "AGENT_API_KEY",
      hosts: null,
    });
  });

  it("throws with the first GraphQL error message when no key is returned", async () => {
    graphqlRequest.mockResolvedValue(
      result({
        status: 403,
        data: { createApiKey: null },
        errors: [{ message: "forbidden" }],
      }),
    );

    await expect(createApiKey("tok", "AGENT_API_KEY")).rejects.toThrow(
      "createApiKey failed: forbidden",
    );
  });

  it("falls back to the HTTP status when there is no error message", async () => {
    graphqlRequest.mockResolvedValue(result({ status: 500, data: {} }));

    await expect(createApiKey("tok", "AGENT_API_KEY")).rejects.toThrow(
      "createApiKey failed: HTTP 500",
    );
  });

  it("does not throw a TypeError when createApiKey is null", async () => {
    graphqlRequest.mockResolvedValue(
      result({ status: 200, data: { createApiKey: null } }),
    );

    // Should surface the friendly failure, not "Cannot read properties of null".
    await expect(createApiKey("tok", "AGENT_API_KEY")).rejects.toThrow(
      "createApiKey failed: HTTP 200",
    );
  });
});
