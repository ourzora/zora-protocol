import { describe, it, expect, vi, afterEach } from "vitest";
import {
  graphqlRequest,
  ZORA_GRAPHQL,
  ZORA_ORIGIN,
  BROWSER_USER_AGENT,
} from "./zora-client.js";

/** A `fetch` stand-in that resolves to a Response-like object. */
function mockFetch(status: number, body: string) {
  const fn = vi.fn();
  fn.mockResolvedValue({ status, text: async () => body });
  return fn;
}

afterEach(() => vi.unstubAllGlobals());

describe("graphqlRequest", () => {
  it("returns parsed data and the raw text on success", async () => {
    const body = JSON.stringify({ data: { ok: true } });
    vi.stubGlobal("fetch", mockFetch(200, body));

    const result = await graphqlRequest("tok", "query Q { ok }", "Q");

    expect(result).toEqual({
      status: 200,
      data: { ok: true },
      errors: undefined,
      text: body,
    });
  });

  it("sends the Bearer token and browser-like headers", async () => {
    const fetchMock = mockFetch(200, JSON.stringify({ data: {} }));
    vi.stubGlobal("fetch", fetchMock);

    await graphqlRequest("tok-123", "query Q { ok }", "Q", { handle: "a" });

    expect(fetchMock).toHaveBeenCalledTimes(1);
    const [url, init] = fetchMock.mock.calls[0];
    expect(url).toBe(ZORA_GRAPHQL);
    expect(init.method).toBe("POST");
    expect(init.headers).toMatchObject({
      authorization: "Bearer tok-123",
      "content-type": "application/json",
      accept: "multipart/mixed; application/json",
      origin: ZORA_ORIGIN,
      "user-agent": BROWSER_USER_AGENT,
    });
    expect(JSON.parse(init.body)).toEqual({
      query: "query Q { ok }",
      operationName: "Q",
      variables: { handle: "a" },
    });
  });

  it("omits variables from the body when none are passed", async () => {
    const fetchMock = mockFetch(200, JSON.stringify({ data: {} }));
    vi.stubGlobal("fetch", fetchMock);

    await graphqlRequest("tok", "query Q { ok }", "Q");

    expect(JSON.parse(fetchMock.mock.calls[0][1].body)).not.toHaveProperty(
      "variables",
    );
  });

  it("falls back to a non-JSON error when the body isn't JSON", async () => {
    vi.stubGlobal("fetch", mockFetch(200, "<html>blocked</html>"));

    const result = await graphqlRequest("tok", "query Q { ok }", "Q");

    expect(result.data).toBeUndefined();
    expect(result.errors?.[0]?.message).toBe("non-JSON (HTTP 200)");
    expect(result.text).toBe("<html>blocked</html>");
  });

  it("passes a 4xx status through with its GraphQL errors", async () => {
    const body = JSON.stringify({ errors: [{ message: "forbidden" }] });
    vi.stubGlobal("fetch", mockFetch(403, body));

    const result = await graphqlRequest("tok", "query Q { ok }", "Q");

    expect(result.status).toBe(403);
    expect(result.data).toBeUndefined();
    expect(result.errors?.[0]?.message).toBe("forbidden");
  });
});
