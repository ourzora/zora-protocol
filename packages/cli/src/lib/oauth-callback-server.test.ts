import { describe, it, expect, afterEach } from "vitest";
import {
  startOAuthCallbackServer,
  type OAuthCallbackServer,
} from "./oauth-callback-server.js";

let server: OAuthCallbackServer | undefined;

afterEach(() => {
  server?.close();
  server = undefined;
});

// Bind to port 0 so the OS assigns a free ephemeral port — avoids clashing with
// anything (including the fixed production default) during tests.
async function start() {
  server = await startOAuthCallbackServer({ port: 0 });
  return server;
}

describe("startOAuthCallbackServer", () => {
  it("resolves with the code, state, and provider from the redirect", async () => {
    const s = await start();
    const waiting = s.waitForCallback();

    const res = await fetch(
      `${s.redirectUri}/?privy_oauth_code=the-code&privy_oauth_state=the-state&privy_oauth_provider=twitter`,
    );
    expect(res.status).toBe(200);
    expect(res.headers.get("content-type")).toContain("text/html");

    await expect(waiting).resolves.toEqual({
      code: "the-code",
      state: "the-state",
      provider: "twitter",
    });
  });

  it("rejects when the redirect carries an error", async () => {
    const s = await start();
    // Attach the rejection handler before triggering the request so the
    // rejection is never momentarily unhandled.
    const rejection = expect(s.waitForCallback()).rejects.toThrow(
      /access_denied/,
    );
    const res = await fetch(`${s.redirectUri}/?error=access_denied`);
    expect(res.status).toBe(400);
    await rejection;
  });

  it("rejects when code or state is missing", async () => {
    const s = await start();
    const rejection = expect(s.waitForCallback()).rejects.toThrow(
      /missing the authorization code/i,
    );
    await fetch(`${s.redirectUri}/?privy_oauth_code=only-code`);
    await rejection;
  });

  it("rejects on timeout", async () => {
    const s = await start();
    await expect(s.waitForCallback(10)).rejects.toThrow(/Timed out/);
  });

  it("ignores non-root probes without consuming the flow", async () => {
    const s = await start();
    const waiting = s.waitForCallback();

    const favicon = await fetch(`${s.redirectUri}/favicon.ico`);
    expect(favicon.status).toBe(404);

    await fetch(`${s.redirectUri}/?privy_oauth_code=c&privy_oauth_state=st`);
    await expect(waiting).resolves.toMatchObject({ code: "c", state: "st" });
  });

  it("surfaces an in-use port as a startup error", async () => {
    const first = await startOAuthCallbackServer({ port: 0 });
    const port = Number(new URL(first.redirectUri).port);
    await expect(startOAuthCallbackServer({ port })).rejects.toMatchObject({
      code: "EADDRINUSE",
    });
    first.close();
  });
});
