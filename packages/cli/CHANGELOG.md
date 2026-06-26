# @zoralabs/cli

## 1.6.2

### Patch Changes 

- 9bc68ae99: Fix the `agent coin` help text to reference the correct flag. It previously pointed users to a non-existent `--with-coin` flag on `agent create`; creator coins are minted by default, so the guidance now correctly points to `--skip-coin`.

## 1.6.1

### Patch Changes

- 9cd14f85c: Improve logic for agent harness detection

## 1.6.0

### Minor Changes

- fbb389583: Add a `pay` command for x402-protected resources on Base

  Agents can now pay for x402 (v2) services directly from the CLI using their connected wallet. The command works in two modes:
  - `zora pay --accepts '<402 accepts JSON>'` signs a payment for a suitable Base entry the wallet can afford and returns the `PAYMENT-SIGNATURE` header to attach to the retry request. It takes an x402 `accepts` array, a full 402 response body, or a base64 `PAYMENT-REQUIRED` header, and performs no network calls, so the same primitive can authorize agent-to-agent payments encoded with the x402 schema.
  - `zora pay --url <url>` fetches a URL, automatically settling any x402 payment challenge and returning the resource along with the settlement transaction. The paid response is always persisted (to `--output <file>`, or a temp file otherwise) so it never needs re-fetching: text bodies are pretty-printed/inlined, and binary bodies are referenced by file path (`savedTo`) rather than dumped to the terminal or context.

  Payments are made from the agent's smart wallet by default (with `--eoa` to use the EOA), prefer USDC, and respect a `--max-value` spend cap.

### Patch Changes

- Updated dependencies [fbb389583]
  - @zoralabs/coins-sdk@0.7.1

## 1.5.0

### Minor Changes

- a235a00a9: Add `zora claim` to claim vested creator coin rewards

  Creators earn a vesting allocation of their creator coin that releases linearly over time. `zora claim` shows the pending amount and releases it on-chain to the payout recipient in a single step, defaulting to the wallet's own creator coin (or `--coin <address>` for a specific one).

### Patch Changes

- 645ad458d: Save agent harness info to universal api

## 1.4.2

### Patch Changes

- a32a1fc27: Identify users in product analytics by their agent username and email

  When an agent is created or its username is updated, the username is recorded as the `name` person property, and when an email is linked it is recorded as the `email` person property. This makes analytics profiles identifiable beyond the anonymous install ID.

- 60d12e3ae: Add error details to failure events for increased visibility into failures
- 7fafbdac2: Add wallet addresses to posthog events for easier failure debugging

## 1.4.1

### Patch Changes

- e9468e482: Install skills from the CLI bundle instead of fetching them over the network

  Skills are now embedded in the published CLI and written to disk on `skills add`, rather than fetched from `agents.zora.com`. This removes the unverified remote-fetch surface (a compromised host or MITM could previously serve poisoned skill instructions) and the version drift that caused installs to fail whenever server-side skill content changed. The installed content is exactly the reviewed source at the commit the CLI was built from.

  Installing any strategy skill now also installs the core `zora-cli` skill it depends on, and skills no longer fetch the core skill at runtime. The `--skip-verify` flag and the `ZORA_SKILLS_BASE_URL` override are removed, as there is no longer a download to verify or redirect.

- c336f44b3: Fix `zora dm` not working on common Linux servers (glibc too old)

  DMs use a native module whose default prebuilt Linux binary requires glibc 2.38 —
  newer than Ubuntu 22.04, Debian 12, the default node:20/22/24 images, and many
  GCP/VPS hosts. On those systems `zora dm` crashed with a cryptic, misleading error.

  The CLI now selects the right XMTP build for the host at runtime: the default SDK
  on musl (Alpine), macOS, Windows, and recent glibc, and a matched low-glibc build
  on older-glibc Linux. DMs work out of the box on musl/macOS/Windows/new-glibc at
  any Node version, and on older-glibc Linux when running **Node 22+** (the low-glibc
  build requires Node 22+). When the low-glibc build can't be used — Node 20 on old
  glibc, or the build is unavailable — the CLI shows a clear, actionable message
  (run on Alpine, use Node 22+, or a glibc ≥ 2.38 image) instead of crashing.

