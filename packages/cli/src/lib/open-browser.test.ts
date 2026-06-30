import { describe, it, expect, vi, afterEach } from "vitest";

const { spawnMock } = vi.hoisted(() => ({ spawnMock: vi.fn() }));
vi.mock("node:child_process", () => ({ spawn: spawnMock }));

import { openBrowser } from "./open-browser.js";

function fakeChild() {
  return { on: vi.fn(), unref: vi.fn() };
}

describe("openBrowser", () => {
  // Reset in afterEach rather than beforeEach: resetting a throwing spy in
  // beforeEach makes vitest surface the (app-caught) throw as a failure.
  afterEach(() => {
    spawnMock.mockReset();
    vi.unstubAllGlobals();
  });

  it("uses the macOS opener", () => {
    spawnMock.mockReturnValue(fakeChild());
    vi.stubGlobal("process", { ...process, platform: "darwin" });

    expect(openBrowser("https://x.com/auth")).toBe(true);
    const [command, args] = spawnMock.mock.calls[0];
    expect(command).toBe("open");
    expect(args).toEqual(["https://x.com/auth"]);
  });

  it("uses xdg-open on linux", () => {
    spawnMock.mockReturnValue(fakeChild());
    vi.stubGlobal("process", { ...process, platform: "linux" });

    expect(openBrowser("https://x.com/auth")).toBe(true);
    expect(spawnMock.mock.calls[0][0]).toBe("xdg-open");
  });

  it("quotes the URL on Windows so cmd.exe doesn't split it on &", () => {
    spawnMock.mockReturnValue(fakeChild());
    vi.stubGlobal("process", { ...process, platform: "win32" });

    // A real OAuth URL with &-separated params — cmd.exe would truncate it at
    // the first & unless the whole URL is quoted.
    const url =
      "https://x.com/i/oauth2/authorize?code_challenge=abc&state_code=xyz&scope=users.read";
    expect(openBrowser(url)).toBe(true);
    const [command, args] = spawnMock.mock.calls[0];
    expect(command).toBe("start");
    expect(args).toEqual(['""', `"${url}"`]);
  });

  it("returns false when the launcher cannot be spawned", () => {
    spawnMock.mockImplementation(() => {
      throw new Error("ENOENT");
    });
    expect(openBrowser("https://x.com/auth")).toBe(false);
  });
});
