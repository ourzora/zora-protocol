# Sim API Agent Reference (Quick Guide)

Source: https://docs.sim.dune.com/agent-reference
Base URL: `https://api.sim.dune.com`

## Authentication

Use HTTPS and include header in every request:

```http
X-Sim-Api-Key: <YOUR_API_KEY>
```

Do not expose API keys in frontend/client code.

## Namespaces

- Stable EVM: `/v1/evm/...`
- Beta EVM/SVM: `/beta/...`

## Core rules for agent integrations

Always:

1. Pass `X-Sim-Api-Key`.
2. Pass explicit `chain_ids` for EVM (avoid implicit `default` cost expansion).
3. For SVM, use `chains` (`solana`, `eclipse`, `all`) instead of `chain_ids`.
4. Respect cursor pagination using `next_offset` only.
5. Check `warnings[]` in successful responses.
6. Retry 429/500 with exponential backoff.

Never:

- Construct your own `offset`.
- Use chain names in `chain_ids` (use numeric ids or tags only).
- Assume beta endpoints are production-safe by default.
- Hardcode API keys in browser apps.

## Recommended request patterns

### EVM balances (portfolio)

```bash
curl -s "https://api.sim.dune.com/v1/evm/balances/0x...?..." \
  -G \
  --data-urlencode "chain_ids=1,8453,42161" \
  --data-urlencode "limit=500" \
  --data-urlencode "exclude_spam_tokens=true" \
  -H "X-Sim-Api-Key: $SIM_API_KEY"
```

### EVM activity feed

```bash
curl -s "https://api.sim.dune.com/v1/evm/activity/0x..." \
  -G \
  --data-urlencode "chain_ids=1,8453" \
  --data-urlencode "activity_type=receive" \
  --data-urlencode "asset_type=erc20" \
  --data-urlencode "limit=50" \
  -H "X-Sim-Api-Key: $SIM_API_KEY"
```

### Token info + historical prices

```bash
curl -s "https://api.sim.dune.com/v1/evm/token-info/0x..." \
  -G \
  --data-urlencode "chain_ids=1" \
  --data-urlencode "historical_prices=720,168,24" \
  -H "X-Sim-Api-Key: $SIM_API_KEY"
```

## Pagination contract

1. Set `limit`.
2. Read `next_offset` from response.
3. Send exactly that value as `offset` in the next request.
4. Stop when `next_offset` is null/absent.

## Error handling

- 400: validate request params/addresses.
- 401: invalid/missing API key.
- 402: CU quota exceeded (do not retry blindly).
- 404: wrong endpoint/path params.
- 429: rate-limited, backoff and retry.
- 500: server-side issue, short backoff and retry.

Error body can contain either `error` or `message`.

## Cost control (CU)

- Omitted `chain_ids` can expand to many default chains and increase CU.
- Use explicit small chain sets for predictable spend.
- Ask before enabling webhooks in production (ongoing per-event CU usage).

## Useful links

- Docs: https://docs.sim.dune.com
- Supported chains endpoint: `GET /v1/evm/supported-chains`
- OpenAPI: https://github.com/duneanalytics/sim-docs/blob/main/openapi.json
- Dashboard: https://sim.dune.com
