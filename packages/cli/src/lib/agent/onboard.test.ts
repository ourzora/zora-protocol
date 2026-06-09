import { describe, it, expect, vi, beforeEach } from "vitest";

vi.mock("../privy.js", () => ({ createPrivyAccount: vi.fn() }));
vi.mock("./profile.js", () => ({ createAgentProfile: vi.fn() }));

import { onboardAgent } from "./onboard.js";
import { createPrivyAccount } from "../privy.js";
import { createAgentProfile } from "./profile.js";

const PK = `0x${"a".repeat(64)}` as const;

beforeEach(() => {
  vi.clearAllMocks();
  vi.mocked(createPrivyAccount).mockResolvedValue({
    address: "0xExternal000000000000000000000000000000001",
    did: "did:privy:x",
    accessToken: "tok",
    isNewUser: true,
  });
  vi.mocked(createAgentProfile).mockResolvedValue({
    username: "keen_maple_3144",
  });
});

describe("onboardAgent", () => {
  it("creates the Privy account, then the profile, and assembles the result", async () => {
    const result = await onboardAgent({ privateKey: PK });
    expect(result).toMatchObject({
      did: "did:privy:x",
      accessToken: "tok",
      username: "keen_maple_3144",
      isNewUser: true,
    });
    expect(createPrivyAccount).toHaveBeenCalledTimes(1);
    expect(createAgentProfile).toHaveBeenCalledWith("tok");
  });

  it("reports progress for each step", async () => {
    const steps: string[] = [];
    await onboardAgent({
      privateKey: PK,
      onProgress: (step) => steps.push(step),
    });
    expect(steps).toEqual(["privy", "profile"]);
  });
});
