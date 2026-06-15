import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import type { DmConsent } from "./types.js";

const fakeClient = {
  sync: vi.fn(async () => {}),
  listDms: vi.fn(async () => [] as unknown[]),
  close: vi.fn(async () => {}),
};

vi.mock("../lib/config.js", () => ({
  getSmartWalletAddress: vi.fn(
    () => "0x3333333333333333333333333333333333333333",
  ),
  getPrivateKey: vi.fn(() => "0x" + "1".repeat(64)),
  getDmCheckAt: vi.fn(() => undefined),
  saveDmCheckAt: vi.fn(),
}));
vi.mock("../lib/wallet.js", () => ({
  normalizeKey: (k: string) => (k.startsWith("0x") ? k : `0x${k}`),
}));
vi.mock("./cli-auth-provider.js", () => ({
  createCliSmartWalletProvider: vi.fn(async () => ({})),
}));
vi.mock("./identity.js", () => ({
  createSmartWalletAuth: vi.fn(() => ({
    signerSpec: {},
    getApiToken: async () => "privy.jwt.token",
  })),
}));
vi.mock("./client.js", () => ({
  createMessagingClient: vi.fn(async () => fakeClient),
}));

import {
  getSmartWalletAddress,
  getDmCheckAt,
  saveDmCheckAt,
} from "../lib/config.js";
import { createMessagingClient } from "./client.js";
import { maybeNotifyNewDms } from "./notify.js";

const summary = (sentAtMs: number, fromSelf = false) => ({
  id: "c1",
  peerAddress: "0x1111111111111111111111111111111111111111",
  consent: "allowed" as DmConsent,
  profile: null,
  lastMessage: {
    id: "m1",
    fromSelf,
    text: "gm",
    contentType: "xmtp.org/text:1.0",
    sentAtMs,
  },
});

describe("maybeNotifyNewDms", () => {
  let errSpy: ReturnType<typeof vi.spyOn>;

  beforeEach(() => {
    vi.clearAllMocks();
    fakeClient.listDms.mockResolvedValue([]);
    errSpy = vi.spyOn(process.stderr, "write").mockImplementation(() => true);
  });
  afterEach(() => {
    vi.restoreAllMocks();
    delete process.env.ZORA_DM_NOTIFY;
  });

  const stderr = () => errSpy.mock.calls.map((c) => String(c[0])).join("");

  it("does nothing when no smart wallet is configured", async () => {
    vi.mocked(getSmartWalletAddress).mockReturnValueOnce(undefined);
    await maybeNotifyNewDms();
    expect(createMessagingClient).not.toHaveBeenCalled();
    expect(saveDmCheckAt).not.toHaveBeenCalled();
  });

  it("does nothing when checked within the throttle window", async () => {
    vi.mocked(getDmCheckAt).mockReturnValueOnce(Date.now() - 1000);
    await maybeNotifyNewDms();
    expect(createMessagingClient).not.toHaveBeenCalled();
  });

  it("reports message requests that arrived since the last check", async () => {
    const baseline = Date.now() - 20 * 60_000;
    vi.mocked(getDmCheckAt).mockReturnValue(baseline);
    fakeClient.listDms.mockImplementation(async (consent?: DmConsent[]) =>
      consent?.[0] === "unknown"
        ? [summary(baseline + 5_000), summary(baseline + 6_000)]
        : [],
    );
    await maybeNotifyNewDms();
    expect(saveDmCheckAt).toHaveBeenCalledWith(expect.any(Number));
    expect(stderr()).toContain("2 new message requests");
    expect(stderr()).toContain("zora dm requests");
    expect(fakeClient.close).toHaveBeenCalled();
  });

  it("is silent on the first run even with pending requests (just sets baseline)", async () => {
    vi.mocked(getDmCheckAt).mockReturnValue(undefined);
    fakeClient.listDms.mockImplementation(async (consent?: DmConsent[]) =>
      consent?.[0] === "unknown" ? [summary(Date.now())] : [],
    );
    await maybeNotifyNewDms();
    expect(saveDmCheckAt).toHaveBeenCalled();
    expect(stderr()).toBe("");
  });

  it("does not re-report a request older than the last check", async () => {
    const baseline = Date.now() - 20 * 60_000;
    vi.mocked(getDmCheckAt).mockReturnValue(baseline);
    fakeClient.listDms.mockImplementation(async (consent?: DmConsent[]) =>
      consent?.[0] === "unknown" ? [summary(baseline - 5_000)] : [],
    );
    await maybeNotifyNewDms();
    expect(stderr()).toBe("");
  });

  it("reports conversations with messages newer than the last check", async () => {
    const baseline = Date.now() - 20 * 60_000;
    vi.mocked(getDmCheckAt).mockReturnValue(baseline);
    fakeClient.listDms.mockImplementation(async (consent?: DmConsent[]) =>
      consent?.[0] === "allowed"
        ? [summary(baseline + 5_000), summary(baseline - 5_000)]
        : [],
    );
    await maybeNotifyNewDms();
    expect(stderr()).toContain("new messages in 1 conversation");
    expect(stderr()).toContain("zora dm list");
  });

  it("stays silent when there is nothing new", async () => {
    vi.mocked(getDmCheckAt).mockReturnValue(Date.now() - 20 * 60_000);
    fakeClient.listDms.mockResolvedValue([]);
    await maybeNotifyNewDms();
    expect(stderr()).toBe("");
  });

  describe("ZORA_DM_NOTIFY=always (force)", () => {
    beforeEach(() => {
      process.env.ZORA_DM_NOTIFY = "always";
    });

    it("bypasses the throttle and reports 'no new' instead of staying silent", async () => {
      vi.mocked(getDmCheckAt).mockReturnValue(Date.now() - 1000); // within throttle
      await maybeNotifyNewDms();
      expect(createMessagingClient).toHaveBeenCalled();
      expect(stderr()).toContain("No new DMs or message requests");
    });

    it("does not disturb the real throttle timestamp", async () => {
      await maybeNotifyNewDms();
      expect(saveDmCheckAt).not.toHaveBeenCalled();
    });

    it("explains why it skipped when no smart wallet is set up", async () => {
      vi.mocked(getSmartWalletAddress).mockReturnValueOnce(undefined);
      await maybeNotifyNewDms();
      expect(createMessagingClient).not.toHaveBeenCalled();
      expect(stderr()).toContain("no smart wallet");
    });
  });
});
