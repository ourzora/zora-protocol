import { describe, it, expect, vi, beforeEach } from "vitest";

vi.mock("../privy.js", () => ({
  createPrivyAccount: vi.fn(),
  findEmbeddedWallet: vi.fn(),
}));
vi.mock("./profile.js", () => ({ createAgentProfile: vi.fn() }));
vi.mock("./smart-wallet.js", () => ({ provisionSmartWallet: vi.fn() }));

import { onboardAgent } from "./onboard.js";
import { createPrivyAccount, findEmbeddedWallet } from "../privy.js";
import { createAgentProfile } from "./profile.js";
import { provisionSmartWallet } from "./smart-wallet.js";

const PK = `0x${"a".repeat(64)}` as const;
const EMBEDDED = "0xEeE0000000000000000000000000000000000001" as const;
const SMART = "0xd1373e4119dD2C4C23f11F9cDc97A464790acbC8" as const;
const noSleep = async () => {};

beforeEach(() => {
  vi.clearAllMocks();
  vi.mocked(createPrivyAccount).mockResolvedValue({
    address: "0xExternal000000000000000000000000000000001",
    did: "did:privy:x",
    accessToken: "tok",
    isNewUser: true,
    linkedAccounts: [],
  });
  vi.mocked(findEmbeddedWallet).mockReturnValue(EMBEDDED);
  vi.mocked(createAgentProfile).mockResolvedValue({
    username: "keen_maple_3144",
  });
  vi.mocked(provisionSmartWallet).mockResolvedValue({
    address: SMART,
    owners: [EMBEDDED, SMART],
  });
});

describe("onboardAgent", () => {
  it("runs account → profile → smart wallet and assembles the result", async () => {
    const result = await onboardAgent({ privateKey: PK, sleep: noSleep });
    expect(result.username).toBe("keen_maple_3144");
    expect(result.smartWallet).toBe(SMART);
    expect(result.embedded).toBe(EMBEDDED);
    expect(createAgentProfile).toHaveBeenCalledTimes(1);
    expect(provisionSmartWallet).toHaveBeenCalledTimes(1);
  });

  it("re-authenticates until the embedded wallet appears", async () => {
    vi.mocked(findEmbeddedWallet)
      .mockReturnValueOnce(undefined)
      .mockReturnValueOnce(undefined)
      .mockReturnValue(EMBEDDED);
    await onboardAgent({ privateKey: PK, sleep: noSleep });
    expect(
      vi.mocked(createPrivyAccount).mock.calls.length,
    ).toBeGreaterThanOrEqual(3);
  });

  it("throws if the embedded wallet never appears", async () => {
    vi.mocked(findEmbeddedWallet).mockReturnValue(undefined);
    await expect(
      onboardAgent({ privateKey: PK, sleep: noSleep, embeddedAttempts: 2 }),
    ).rejects.toThrow(/embedded wallet/i);
  });

  it("reports isNewUser from the first sign-in, not the re-auth", async () => {
    // A genuinely new user: the first SIWE registers (is_new_user=true), but the
    // re-auth that picks up the embedded wallet returns the same user as a
    // returning one (false). The result must reflect the first sign-in.
    vi.mocked(createPrivyAccount)
      .mockResolvedValueOnce({
        address: "0xExternal000000000000000000000000000000001",
        did: "did:privy:x",
        accessToken: "tok",
        isNewUser: true,
        linkedAccounts: [],
      })
      .mockResolvedValue({
        address: "0xExternal000000000000000000000000000000001",
        did: "did:privy:x",
        accessToken: "tok",
        isNewUser: false,
        linkedAccounts: [],
      });
    vi.mocked(findEmbeddedWallet)
      .mockReturnValueOnce(undefined)
      .mockReturnValue(EMBEDDED);

    const result = await onboardAgent({ privateKey: PK, sleep: noSleep });
    expect(result.isNewUser).toBe(true);
  });
});
