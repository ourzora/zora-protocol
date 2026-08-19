import { describe, it, expect, vi, beforeEach } from "vitest";

vi.mock("./agent/zora-client.js", () => ({ graphqlRequest: vi.fn() }));

import { followProfile, unfollowProfile } from "./follow.js";
import { graphqlRequest } from "./agent/zora-client.js";

const followSuccess = {
  status: 200,
  data: {
    follow: {
      handle: "wbnns",
      profileId: "wbnns",
      vcFollowingStatus: "FOLLOWING",
    },
  },
  text: "",
};

const unfollowSuccess = {
  status: 200,
  data: {
    unfollow: {
      handle: "wbnns",
      profileId: "wbnns",
      vcFollowingStatus: "NOT_FOLLOWING",
    },
  },
  text: "",
};

beforeEach(() => vi.clearAllMocks());

describe("followProfile", () => {
  it("returns the target profile and viewer follow status on success", async () => {
    vi.mocked(graphqlRequest).mockResolvedValue(followSuccess);
    await expect(followProfile("token", "wbnns")).resolves.toEqual({
      handle: "wbnns",
      profileId: "wbnns",
      followingStatus: "FOLLOWING",
    });
  });

  it("forwards the identifier as the followeeId variable", async () => {
    vi.mocked(graphqlRequest).mockResolvedValue(followSuccess);
    await followProfile("token", "wbnns");
    const [token, , operationName, variables] =
      vi.mocked(graphqlRequest).mock.calls[0];
    expect(token).toBe("token");
    expect(operationName).toBe("CliFollow");
    expect(variables).toEqual({ followeeId: "wbnns" });
  });

  it("falls back to profileId when the target has no handle", async () => {
    vi.mocked(graphqlRequest).mockResolvedValue({
      status: 200,
      data: {
        follow: {
          profileId: "0xabc0000000000000000000000000000000000001",
          vcFollowingStatus: "FOLLOWING",
        },
      },
      text: "",
    });
    const result = await followProfile(
      "token",
      "0xabc0000000000000000000000000000000000001",
    );
    expect(result.handle).toBe("0xabc0000000000000000000000000000000000001");
  });

  it("defaults an absent status to UNKNOWN", async () => {
    vi.mocked(graphqlRequest).mockResolvedValue({
      status: 200,
      data: { follow: { handle: "wbnns", profileId: "wbnns" } },
      text: "",
    });
    await expect(followProfile("token", "wbnns")).resolves.toMatchObject({
      followingStatus: "UNKNOWN",
    });
  });

  it("throws with the server error message", async () => {
    vi.mocked(graphqlRequest).mockResolvedValue({
      status: 200,
      data: null,
      errors: [{ message: "You cannot follow yourself." }],
      text: "",
    });
    await expect(followProfile("token", "me")).rejects.toThrow(
      /follow failed: You cannot follow yourself/,
    );
  });

  it("throws on an HTTP error with no error message", async () => {
    vi.mocked(graphqlRequest).mockResolvedValue({
      status: 401,
      data: null,
      text: "",
    });
    await expect(followProfile("token", "wbnns")).rejects.toThrow(/HTTP 401/);
  });
});

describe("unfollowProfile", () => {
  it("returns the target profile and viewer follow status on success", async () => {
    vi.mocked(graphqlRequest).mockResolvedValue(unfollowSuccess);
    await expect(unfollowProfile("token", "wbnns")).resolves.toEqual({
      handle: "wbnns",
      profileId: "wbnns",
      followingStatus: "NOT_FOLLOWING",
    });
  });

  it("uses the unfollow mutation and operation name", async () => {
    vi.mocked(graphqlRequest).mockResolvedValue(unfollowSuccess);
    await unfollowProfile("token", "wbnns");
    const [, query, operationName] = vi.mocked(graphqlRequest).mock.calls[0];
    expect(operationName).toBe("CliUnfollow");
    expect(query).toContain("unfollow(followeeId:");
  });

  it("throws with the server error message", async () => {
    vi.mocked(graphqlRequest).mockResolvedValue({
      status: 200,
      data: null,
      errors: [{ message: "Profile not found." }],
      text: "",
    });
    await expect(unfollowProfile("token", "ghost")).rejects.toThrow(
      /unfollow failed: Profile not found/,
    );
  });
});
