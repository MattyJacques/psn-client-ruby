# psn-client-ruby — Design

**Date:** 2026-07-04
**Status:** Approved

## Purpose

A Ruby gem providing a client for the (unofficial) PlayStation Network API. It retrieves, for a PSN account:

- **Games played** — the account's played-titles list with play time and dates.
- **Trophies earned** — trophy titles, individual trophies with earned status, and the account's trophy summary.
- **Purchases** — both the monetary **transaction history** and the owned **entitlements** list (games, DLC, free claims).

Games and trophies work for any account whose privacy settings allow it; purchases are available only for the authenticated account.

## Decisions (from brainstorming)

| Topic | Decision |
|---|---|
| Gem name | `psn-client-ruby` (available on RubyGems; required as `psn_client`, module `PSN`) |
| Auth input | NPSSO token **or** saved refresh token; gem handles OAuth exchange and auto-refresh |
| Scope of data | Games/trophies for any (public) account; transactions/entitlements own-account only |
| Purchases | Both transaction history and entitlements, as separate calls |
| Return values | Hybrid: typed immutable `Data` objects with `#raw` hash escape hatch |
| HTTP | Faraday (+ faraday-retry) |
| Pagination | Lazy enumerators (`Enumerator::Lazy`) |
| Architecture | Resource-namespaced client (Octokit-style): `client.games`, `client.trophies`, `client.store` |
| Ruby version | >= 3.2 (needs `Data`) |

## Public API

```ruby
require "psn_client"

client = PSN::Client.new(npsso: "abc123...")
client = PSN::Client.new(refresh_token: saved_token)

client.games.played                    # own account
client.games.played("some_online_id")  # another user

client.trophies.titles("some_online_id")
client.trophies.earned("some_online_id", np_communication_id: "NPWR12345_00")
client.trophies.summary("some_online_id")

client.store.transactions   # authenticated account only
client.store.entitlements   # authenticated account only

client.access_token   # readable
client.refresh_token  # readable — caller persists this for next session
```

- `games` / `trophies` / `store` are memoized resource objects sharing one authenticated connection.
- All list calls return `Enumerator::Lazy`; `.first(10)` fetches one page, `.to_a` walks all pages.
- Omitting the online ID (or passing `nil`) means the authenticated account (`"me"`).
- Online IDs are resolved to Sony's numeric `accountId` internally and cached per client instance.

## Architecture

```
PSN::Client ──▶ PSN::Resources::Games ────┐
            ──▶ PSN::Resources::Trophies ─┼──▶ PSN::Connection ──▶ PSN::Auth
            ──▶ PSN::Resources::Store ────┤        (Faraday)        (tokens)
            ──▶ PSN::Resources::Users ────┘  (internal: accountId resolution)
```

### Auth (`PSN::Auth`)

