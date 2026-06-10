import { describe, it, expect, vi, beforeEach } from "vitest";

vi.mock("./zora-client.js", () => ({ graphqlRequest: vi.fn() }));

import { updateAgentProfile } from "./update-profile.js";
import { graphqlRequest } from "./zora-client.js";

const success = {
  status: 200,
  data: {
    updateAgentProfile: {
      username: "brave_falcon_4242",
      avatar: { originalUri: "ipfs://new" },
    },
  },
  text: "",
};

beforeEach(() => vi.clearAllMocks());

describe("updateAgentProfile", () => {
  it("returns the updated profile on success", async () => {
    vi.mocked(graphqlRequest).mockResolvedValue(success);
    await expect(
      updateAgentProfile("token", {
        username: "brave_falcon_4242",
        bio: "gm",
        avatarUri: "ipfs://new",
      }),
    ).resolves.toEqual({
      username: "brave_falcon_4242",
      avatarUri: "ipfs://new",
    });
  });

  it("forwards the fields as the `input` variable", async () => {
    vi.mocked(graphqlRequest).mockResolvedValue(success);
    await updateAgentProfile("token", { bio: "gm" });
    const [token, , operationName, variables] =
      vi.mocked(graphqlRequest).mock.calls[0];
    expect(token).toBe("token");
    expect(operationName).toBe("UpdateAgentProfile");
    expect(variables).toEqual({ input: { bio: "gm" } });
  });

  it("forwards an empty string so the field is cleared server-side", async () => {
    vi.mocked(graphqlRequest).mockResolvedValue(success);
    await updateAgentProfile("token", { bio: "" });
    const variables = vi.mocked(graphqlRequest).mock.calls[0][3];
    expect(variables).toEqual({ input: { bio: "" } });
  });

  it("throws with the server error message", async () => {
    vi.mocked(graphqlRequest).mockResolvedValue({
      status: 200,
      data: null,
      errors: [{ message: "Username brave_falcon_4242 is taken." }],
      text: "",
    });
    await expect(
      updateAgentProfile("token", { username: "brave_falcon_4242" }),
    ).rejects.toThrow(/is taken/);
  });

  it("throws on an HTTP error with no error message", async () => {
    vi.mocked(graphqlRequest).mockResolvedValue({
      status: 401,
      data: null,
      text: "",
    });
    await expect(updateAgentProfile("token", { bio: "gm" })).rejects.toThrow(
      /HTTP 401/,
    );
  });
});
