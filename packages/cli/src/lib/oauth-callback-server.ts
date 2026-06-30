import { createServer, type Server } from "node:http";
import { AddressInfo } from "node:net";

/**
 * The fixed loopback port the OAuth callback listens on. It can't be configured:
 * Privy validates `redirect_to` against the app's allowed origins, so the exact
 * `http://localhost:8976` must be registered there — a per-run port would never
 * match the allowlist.
 */
export const OAUTH_CALLBACK_PORT = 8976;

/** How long {@link OAuthCallbackServer.waitForCallback} waits before giving up. */
const DEFAULT_CALLBACK_TIMEOUT_MS = 5 * 60 * 1000;

/** The params Privy appends to the redirect URL after a social OAuth flow. */
export interface OAuthCallbackResult {
  /** `privy_oauth_code` — the authorization code to exchange at `oauth/link`. */
  code: string;
  /** `privy_oauth_state` — compare to the state sent at `oauth/init`. */
  state: string;
  /** `privy_oauth_provider` — the provider Privy authenticated, when present. */
  provider?: string;
}

export interface OAuthCallbackServer {
  /** The `redirect_to` URL to register with Privy and pass to `oauth/init`. */
  redirectUri: string;
  /** Resolve once Privy redirects to the callback; reject on error or timeout. */
  waitForCallback: (timeoutMs?: number) => Promise<OAuthCallbackResult>;
  /** Stop the server. Safe to call more than once. */
  close: () => void;
}

const SUCCESS_HTML = `<!doctype html><html><head><meta charset="utf-8"><title>Zora CLI</title>
<style>body{font-family:-apple-system,system-ui,sans-serif;background:#0a0a0a;color:#fafafa;display:flex;align-items:center;justify-content:center;height:100vh;margin:0}main{text-align:center}h1{font-weight:600}p{color:#a1a1a1}</style>
</head><body><main><h1>✓ Account linked</h1><p>You can close this tab and return to the terminal.</p></main></body></html>`;

const ERROR_HTML = `<!doctype html><html><head><meta charset="utf-8"><title>Zora CLI</title>
<style>body{font-family:-apple-system,system-ui,sans-serif;background:#0a0a0a;color:#fafafa;display:flex;align-items:center;justify-content:center;height:100vh;margin:0}main{text-align:center}h1{font-weight:600}p{color:#a1a1a1}</style>
</head><body><main><h1>Something went wrong</h1><p>Return to the terminal — the CLI will show what happened.</p></main></body></html>`;

/**
 * Start a one-shot local HTTP server on `127.0.0.1:`{@link OAUTH_CALLBACK_PORT}
 * that captures the redirect Privy sends after a social OAuth flow. The browser
 * is sent to the provider, then back here with `privy_oauth_code` /
 * `privy_oauth_state` in the query; {@link OAuthCallbackServer.waitForCallback}
 * resolves with those.
 *
 * `opts.port` exists only so tests can bind an ephemeral port — production
 * always uses the fixed {@link OAUTH_CALLBACK_PORT} (see why it can't vary there).
 *
 * @throws if the port is already in use (the caller surfaces guidance).
 */
export function startOAuthCallbackServer(
  opts: { port?: number } = {},
): Promise<OAuthCallbackServer> {
  const port = opts.port ?? OAUTH_CALLBACK_PORT;

  return new Promise((resolveServer, rejectServer) => {
    let resolveCb: ((r: OAuthCallbackResult) => void) | undefined;
    let rejectCb: ((e: Error) => void) | undefined;
    let settled = false;
    // If the redirect somehow arrives before waitForCallback() registers its
    // handlers, buffer the outcome here and deliver it when it's called — so an
    // early request is never silently dropped (which would hang until timeout).
    let pending: { ok: OAuthCallbackResult } | { err: Error } | undefined;

    const fulfill = (result: OAuthCallbackResult) => {
      if (settled) return;
      settled = true;
      if (resolveCb) resolveCb(result);
      else pending = { ok: result };
    };
    const fail = (err: Error) => {
      if (settled) return;
      settled = true;
      if (rejectCb) rejectCb(err);
      else pending = { err };
    };

    const server: Server = createServer((req, res) => {
      // Ignore favicon and any non-root probes so they don't consume the flow.
      const url = new URL(req.url ?? "/", `http://localhost:${port}`);
      if (url.pathname !== "/") {
        res.writeHead(404).end();
        return;
      }

      const error = url.searchParams.get("error");
      const code = url.searchParams.get("privy_oauth_code");
      const state = url.searchParams.get("privy_oauth_state");
      const provider =
        url.searchParams.get("privy_oauth_provider") ?? undefined;

      if (error || !code || !state) {
        res
          .writeHead(400, { "Content-Type": "text/html; charset=utf-8" })
          .end(ERROR_HTML);
        fail(
          new Error(
            error
              ? `OAuth provider returned an error: ${error}`
              : "The redirect was missing the authorization code or state.",
          ),
        );
        return;
      }

      res
        .writeHead(200, { "Content-Type": "text/html; charset=utf-8" })
        .end(SUCCESS_HTML);
      fulfill({ code, state, provider });
    });

    server.once("error", (err) => rejectServer(err));

    // Bind to loopback only — the callback must never be reachable off-host.
    server.listen(port, "127.0.0.1", () => {
      const actualPort = (server.address() as AddressInfo).port;
      resolveServer({
        redirectUri: `http://localhost:${actualPort}`,
        close: () => server.close(),
        waitForCallback: (timeoutMs = DEFAULT_CALLBACK_TIMEOUT_MS) =>
          new Promise<OAuthCallbackResult>((resolve, reject) => {
            let timer: ReturnType<typeof setTimeout> | undefined;
            resolveCb = (r) => {
              if (timer) clearTimeout(timer);
              resolve(r);
            };
            rejectCb = (e) => {
              if (timer) clearTimeout(timer);
              reject(e);
            };
            // Deliver an outcome that already arrived before this call.
            if (pending) {
              if ("ok" in pending) resolveCb(pending.ok);
              else rejectCb(pending.err);
              return;
            }
            timer = setTimeout(() => {
              if (!settled) {
                settled = true;
                reject(
                  new Error(
                    `Timed out after ${Math.round(timeoutMs / 1000)}s waiting for the browser redirect. ` +
                      "If the provider showed an error and never returned here, the authorization was likely blocked — " +
                      "check the browser tab. A common cause is that the account was already linked recently " +
                      "(some providers, e.g. X/Twitter, enforce a multi-day cooldown before re-linking).",
                  ),
                );
              }
            }, timeoutMs);
            // Don't let the pending timer keep the process alive on its own.
            timer.unref?.();
          }),
      });
    });
  });
}