- **NPSSO path:** NPSSO → authorization code → access token + refresh token, via `ca.account.sony.com/api/authz/v3/oauth` endpoints. Performed lazily on first API call, not in the constructor.
- **Refresh-token path:** goes straight to the refresh grant.
- **Auto-refresh:** access tokens last ~1 hour; Auth tracks expiry and refreshes proactively. If a request still receives 401, refresh once and retry the request a single time before raising.
- **Exposure:** `access_token` / `refresh_token` readable; no persistence inside the gem (caller's job). Refresh tokens last ~2 months.
- **Errors:** invalid/expired NPSSO raises `PSN::AuthenticationError` with a message noting NPSSO expiry.
- **Thread safety:** refresh is mutex-guarded to prevent double refresh from concurrent calls.

### HTTP (`PSN::Connection`)

- One Faraday instance per base host:
  - `m.np.playstation.com` — games, trophies, universal search
  - `web.np.playstation.com` — transactions, entitlements
- Middleware: JSON request/response; `faraday-retry` for 429/5xx with backoff honoring `Retry-After`.
- Authorization header injected per-request from `Auth` (so mid-session refresh is always picked up).
- Error mapping to a hierarchy under `PSN::Error`:
  - `PSN::AuthenticationError` — 401 after one refresh attempt / bad NPSSO
  - `PSN::PrivacyError` — 403, target account's privacy settings block access
  - `PSN::NotFoundError` — 404, unknown online ID / title
  - `PSN::RateLimitError` — 429 surviving retries; carries `retry_after`
  - `PSN::APIError` — everything else; carries status + Sony error body
- All exceptions expose `#response` (status, body).

### Resources

**`PSN::Resources::Games`**
- `played(online_id = nil)` → `GET /api/gamelist/v2/users/{accountId}/titles` (m.np host). Play time, play count, first/last played. `limit`/`offset` paged.

**`PSN::Resources::Trophies`**
- `titles(online_id = nil)` → `/api/trophy/v1/users/{accountId}/trophyTitles`.
- `earned(online_id = nil, np_communication_id:, platform: nil)` — merges the title's trophy definitions (`/trophyGroups/all/trophies`) with the user's earned status so each `Trophy` carries name, description, grade, rarity, and `earned_at`. PS3/Vita titles need `npServiceName=trophy`, derived internally from platform.
- `summary(online_id = nil)` → `/api/trophy/v1/users/{accountId}/trophySummary`.

**`PSN::Resources::Store`** (authenticated account only)
- `transactions` → account-management transaction-history API on `web.np.playstation.com`. Order date, items, amount, currency, payment method. Cursor-paged.
- `entitlements` → games/library entitlements API on the same host.
- ⚠️ These endpoints are undocumented and have churned before. Exact paths/params will be verified during implementation against real traffic captured by the `psn-account-manager` extension (in `C:\Development\psn-account-manager`). Each is an isolated adapter so a Sony change touches one file.

**`PSN::Resources::Users`** (internal)
- `universalSearch` maps online ID → numeric `accountId`; cached in a per-client hash. `nil` → literal `"me"`.

### Models (`PSN::Models`)

Immutable `Data` classes, one file each. Built via `.from_api(hash)` mapping Sony's camelCase keys; the untouched response hash is kept as `#raw`. Unmapped/new fields never crash mapping — they are reachable only via `#raw`.

- `GameTitle` — name, title_id, platform, play_count, first_played_at, last_played_at, play_duration (Integer seconds parsed from ISO-8601 duration)
- `TrophyTitle` — name, np_communication_id, platform, progress %, earned counts by grade
- `Trophy` — id, name, detail, grade (`:bronze`/`:silver`/`:gold`/`:platinum`), rarity %, earned?, earned_at (`Time` or nil)
- `TrophySummary` — level, progress, earned counts
- `Transaction` — transaction_id, date, description/items, amount (integer minor units + currency string; no float money), payment method, type (purchase/refund/wallet funding)
- `Entitlement` — id, name, type (game/DLC/etc.), platform, acquired_at

### Pagination (`PSN::Paginator`)

```ruby
Paginator.enumerate(page_size: 200) { |limit, offset| conn.get(path, ...) }
# → Enumerator::Lazy of mapped models
```

Handles both Sony paging styles — `totalItemCount` + offset (games/trophies) and cursor-based (transactions) — behind one lazy interface. Nothing is fetched until the enumerator is consumed.

## Gem layout

```
psn-client-ruby/
├── psn-client-ruby.gemspec     # Ruby >= 3.2; deps: faraday, faraday-retry
├── lib/psn_client.rb           # requires + PSN module, VERSION
└── lib/psn_client/
    ├── client.rb               # facade: .games/.trophies/.store
    ├── auth.rb
    ├── connection.rb
    ├── paginator.rb
    ├── errors.rb
    ├── resources/{games,trophies,store,users}.rb
    └── models/{game_title,trophy_title,trophy,trophy_summary,transaction,entitlement}.rb
```

## Testing

- RSpec + WebMock; TDD throughout.
- Unit tests per layer:
  - Auth: stubbed OAuth responses, including refresh-and-retry-on-401.
  - Connection: error mapping per status code.
  - Paginator: both paging styles; laziness verified by asserting only one HTTP stub fires for `.first(n)`.
  - Models: `.from_api` against realistic (anonymized) fixture JSON captured from real responses.
- No live-API tests in the suite. A `bin/smoke` script (token gitignored) allows manual verification against real PSN.
- RuboCop for style; GitHub Actions CI.

## Out of scope (YAGNI)

- Writing/persisting tokens to disk (caller's responsibility).
- Any write operations (sending messages, friend requests, etc.).
- Store catalog browsing/pricing lookups.
- CLI executable.