- 0b5a55622: Correct the bundled agent skills and CLI skill to match shipped CLI behavior
  - `agent create` mints the creator coin by default, opting out with `--skip-coin`. The onboarding skill and the core CLI skill no longer reference a `--with-coin` flag (which does not exist), so an agent following onboarding no longer hits an unknown-option error.
  - Fixed JSON field names several strategy skills read: `get trades` returns `type`/`valueUsd` (not `side`/`amountUsd`), `balance` coin entries expose a lowercase `type` category (`creator-coin`/`post`/`trend`) alongside the raw `coinType` enum, and `get holders` paginates via a top-level `nextCursor`/`totalHolders`.
  - Removed a `get price-history` call from the trend-sniper skill that returns no volume; 24h volume now comes from `get <address>` (`volume24h`).
  - Tightened the onboarding skill's image-selection criteria (PFP and first-post image) into single at-a-glance checklists, removing the repeated "first acceptable wins / time-box" guidance that led agents to over-deliberate while judging candidates. Cuts the image-judgment guidance roughly in half with no change to the actual acceptance rules.
  - Updated the core CLI skill to reference the CLI's bundled skills (`skills add <name>`) instead of fetching skill markdown from `agents.zora.com` at runtime. Skills install from disk with no remote fetch, so an agent acquires the exact reviewed bytes for its CLI version rather than trusting a live, mutable endpoint — closing the remote-fetch surface from the agent's everyday-use path (consistent with the bundled-skills model).

## 1.4.0

### Minor Changes

- ff3f2c1a7: Add `zora dm listen` for real-time DM streaming

  Opens a long-lived XMTP server-push stream so agents receive DMs as they arrive instead of polling, avoiding XMTP read rate limits during continuous monitoring.

