import { privateKeyToAccount } from "viem/accounts";
import { createSiweMessage } from "viem/siwe";

/**
 * The Zora production Privy application id.
 *
 * An agent's Privy session is only accepted by the Zora backend if the user
 * belongs to this app, so this is the default for {@link createPrivyAccount}.
 */
export const ZORA_PRIVY_APP_ID = "clpgf04wn04hnkw0fv1m11mnb";

/** Default origin the SIWE message is scoped to (an allowed origin on the app). */
export const DEFAULT_SIWE_ORIGIN = "https://zora.com";

/** Base mainnet — the default chain for the SIWE message. */
export const DEFAULT_SIWE_CHAIN_ID = 8453;

const PRIVY_AUTH_BASE = "https://auth.privy.io";

// Privy's WAF rejects non-browser User-Agents (e.g. the default Node fetch UA),
// so we present as a browser for the auth.privy.io calls.
const BROWSER_USER_AGENT =
  "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 " +
  "(KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36";

export interface CreatePrivyAccountOptions {
  /** 0x-prefixed EOA private key used to sign the SIWE message. */
  privateKey: `0x${string}`;
  /** Privy app id. Defaults to {@link ZORA_PRIVY_APP_ID}. */
  appId?: string;
  /** Origin the SIWE message is scoped to. Defaults to {@link DEFAULT_SIWE_ORIGIN}. */
  origin?: string;
  /** EVM chain id for the SIWE message. Defaults to {@link DEFAULT_SIWE_CHAIN_ID}. */
  chainId?: number;
  /**
   * Privy `walletClientType` sent to `siwe/authenticate`. Defaults to `"metamask"`
   * — mimicking a browser MetaMask client to satisfy Privy's WAF. Override if
   * Privy's tolerance for that from a non-browser context changes.
   */
  walletClientType?: string;
  /** Privy `connectorType` sent to `siwe/authenticate`. Defaults to `"injected"`. */
  connectorType?: string;
  /** Privy auth API base. Override only for testing. */
  authBase?: string;
}

export interface PrivyAccount {
  /** The EOA address that signed in. */
  address: string;
  /** The Privy user DID (`did:privy:...`). */
  did: string;
  /**
   * Short-lived Privy access token (a JWT, ~1h). Send it as
   * `Authorization: Bearer <accessToken>` to the Zora GraphQL/tRPC endpoints.
   */
  accessToken: string;
  /** Privy identity token, when returned. */
  identityToken?: string;
  /** True when this call created a brand-new Privy user (vs. re-authenticating). */
  isNewUser: boolean;
}

interface PrivyPostResult {
  ok: boolean;
  status: number;
  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  json: any;
}

/**
 * Headlessly create (or re-authenticate) a Privy user from an EOA via
 * Sign-In-With-Ethereum, returning a Privy access token.
 *
 * This is the exact SIWE handshake the Zora web app performs in the browser,
 * run from a script instead: generate/supply an EOA, `siwe/init` to get a
 * nonce, sign the standard SIWE message, then `siwe/authenticate`. No Privy
 * dashboard, email, or OTP is required.
 *
 * Note: the target Privy app must allow `origin` and have CAPTCHA disabled for
 * this headless flow to succeed.
 */
export async function createPrivyAccount(
  opts: CreatePrivyAccountOptions,
): Promise<PrivyAccount> {
  const {
    privateKey,
    appId = ZORA_PRIVY_APP_ID,
    origin = DEFAULT_SIWE_ORIGIN,
    chainId = DEFAULT_SIWE_CHAIN_ID,
    walletClientType = "metamask",
    connectorType = "injected",
    authBase = PRIVY_AUTH_BASE,
  } = opts;

  const account = privateKeyToAccount(privateKey);
  const domain = new URL(origin).host;
  const headers = {
    "Content-Type": "application/json",
    "privy-app-id": appId,
    origin,
    "User-Agent": BROWSER_USER_AGENT,
  };

  const post = async (
    path: string,
    body: unknown,
  ): Promise<PrivyPostResult> => {
    const res = await fetch(`${authBase}${path}`, {
      method: "POST",
      headers,
      body: JSON.stringify(body),
    });
    const json = await res.json().catch(() => null);
    return { ok: res.ok, status: res.status, json };
  };

  const init = await post("/api/v1/siwe/init", { address: account.address });
  if (!init.ok || !init.json?.nonce) {
    throw new Error(`Privy siwe/init failed (HTTP ${init.status}).`);
  }

  const message = createSiweMessage({
    address: account.address,
    chainId,
    domain,
    uri: origin,
    version: "1",
    nonce: init.json.nonce,
    issuedAt: new Date(),
    statement:
      "By signing, you are proving you own this wallet and logging in. " +
      "This does not initiate a transaction or cost any fees.",
    resources: ["https://privy.io"],
  });
  const signature = await account.signMessage({ message });

  const auth = await post("/api/v1/siwe/authenticate", {
    message,
    signature,
    chainId: `eip155:${chainId}`,
    walletClientType,
    connectorType,
    mode: "login-or-sign-up",
  });
  if (!auth.ok || !auth.json?.token || !auth.json?.user?.id) {
    throw new Error(`Privy siwe/authenticate failed (HTTP ${auth.status}).`);
  }

  return {
    address: account.address,
    did: auth.json.user.id,
    accessToken: auth.json.token,
    identityToken: auth.json.identity_token,
    isNewUser: Boolean(auth.json.is_new_user),
  };
}
