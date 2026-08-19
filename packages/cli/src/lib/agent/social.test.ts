import { describe, it, expect, vi, beforeEach, afterEach } from "vitest";
import { syncSocials } from "./social.js";

function gqlResponse(body: unknown, status = 200) {
  return {
    status,
    text: async () => JSON.stringify(body),
  };
}

describe("syncSocials", () => {
  const fetchMock = vi.fn();
  const noSleep = () => Promise.resolve();

  beforeEach(() => {
    fetchMock.mockReset();
    vi.stubGlobal("fetch", fetchMock);
  });
  afterEach(() => vi.unstubAllGlobals());

  it("posts the updateSocials mutation and returns usernames + force-unlinked", async () => {
    fetchMock.mockResolvedValueOnce(
      gqlResponse({
        data: {
          updateSocials: {
            socialAccounts: {
              forceUnlinkedSocials: ["INSTAGRAM"],
              twitter: { username: "zora_agent" },
              tiktok: null,
              instagram: null,
            },
          },
        },
      }),
    );

    const result = await syncSocials("the-token");

    expect(result).toEqual({
      forceUnlinkedSocials: ["INSTAGRAM"],
      usernames: { twitter: "zora_agent" },
    });

    const [url, init] = fetchMock.mock.calls[0];
    expect(url).toBe("https://api.zora.co/universal/graphql");
    expect(init.headers.authorization).toBe("Bearer the-token");
    expect(JSON.parse(init.body).query).toContain("updateSocials");
  });

  it("retries while socialAccounts is absent, then succeeds", async () => {
    fetchMock
      .mockResolvedValueOnce(gqlResponse({ data: {} }))
      .mockResolvedValueOnce(
        gqlResponse({
          data: {
            updateSocials: { socialAccounts: { forceUnlinkedSocials: [] } },
          },
        }),
      );

    const result = await syncSocials("t", { sleep: noSleep });
    expect(result.forceUnlinkedSocials).toEqual([]);
    expect(fetchMock).toHaveBeenCalledTimes(2);
  });

  it("retries when the request throws (network error), then succeeds", async () => {
    fetchMock
      .mockRejectedValueOnce(new Error("ECONNRESET"))
      .mockResolvedValueOnce(
        gqlResponse({
          data: {
            updateSocials: { socialAccounts: { forceUnlinkedSocials: [] } },
          },
        }),
      );

    const result = await syncSocials("t", { sleep: noSleep });
    expect(result.forceUnlinkedSocials).toEqual([]);
    expect(fetchMock).toHaveBeenCalledTimes(2);
  });

  it("throws after exhausting attempts", async () => {
    fetchMock.mockResolvedValue(
      gqlResponse({ errors: [{ message: "nope" }] }, 200),
    );
    await expect(
      syncSocials("t", { attempts: 2, sleep: noSleep }),
    ).rejects.toThrow(/updateSocials failed: nope/);
    expect(fetchMock).toHaveBeenCalledTimes(2);
  });

  it("surfaces the last network error after exhausting attempts", async () => {
    fetchMock.mockRejectedValue(new Error("ETIMEDOUT"));
    await expect(
      syncSocials("t", { attempts: 2, sleep: noSleep }),
    ).rejects.toThrow(/updateSocials failed: ETIMEDOUT/);
    expect(fetchMock).toHaveBeenCalledTimes(2);
  });

  const accountsResponse = (socialAccounts: unknown) =>
    gqlResponse({ data: { updateSocials: { socialAccounts } } });

  it("awaitPlatform: retries while the username is null, returns once it lands", async () => {
    fetchMock
      .mockResolvedValueOnce(
        accountsResponse({ forceUnlinkedSocials: [], twitter: null }),
      )
      .mockResolvedValueOnce(
        accountsResponse({
          forceUnlinkedSocials: [],
          twitter: { username: "zora_agent" },
        }),
      );

    const result = await syncSocials("t", {
      awaitPlatform: "twitter",
      sleep: noSleep,
    });
    expect(result.usernames.twitter).toBe("zora_agent");
    expect(fetchMock).toHaveBeenCalledTimes(2);
  });

  it("awaitPlatform: stops immediately when the platform is force-unlinked", async () => {
    fetchMock.mockResolvedValue(
      accountsResponse({ forceUnlinkedSocials: ["TWITTER"] }),
    );

    const result = await syncSocials("t", {
      awaitPlatform: "twitter",
      sleep: noSleep,
    });
    expect(result.forceUnlinkedSocials).toEqual(["TWITTER"]);
    // Terminal state — no point retrying.
    expect(fetchMock).toHaveBeenCalledTimes(1);
  });

  it("awaitPlatform: returns the incomplete result (not throws) if it never lands", async () => {
    fetchMock.mockResolvedValue(
      accountsResponse({ forceUnlinkedSocials: [], twitter: null }),
    );

    const result = await syncSocials("t", {
      awaitPlatform: "twitter",
      attempts: 2,
      sleep: noSleep,
    });
    expect(result.usernames.twitter).toBeUndefined();
    expect(fetchMock).toHaveBeenCalledTimes(2);
  });
});
