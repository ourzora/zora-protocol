import { describe, it, expect, vi, beforeEach } from "vitest";

vi.mock("./zora-client.js", () => ({ graphqlRequest: vi.fn() }));

import { createAgentProfile } from "./profile.js";
import { graphqlRequest } from "./zora-client.js";

const noSleep = async () => {};
const success = {
  status: 200,
  data: {
    createAgentProfile: {
      username: "keen_maple_3144",
      avatar: { originalUri: "ipfs://a" },
    },
  },
  text: "",
};
const embeddedError = {
  status: 200,
  data: null,
  errors: [{ message: "unable to create embedded wallet" }],
  text: "",
};

beforeEach(() => vi.clearAllMocks());

describe("createAgentProfile", () => {
  it("returns the profile on success", async () => {
    vi.mocked(graphqlRequest).mockResolvedValue(success);
    await expect(
      createAgentProfile("token", { sleep: noSleep }),
    ).resolves.toEqual({
      username: "keen_maple_3144",
      avatarUri: "ipfs://a",
    });
  });

  it("retries through the transient embedded-wallet error", async () => {
    vi.mocked(graphqlRequest)
      .mockResolvedValueOnce(embeddedError)
      .mockResolvedValueOnce(embeddedError)
      .mockResolvedValue(success);
    const profile = await createAgentProfile("token", { sleep: noSleep });
    expect(profile.username).toBe("keen_maple_3144");
    expect(vi.mocked(graphqlRequest).mock.calls.length).toBe(3);
  });

  it("throws after exhausting attempts", async () => {
    vi.mocked(graphqlRequest).mockResolvedValue(embeddedError);
    await expect(
      createAgentProfile("token", { attempts: 2, sleep: noSleep }),
    ).rejects.toThrow(/embedded wallet/);
  });

  it("fails fast on a non-transient error without retrying", async () => {
    const authError = {
      status: 401,
      data: null,
      errors: [{ message: "invalid or expired token" }],
      text: "",
    };
    vi.mocked(graphqlRequest).mockResolvedValue(authError);
    await expect(
      createAgentProfile("token", { sleep: noSleep }),
    ).rejects.toThrow(/invalid or expired token/);
    // Bailed after the first attempt — only the embedded-wallet race is retried.
    expect(vi.mocked(graphqlRequest).mock.calls.length).toBe(1);
  });
});
