import { describe, it, expect, vi, beforeEach } from "vitest";

vi.mock("./agent/zora-client.js", async (importOriginal) => {
  const actual =
    await importOriginal<typeof import("./agent/zora-client.js")>();
  return { ...actual, graphqlRequest: vi.fn() };
});

import { hideCoin, unhideCoin } from "./hide.js";
import { graphqlRequest, BASE_CHAIN_ID } from "./agent/zora-client.js";

const COIN = "0x1fa82d2ccbf747e2be25339fde108bddbf9381b6";

const hideSuccess = {
  status: 200,
  data: { addHiddenCreation: { id: "1", profileId: "me", handle: "me" } },
  text: "",
};
const unhideSuccess = {
  status: 200,
  data: { removeHiddenCreation: { id: "1", profileId: "me", handle: "me" } },
  text: "",
};

beforeEach(() => vi.clearAllMocks());

describe("hideCoin", () => {
  it("sends addHiddenCreation with the correct operation and input, returns the profile", async () => {
    vi.mocked(graphqlRequest).mockResolvedValue(hideSuccess);
    await expect(hideCoin("token", COIN)).resolves.toEqual({
      profileId: "me",
      handle: "me",
    });
    const [token, , operationName, variables] =
      vi.mocked(graphqlRequest).mock.calls[0]!;
    expect(token).toBe("token");
    expect(operationName).toBe("CliHideCoin");
    expect(variables).toEqual({
      input: {
        chainId: BASE_CHAIN_ID,
        collectionAddress: COIN,
        tokenId: null,
      },
    });
  });

  it("defaults to Base but forwards an explicit chainId", async () => {
    vi.mocked(graphqlRequest).mockResolvedValue(hideSuccess);
    await hideCoin("token", COIN, 7777777);
    const variables = vi.mocked(graphqlRequest).mock.calls[0]![3] as any;
    expect(variables.input.chainId).toBe(7777777);
  });

  it("falls back to the profileId when handle is missing", async () => {
    vi.mocked(graphqlRequest).mockResolvedValue({
      status: 200,
      data: { addHiddenCreation: { id: "1", profileId: "me" } },
      text: "",
    });
    await expect(hideCoin("token", COIN)).resolves.toEqual({
      profileId: "me",
      handle: "me",
    });
  });

  it("throws with the GraphQL error message on failure", async () => {
    vi.mocked(graphqlRequest).mockResolvedValue({
      status: 200,
      data: {},
      errors: [{ message: "not allowed" }],
      text: "",
    });
    await expect(hideCoin("token", COIN)).rejects.toThrow(
      "addHiddenCreation failed: not allowed",
    );
  });

  it("throws with the HTTP status when no error message is present", async () => {
    vi.mocked(graphqlRequest).mockResolvedValue({
      status: 403,
      data: undefined,
      text: "",
    });
    await expect(hideCoin("token", COIN)).rejects.toThrow(
      "addHiddenCreation failed: HTTP 403",
    );
  });
});

describe("unhideCoin", () => {
  it("sends removeHiddenCreation with the correct operation and input", async () => {
    vi.mocked(graphqlRequest).mockResolvedValue(unhideSuccess);
    await expect(unhideCoin("token", COIN)).resolves.toEqual({
      profileId: "me",
      handle: "me",
    });
    const [, , operationName, variables] =
      vi.mocked(graphqlRequest).mock.calls[0]!;
    expect(operationName).toBe("CliUnhideCoin");
    expect((variables as any).input.collectionAddress).toBe(COIN);
  });

  it("throws with the GraphQL error message on failure", async () => {
    vi.mocked(graphqlRequest).mockResolvedValue({
      status: 200,
      data: {},
      errors: [{ message: "nope" }],
      text: "",
    });
    await expect(unhideCoin("token", COIN)).rejects.toThrow(
      "removeHiddenCreation failed: nope",
    );
  });
});
