---
name: pay
description: >-
  Pay for x402-protected resources and APIs on Base from the agent's connected Zora wallet. Use whenever a URL or API responds with HTTP 402 Payment Required, or the user wants to access, unlock, or buy access to a paid/paywalled endpoint — phrasings like "pay for this API", "fetch this x402 resource", "this endpoint needs payment", "I got a 402", "unlock this content", "pay N USDC to access ...", "buy access to ...", "use my wallet to pay for this service", or "call this paid API". Also use to settle an x402-schema payment request received out-of-band (e.g. agent-to-agent over a DM). The command signs the payment (`PAYMENT-SIGNATURE` header) and can fetch-and-pay a URL in one shot.
compatibility: Requires the Zora CLI (@zoralabs/cli).
---

# Pay (x402) Skill

**Skill version 1.0.0**

## What This Skill Does

The `zora pay` command lets you pay for **x402**-protected resources on the Base network using the agent's connected wallet (smart wallet by default). [x402](https://docs.x402.org) is an open standard where a server answers a request with **HTTP 402 Payment Required** plus the payment options it accepts; the client signs a stablecoin payment (e.g. USDC) and retries with proof of payment, and the server settles it on-chain and returns the resource.

This skill speaks **x402 v2**. It supports two modes:

- **Pay-and-fetch (`--url`)** — make the request, automatically settle any 402 challenge, and return the resource. Use this when you just want the paid content.
- **Sign-only (`--accepts`)** — given an x402 `accepts` array (or a 402 response body, or a base64 `PAYMENT-REQUIRED` header), produce the signed `PAYMENT-SIGNATURE` header without any network call. Use this when **you** already made the HTTP request and got a 402, or when settling an x402-schema payment request that arrived some other way (e.g. encoded in a DM, for agent-to-agent payments).

## When To Use It

Reach for this skill when:

- A `fetch`/`curl`/API call returns **402 Payment Required**, or a service's docs say it's "x402" / "pay-per-call" / "paid API".
- The user asks to **access, unlock, or buy** a paywalled URL, dataset, image, model, or report — e.g. _"pay for this API"_, _"get me the data behind this paid endpoint"_, _"unlock this"_, _"pay 1 USDC and fetch X"_, _"I got a 402 from \<url\>"_.
- The user hands you an x402 payment request (JSON following the x402 schema) to settle.
- Another agent sends a payment request and you need to produce proof of payment to send back.

If the user just wants to send tokens to an address or profile (not pay for a resource), use the `send` command instead.

## Requirements

If the Zora CLI basics aren't already in your context, load the core `zora-cli` skill first (CLI invocation, wallet/account setup, `--json` response shapes, error handling). Commands below use `zora` as shorthand for `npx @zoralabs/cli@latest`.

- Payments settle in a stablecoin (typically **USDC**) on **Base mainnet**. The paying wallet must hold enough of the asset the server requests. Only the `exact` scheme on Base is supported.
- Payment is made from the agent's **smart wallet** by default. Pass `--eoa` to pay from the EOA instead (use this if a server's facilitator rejects the smart-wallet signature).
- **Always run with `--json`** and inspect the result. Always pass **`--max-value`** as a spend cap (see Safety).

## Options

| Option              | Purpose                                                                                                                                              |
| ------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------- |
| `--url <url>`       | Pay-and-fetch: request the URL, settle any 402, return the resource.                                                                                 |
| `--accepts <json>`  | Sign-only: an `accepts` array, a full 402 body, a base64 `PAYMENT-REQUIRED` header, `@file`, or `-` (stdin). Outputs the `PAYMENT-SIGNATURE` header. |
| `--method <method>` | HTTP method for `--url` mode (default `GET`).                                                                                                        |
| `--data <body>`     | JSON request body for `--url` mode.                                                                                                                  |
| `--asset <0x...>`   | Prefer paying with this ERC-20 asset when the server accepts several.                                                                                |
| `--max-value <n>`   | Maximum payment in the asset's **atomic units**; refuse to pay above it. **Always set this.**                                                        |
| `--output <file>`   | Write the response body straight to a file (raw bytes; best for binary).                                                                             |
| `--eoa`             | Pay from the EOA instead of the smart wallet.                                                                                                        |
| `--yes`             | Skip the confirmation prompt (you run non-interactively, so include this).                                                                           |

`--url` and `--accepts` are mutually exclusive.

### Atomic units for `--max-value`

`--max-value` is in the asset's smallest unit. **USDC has 6 decimals**, so:

- `$0.01` → `--max-value 10000`
- `$0.10` → `--max-value 100000`
- `$1.00` → `--max-value 1000000`

## Examples

