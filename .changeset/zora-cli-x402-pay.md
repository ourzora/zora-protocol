---
"@zoralabs/cli": minor
---

Add a `pay` command for x402-protected resources on Base

Agents can now pay for x402 (v2) services directly from the CLI using their connected wallet. The command works in two modes:

- `zora pay --accepts '<402 accepts JSON>'` signs a payment for a suitable Base entry the wallet can afford and returns the `PAYMENT-SIGNATURE` header to attach to the retry request. It takes an x402 `accepts` array, a full 402 response body, or a base64 `PAYMENT-REQUIRED` header, and performs no network calls, so the same primitive can authorize agent-to-agent payments encoded with the x402 schema.
- `zora pay --url <url>` fetches a URL, automatically settling any x402 payment challenge and returning the resource along with the settlement transaction. The paid response is always persisted (to `--output <file>`, or a temp file otherwise) so it never needs re-fetching: text bodies are pretty-printed/inlined, and binary bodies are referenced by file path (`savedTo`) rather than dumped to the terminal or context.

Payments are made from the agent's smart wallet by default (with `--eoa` to use the EOA), prefer USDC, and respect a `--max-value` spend cap.