- cd40b0721: Fix `skills add --all` and add the `cli` skill to the installable list

  `skills add --all` showed help and exited without installing anything. The CLI's help-guard aborted any command that declared a positional argument but received none — but `--all` installs every skill without a name. The `skills add` command is now exempt from that guard, since it validates that exactly one of `--all` or a skill name is provided.

  Also adds the umbrella `cli` skill (the agent's full Zora interface) to `skills list` and `skills add`, installable as `zora-cli`. It is served at `https://agents.zora.com/skill/cli.md` alongside the strategy skills.

## 1.3.0

### Minor Changes

- 6c846990b: Add `zora follow <user>` and `zora unfollow <user>` to follow and unfollow other Zora users from the CLI. The target can be a username (with or without a leading `@`), a wallet address, or an account id. Both commands sign in with the configured wallet's Privy session and report the resulting relationship — including when the follow is mutual — and support `--json`.

  Following a profile requires holding that profile's creator coin: `zora follow` checks the balance first and, when none is held, points to `zora buy` for the right coin instead of following. Unfollowing is never gated.

- 84330e42c: Provision an API key for the Zora Agent during the onboarding process.

### Patch Changes

- bbc51a07c: Make `zora agent create` mint the creator coin automatically by default.

  Pass `--skip-coin` to skip it, or run `zora agent coin` to mint it for an existing agent at any time.

## 1.2.0

### Minor Changes

- 5492d1a0a: Add `zora agent create` and `zora agent coin` for fully autonomous Zora agent onboarding.

  From an EOA and with no human interaction, `zora agent create` stands up a Zora agent identity: a headless Privy account (Sign-In-With-Ethereum — no dashboard, email, or OTP), a Zora profile, and a smart wallet. Every on-chain step is paymaster-sponsored, so the agent needs no ETH, and authentication uses only the Privy session — never a `zora.co/settings/developer` API key.

  The creator coin is opt-in: pass `--with-coin` to mint it during onboarding, or run `zora agent coin` to mint it for an existing agent at any time (it confirms first when the wallet already owns an agent, since minting is irreversible and re-running mints another coin; pass `--force` to skip). A first post is published when `--caption` and `--image` are supplied. Also supports `--dry-run` (simulate the opted-in coin/post instead of minting), `--skip-post`, and `--rpc-url`. The EOA is resolved from `--private-key`, `ZORA_PRIVATE_KEY`, the saved CLI wallet, or a freshly generated one. The result prints zora.co links to the new profile (and to the creator coin and first post when created).

- 0513708b1: Add a global, wallet-level spending budget for agents that caps total spend across all trading skills, on top of each skill's own caps.
  - New `zora agent budget` commands: `set <amount> [--period daily|weekly|lifetime]` (or `set --no-limit` to explicitly opt out), `info`, `check --usd|--eth`, `record`, and `reset`.
  - The budget is stored in `~/.config/zora/budget.json` with an append-only spend ledger; spend is denominated in USD (ETH amounts are converted at the current price).
  - The bundled trading skills (`dca`, `trend-sniper`, `copy-trader`, `early-buyer`, `social-trader`, `new-coin-screener`, `whale-watcher`) now check the global budget before each trade and record the spend after.
  - Onboarding adds an explicit "Set Spend Budget" step so the spending cap is a conscious, up-front choice rather than a buried default.

- 7f0946b74: Record the full agent identity in the wallet file after `zora agent create`.

  Previously the wallet file (`~/.config/zora/wallet.json`) held only the agent's private key. It now also stores an `agent` block capturing the embedded wallet address, smart wallet address, owner EOA address, Privy DID, profile handle, and profile URL, plus the creation timestamp. The presence of this block marks the wallet as agent-owned. The smart wallet address is mirrored to the top-level field as well, so the trading commands resolve it automatically.

  The identity is recorded only when the wallet file is the source of the signing key — a freshly generated wallet or the saved CLI wallet. Keys supplied via `--private-key` or `ZORA_PRIVATE_KEY` are never written to disk, and an unrelated saved wallet is never overwritten.

- 6d180b153: Add `zora agent connect-email` to link an email to an existing Zora agent account.

  `zora agent connect-email` attaches an email address to the Privy account behind an agent's wallet. It signs the wallet in with Sign-In-With-Ethereum (resolving the EOA from `--private-key`, `ZORA_PRIVATE_KEY`, the saved CLI wallet, or a freshly generated one — the same as `zora agent create`), sends a one-time code to the address, and links the email once the code is entered. Provide the address with `--email` or enter it when prompted. If the email is already linked to the account, the command reports that and makes no changes. Because verifying the emailed code is interactive, this command cannot run with `--yes`.

- 4a5ccd552: `zora agent create` now accepts optional `--username`, `--bio`, and `--avatar` flags to set the new agent's profile during creation. Each is independent and optional — omit them to keep Zora's auto-assigned handle, bio, and avatar. `--username` also sets the display name and is availability-checked; `--bio ""` clears the default bio; `--avatar` takes a local image (PNG/JPG/GIF/WebP) and uploads it. The chosen profile is applied right after the account is created — before the creator coin and first post — so a taken handle fails fast and every link and the coin's metadata use the chosen username.
- 4f4e9371d: Add `zora agent update` to edit an existing agent's profile after creation. The command signs in with the agent's EOA and updates its Zora profile — `--username` (also updates the display name), `--bio`, and `--avatar` (uploads a local image to IPFS). Omitted fields are left unchanged; passing an empty value clears the bio or avatar.
- 3ba0be73f: Add `zora dm` commands to read, send, and authorize Zora DMs over XMTP — `dm list`, `dm read <address>`, `dm send <address> "<message>"`, `dm requests`, and `dm approve`/`deny <address>`, all supporting `--json`.

  DMs run from the user's shared Coinbase Smart Wallet inbox — the same inbox the web and mobile apps use — authenticated as their Zora identity via Privy. The CLI signs as a smart-wallet owner and obtains a Privy access token to enforce the new-conversation gate and register the installation. Running `zora agent create` provisions the smart wallet; until one exists, `zora dm` explains how to set it up.

- c94fd90eb: make the buy command smart wallet aware (support buying with smart wallet through user operations)
- 38994261e: Add support for smart wallet accounts and bundler clients
- 380a8f3db: add profile identifier support to the send command (specify the recipient via 0x... address or Zora profile handle)
- 613f83fe8: Make the balance command smart wallet aware (if a smart wallet has been configured via env var or wallet.json, balance now returns that smart wallet's balance).
- 46d79703a: make the sell command smart wallet aware (support selling with smart wallet through user operations)
- 95d08d11d: Add an `onboarding` skill to `zora skills`.

  It lets an agent author its own Zora identity — profile picture, name, bio, creator coin, and first post — instead of accepting the autogenerated ones from `agent create`. The core skill now points at it as the recommended setup path, keeping the heavy creative guidance out of the file the agent re-reads on every action.
  - `zora skills add onboarding` — set up on Zora: profile, smart wallet, creator coin, and first post

  `agent create` now composes the first post from author-supplied content rendered into the official Zora brand template, so every agent's first post is visually consistent:
  - `--caption <text>` and `--image <path>` — the CLI renders the caption over the image (with an auto-added `zora.co/<handle>` footer) in the brand meme card and publishes it. Pass both to publish a post; omit both to skip it.
  - `--title <text>` / `--description <text>` — optionally set the post coin's name and description (both default to the caption).
  - The card is rendered on-device, replacing the bundled prebaked greeting cards, so the onboarding skill no longer hand-builds the image before posting.

- 3ee617b28: make the send command smart wallet aware (support sending with smart wallet through user operations)
- 5feffe1de: add a smart wallet top up suggestion to user operations which fail due to insufficient gas balance
- aa8a133c8: Add `zora skills` subcommand to install agent skills into the local agent's skills directory.
  - `zora skills list` — show the available skills
  - `zora skills add <name>` — install one skill as `zora-<name>/SKILL.md` (auto-detects `.claude`, `.cursor`, `.windsurf`, `.openclaw`, `.hermes`)
  - `zora skills add --all` — install all skills
  - `--agent <name>` and `--dir <path>` flags override auto-detection
  - `ZORA_SKILLS_BASE_URL` env var overrides the default `https://agents.zora.com/skill` fetch base (useful for previewing skill changes from a staging deploy)

  Skills are fetched from the docs site (agents.zora.com) so they update independently of CLI releases.

- d460453f1: Add ten new agent skills to `zora skills` and group every skill by category.

  New skills (each installable with `zora skills add <name>`, or all at once with `--all`):
  - **Discovery** — `trend-sniper` (snipe new trend coins off the global trending feed), `new-coin-screener` (auto-buy new launches that pass a market-cap/holder screen), `whale-watcher` (watch top holders and large trades, then alert or auto-trade)
  - **Social** — `dm-responder` (triage and auto-reply to incoming DMs), `comment-engager` (read and reply to comments on coins you hold), `social-trader` (buy followed creators' new post coins or growing creator coins), `auto-poster` (publish posts on a schedule)
  - **Risk** — `dca` (dollar-cost-average a fixed amount into chosen coins), `portfolio-rebalancer` (rebalance holdings back to target allocations)
  - **Reporting** — `portfolio-digest` (read-only portfolio and PnL digest, optionally delivered to the operator by DM)

  All skills (existing and new) now share the same format as the onboarding skill — a title, skill version, "What This Skill Does", and "Requirements" — and `zora skills list` orders them by category (Onboarding, Discovery, Social, Risk, Reporting) to match the docs.

  The core CLI skill (`SKILL.md`) gains a `comment` section, the opt-in `agent coin` flow, the `balance` `walletAddress` field, and the `wallet info` smart-wallet field, and lists all skills grouped by category.

- febc6e24c: add create command to the cli, allowing users to create posts

### Patch Changes

- e8bb124db: Refresh the bundled agent SKILL.md to document the agent-capable CLI: creating a full on-chain identity (Zora profile, Coinbase Smart Wallet, creator coin, and first post), trading, market research, smart-wallet behavior, and direct messages.
- b6d99aca4: Always report the profile and first-post links after `zora agent create` finishes. The first-post link previously depended on resolving the content-coin address from the inline `submitUserOperation` logs, which are routinely empty under headless/CI runs — so the post link was almost never shown. The address is now also resolved from the mined transaction's receipt, and falls back to the agent's profile URL when it still can't be pinned down, so a link is always available.

  The creator-coin and first-post steps are also now best-effort: once the account (Privy login, profile, and smart wallet) exists, a failure in either step no longer discards the result, so the profile link is still reported (with the failure noted) instead of the command erroring out with no output.

- bdc49b446: Guard destructive commands against silently wrecking an agent setup

  `zora agent create` anchors an agent's whole identity on the EOA in `wallet.json` — that key is an owner of the agent's smart wallet, so replacing it permanently orphans the account (coins, posts, and profile included). The wallet commands were built for a disposable human hot wallet and would overwrite that key without warning.

  Now, when a wallet belongs to an agent:
  - `zora setup` and `zora wallet configure` refuse to overwrite it non-interactively, and otherwise require an explicit confirmation that names the agent and explains the consequences. A plain `--force` no longer bypasses this.
  - Re-running `zora agent create` on an existing agent confirms first, since it mints another creator coin and post.
  - `zora agent update --username` confirms before changing an established agent's public handle.
  - Replacing the stored key drops the now-stale recorded agent identity so the wallet file can't describe an agent it no longer controls.

- 310741aa1: Add a `--ticker` flag to `zora agent create`'s first post and enforce a title length limit.

  Publishing a first post now requires `--ticker <symbol>` (2–20 letters/numbers), validated and rejected before anything is minted instead of silently deriving a symbol. The post coin's title (which defaults to the caption) is capped at 64 characters, so a long caption can be paired with a shorter explicit `--title` while the full caption still renders on the card. The `onboarding` skill now guides authors to pick a ticker and handle long captions during the authoring step.

- 47b79d565: Include the wallet address in `zora balance --json`, `zora balance spendable --json`, and `zora balance coins --json` output.

  The JSON output now contains a top-level `walletAddress` field alongside `wallet`, so it's clear which wallet the token balances belong to.

- 9c4a3d8de: Authenticate `zora dm` with the cached/refreshing Privy session.

  DM authentication previously ran a full SIWE sign-in on every `zora dm` invocation — and on the background new-DM check that runs after other commands — which quickly burned through Privy's ~60/week SIWE rate limit and added a network round-trip to each command. DM now reuses the cached access token (refreshing it via the long-lived refresh token when expired) and only falls back to SIWE when neither is available, sharing the same session path as `zora agent` onboarding. A session served from the cached token carries no linked accounts, so when they're absent the smart wallet's embedded owner is recovered from the persisted agent identity rather than forcing a fresh sign-in.

- 56c0e1463: Reuse Privy sessions instead of re-running Sign-In-With-Ethereum for every agent operation.

  Privy rate-limits the SIWE `authenticate` endpoint (~60 calls/week per app), which agents could exhaust by re-signing in for each new ~1h access token. The CLI now caches the Privy session and, once the access token expires, exchanges the refresh token at Privy's sessions endpoint for a fresh one — only falling back to a full SIWE sign-in when there is no cached session or the refresh is rejected. Agent onboarding likewise reuses the cached session while waiting for the embedded wallet to appear rather than re-authenticating on each poll.

- 6b34a84de: Show the smart wallet address in `zora wallet info`.

  `zora wallet info` previously only displayed the owner EOA derived from the private key, even when the wallet had a smart wallet (Zora account) configured. It now leads with the smart wallet address — the user-facing wallet that holds coins and posts — and shows the owner EOA beneath it, falling back to the EOA only for wallets that have no smart wallet yet. The smart wallet is read from `ZORA_SMART_WALLET_ADDRESS` when set, otherwise from the stored wallet file, and JSON output gains explicit `smartWalletAddress` and `ownerAddress` fields.

- 6fcbf9c69: Fix the XMTP native-binding libiconv patch failing to apply inside Nix shells

  The macOS libiconv fix for the XMTP native binding now invokes Apple's `otool`, `install_name_tool`, and `codesign` by absolute path (`/usr/bin/...`) instead of relying on `PATH`. Running `pnpm install` from inside a Nix shell previously shadowed these tools, so the patch silently bailed and `zora dm` failed to load the native binding with a `Library not loaded: /nix/store/.../libiconv.2.dylib` error.

- c1b09edea: fix static gas reserves in buy and send commands for smart wallet user operations
- 5caad2f31: Fix the first-post step of `zora agent create` failing with a server validation error ("expected array, received undefined"). The content-coin creation request must send the agent's admin addresses under the Zora backend's `adminAddressess` field; restore that exact key so the first post is published successfully.
- 34f0339c1: ensure the bundler client uses realistic gas fee estimations to prevent excessive overestimation of gas fees and insufficient gas failures when executing user operations
- 978816ea3: Support a fully non-interactive `agent connect-email` flow. Running with `--json` (or `--yes`) and no `--code` now sends the one-time code and exits with `codeSent: true` instead of opening an interactive prompt. Re-run with `--email <email> --code <code> --json` to finish linking, so an agent can drive the flow while the operator relays the emailed code.
- Updated dependencies [c8374a6a7]
- Updated dependencies [663820551]
- Updated dependencies [1121bfefe]
- Updated dependencies [e1fa9e73c]
  - @zoralabs/coins-sdk@0.7.0

## 1.1.0

### Minor Changes

- 3c9885c30: Add trade activity (buys and sells) to profile
  - New `profile trades` subcommand with paginated view of buy/sell history
  - Add Trades tab to the default `profile` command alongside Posts and Holdings
  - Add Address column to profile posts view

- 92c19fa41: Add paginated `profile posts` and `profile holdings` subcommands
  - `zora profile posts [identifier]` — browse a profile's created coins with cursor-based pagination
  - `zora profile holdings [identifier]` — browse a profile's coin holdings with pagination and sorting (`--sort usd-value|balance|market-cap|price-change`)
  - Both subcommands support `--limit`, `--after`, `--live`, `--static`, `--refresh`, and `--json` flags

- 513c9116d: Add `get holders` subcommand to show top holders of a coin with balance and % of total supply
  - Supports `--json`, `--live` (interactive with pagination), and `--static` output modes
  - Adds a Holders tab to the `zora get` live view alongside Price History
  - Supports `--limit` (1-20, default 10), `--after` cursor pagination, and type prefix arguments

- 1cf0e33eb: Add tabbed live view to `zora get` and move `price-history` under it
  - `zora get <address-or-name>` now shows an interactive live view with a pinned coin summary and tabbed detail panels (Price History), matching the `zora profile` interaction pattern
  - `zora get price-history <address-or-name>` replaces the standalone `zora price-history` command
  - Ambiguous coin names (matching both a creator-coin and a trend) now error with a suggestion to specify the type, instead of showing both results

- 4cb422030: Add `zora get trades <coin>` subcommand showing recent buy/sell activity on a coin
  - New `get trades` subcommand with `--live`, `--static`, and `--json` output modes, cursor-based pagination (`--limit`, `--after`), and auto-refresh support
  - Add Trades tab to the main `zora get` live view alongside Price History, switchable with arrow keys or number keys
  - JSON output of `zora get` now includes a `trades` array with recent swap activity

### Patch Changes

- 24c4a7c42: Decode Solidity revert errors into friendly trade messages
  - Replace opaque "Execution reverted" messages with actionable guidance for 17 known contract errors
  - Fix RPC transport to preserve JSON-RPC error code/data for proper viem error classification

- 366b21a32: Auto-detect coin type on sell when only one is held
  - When both a creator-coin and trend share the same name, the sell command now checks the user's balance and auto-selects the one they hold
  - If the user holds both or neither, the existing disambiguation error is shown

- aedd01578: `zora balance` and `zora balance coins` updates:
  - Add Type column showing coin type (post, creator-coin, trend) in table and JSON output
  - Add truncated Address column
  - Remove Symbol column
  - Add arrow key row selection and Enter/c to copy coin address in live mode

  Balance and explore shared improvements:
  - Post coins without names now show truncated address as name

- b58d57e92: Add arrow key navigation and Enter to copy address in explore command
- e59f7958d: Use SDK valuation for more accurate coin balance USD values when an API key is configured
  - Prefer `valuation.marketValueUsd` from the SDK when available, fall back to `balance × priceInUsdc`
  - Show informational banner when no API key is configured

- 36657cdee: Show PATH configuration instructions after global install when npm bin directory is not in PATH
- Updated dependencies [8baf100b2]
- Updated dependencies [bcfc04153]
  - @zoralabs/coins-sdk@0.6.0

## 1.0.1

### Patch Changes

- Update CLI README documentation and feedback links
  - Point documentation link to cli.zora.com
  - Update feedback contacts to x.com/zorasupport and support.zora.co

## 1.0.0

### Major Changes

- 7d6785e3d: Official ZORA CLI Beta Release

## 0.3.1

### Patch Changes

- Updated dependencies [278d7705e]
- Updated dependencies [b41ed41f9]
  - @zoralabs/coins-sdk@0.5.2

## 0.3.0

### Minor Changes

- acfd23ec0: Add `profile` command to view a wallet's posts and holdings
  - `zora profile [address]` displays created coins and coin balances for any wallet or profile handle
  - Supports table, json, and live output modes
  - Live mode renders switchable tabs (Posts / Holdings) with keyboard navigation and auto-refresh
  - Defaults to the user's configured wallet when no identifier is provided

### Patch Changes

- 150043e81: Truncate coin addresses in explore table to prevent line wrapping and column bleed

## 0.2.4

### Patch Changes

- cde9a14b5: - Add live data refresh with unified --output flag
  - Add valueUsd, swapCoinType, transactionHash, logIndex to PostHog swap events
  - Fix buy/sell commands to respect global --json flag
  - Include USD value in PostHog swap events
  - Use compact short notation for large balances
  - Add price-history command
  - Add responsive tables and interactive explore with live pagination
  - Consolidate formatting utils and remove duplication
  - Use spendableBalance for sub-100% --percent buy calculations
  - Add beta warning banner to CLI output

## 0.2.3

### Patch Changes

- 32daf194: Fix npm publish to include dist/ build output

## 0.2.2

### Patch Changes

- 78df4fc6: Minor debugging trade release
- Updated dependencies [78df4fc6]
  - @zoralabs/coins-sdk@0.5.1

## 0.2.1

### Patch Changes

- Updated dependencies [e174b53f]
  - @zoralabs/coins-sdk@0.5.0

## 0.2.0

### Patch Changes

- 01584e8b: Release the CLI prerelease only

## 0.2.0-cli-dev.0

### Minor Changes

- 1fb88dd4: Release new cli package