```bash
# Pay-and-fetch a paid API, capped at $0.10 of USDC, save large/binary bodies to disk
zora pay --url 'https://api.example.com/paid/endpoint' --max-value 100000 --yes --json
zora pay --url 'https://api.example.com/report.pdf' --max-value 1000000 --output report.pdf --yes --json

# POST with a body
zora pay --url 'https://api.example.com/generate' --method POST --data '{"prompt":"..."}' --max-value 500000 --yes --json

# Sign-only: you already fetched the URL yourself and got a 402 — sign its accepts and retry with the header
zora pay --accepts '<the 402 response body JSON>' --max-value 100000 --yes --json
echo "$PAYMENT_REQUIRED_HEADER_BASE64" | zora pay --accepts - --max-value 100000 --yes --json

# Pay from the EOA instead of the smart wallet
zora pay --url 'https://api.example.com/paid' --max-value 100000 --eoa --yes --json
```

## Handling the response (`--url` mode)

The `--json` result is **self-describing**, and the (already-paid) response is **always written to disk** so you never have to re-fetch it. When you don't pass `--output`, the body is saved to a temp file and its path is returned in `savedTo`:

```json
// Text response (encoding "utf8"): body is inlined AND saved to a temp file
{
  "action": "pay",
  "mode": "fetch",
  "url": "https://api.example.com/paid/endpoint",
  "status": 200,
  "contentType": "application/json",
  "paid": true,
  "settlement": { "success": true, "transaction": "0x…", "network": "eip155:8453", "payer": "0x…" },
  "encoding": "utf8",
  "body": { "...": "parsed JSON, or a string for non-JSON text" },
  "savedTo": "/tmp/zora-x402-XXXX/x402-response.json",
  "bytes": 123
}

// Binary response (encoding "binary"): referenced by file path only — no inline bytes
{
  "action": "pay", "mode": "fetch", "status": 200,
  "contentType": "image/png",
  "paid": true,
  "settlement": { "success": true, "transaction": "0x…" },
  "encoding": "binary",
  "savedTo": "/tmp/zora-x402-XXXX/x402-response.png",
  "bytes": 81234
}
```

**Critical: never re-run a successful paid request to change how output is handled — that pays again.** The first run already captured the resource to `savedTo`. Use `contentType` and `encoding` to decide how to surface it (and when the user's intent isn't clear, **ask** whether to show, summarize, or save it — and where):

- **Text** (`encoding: "utf8"` — JSON, plain text, HTML, CSV, XML): the content is inlined in `body`, so **present it / print it to the terminal** (pretty-print JSON) or summarize it. For very large bodies, read from `savedTo` instead of relying on the inlined copy. If the user wants it kept, move `savedTo` to their chosen path.
- **Binary** (`encoding: "binary"` — images, PDFs, audio, archives, model weights): the bytes are **not** in the JSON (to avoid bloating your context) — they're at `savedTo`. **Move or copy that file** to the destination the user wants (a local `mv`/`cp`); never decode or re-fetch. The extension is inferred from the content type.

You do **not** need to infer binary-ness — `encoding` and `contentType` state it explicitly.

> **Tip:** Passing `--output <path>` up front writes the body straight to that path (returned as `savedTo`) and skips the temp file — handy when the user already told you where to put it. Either way the resource is saved on the **first** run, so there's never a reason to repeat a paid request.

## Handling the response (`--accepts` sign-only mode)

`--json` returns the header to attach to your retry request:

```json
{
  "action": "pay",
  "mode": "build",
  "headerName": "PAYMENT-SIGNATURE",
  "header": "<base64 payment payload>",
  "requirement": {
    "asset": "0x…",
    "amount": "10000",
    "payTo": "0x…",
    "network": "eip155:8453",
    "amountFormatted": "0.01",
    "symbol": "USDC"
  },
  "payerWallet": "smart-wallet"
}
```

Attach `headerName: header` to your retried HTTP request (i.e. set the `PAYMENT-SIGNATURE` request header). The server settles it and returns the resource; the settlement transaction hash comes back to you in the server's `PAYMENT-RESPONSE` header.

## Safety

- **Never pay twice.** A successful payment is final and settles real funds. The first run always saves the resource (`savedTo`, plus inline `body` for text), so never re-run a paid `--url` request just to change how the output is handled — read `body`/`savedTo` from the first response instead.
- **Always cap spend with `--max-value`.** Derive it from what the user authorized; convert to atomic units (USDC = 6 decimals). If the server's requested amount exceeds the cap, the command refuses without paying.
- **Confirm intent for non-trivial amounts.** Surface the amount and recipient (`payTo`) before paying when the cost isn't clearly pre-approved.
- **Errors:** if the response contains `"error"`, or `paid` is `false` on an endpoint you expected to be paid, report it — common causes are insufficient balance on Base, an amount above `--max-value`, no `exact`-on-Base option offered, or a facilitator that rejects the smart-wallet signature (retry with `--eoa`).
