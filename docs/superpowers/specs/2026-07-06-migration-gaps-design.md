# Migration gaps: GraphQL game library, purchases, profiles, trophy extras

**Date:** 2026-07-06
**Goal:** Add the capabilities backlog_manager_old's vendored PSN client has that
this gem lacks, so backlog_manager_old can migrate to the gem. Gem-first design:
we expose the best gem API for each capability rather than mirroring the vendored
client 1:1.

## Context

backlog_manager_old (Rails app) carries its own PSN client in `lib/psn/client/`.
Comparing it against the gem, the gem already covers played games (REST
`gamelist/v2`), trophies (summary/titles/earned), transactions and entitlements,
and online-ID resolution. The gaps are:

1. GraphQL persisted queries: `getUserGameList` (game library) and
   `getPurchasedGameList` (purchased games), which return data the REST
   endpoints don't (subscription titles, `conceptId`, `isDownloadable`,
   `membership`, artwork).
2. User profiles (username → rich profile via the legacy `profile2` endpoint).
3. Granular trophy endpoints: per-title trophy summary (`npTitleIds`) and
   trophy groups (base game vs DLC).

`store.transactions` and `store.entitlements` stay as-is: transactions are the
only source of monetary data, entitlements the only complete ownership ledger.
The new `games.purchased` is a games-only storefront view that complements them
(README will state the distinction).

## 1. Connection: GraphQL transport

`PSN::Connection` gains:

```ruby
graphql(operation_name, variables, hash)
```

- GET to `:mobile` host, path `/api/graphql/v1/op`, query params:
  `operationName`, `variables` (JSON-encoded), `extensions` (persisted-query
  envelope `{"persistedQuery":{"version":1,"sha256Hash":<hash>}}`, JSON-encoded).
- Sends header `Apollo-Require-Preflight: true`.
- Reuses existing Bearer auth, 401 refresh-and-retry, transient retries, and
  HTTP error mapping.
- GraphQL can return HTTP 200 with an `errors` array in the body; `graphql`
  raises `PSN::APIError` in that case instead of returning a partial payload.
- Persisted-query sha256 hashes are NOT Connection's concern; they live as
  constants in the resource that uses them (same isolation philosophy as
  `store.rb`).

## 2. Games: `library` and `purchased`

Both on `PSN::Resources::Games`, authenticated account only (the API ignores
other users). Hashes and response-digging stay private to `games.rb`.

- `games.library` — wraps `getUserGameList`. No offset support upstream, so a
  single fetch with a `limit` (default 200, overridable), exposed as the usual
  lazy enumerator. Returns `LibraryTitle` models: `name`, `platform`,
  `title_id`, `product_id`, `concept_id`, `entitlement_id`, `image_url`,
  `last_played_at`, `active?`, `subscription_service` (nil for owned titles,
  e.g. `"PS_PLUS"` for subscription entries).
- `games.purchased` — wraps `getPurchasedGameList`, paged via `start`/`size`.
  The persisted query returns no total count, so it uses `Paginator.offset`'s
  paginate-until-short-page behaviour. Returns `PurchasedGame` models: `name`,
  `platform`, `title_id`, `product_id`, `concept_id`, `entitlement_id`,
  `image_url`, `active?`, `downloadable?`, `pre_order?`, `membership`.

Models follow the existing pattern: `from_api`, snake_case readers, `#raw`.

## 3. Profiles resource

- New `:community` host in `Connection::HOSTS`:
  `https://us-prof.np.community.playstation.net`.
- New `PSN::Resources::Profiles`, exposed as `client.profiles`.
- `profiles.find(online_id = nil)` — single public method.
  - With a username: legacy `profile2` endpoint (the richer profile API).
  - With nil: resolve own online ID via `:mobile`
    `/api/userProfile/v1/internal/users/me/profiles` first (memoized per
    client), then call `profile2` — callers always get the same rich shape.
- Returns a `Profile` model: `online_id`, `account_id`, `avatar_url` (largest
  size), `plus?`, `about_me`, `languages`, `verified?`, `trophy_summary`
  (reusing `TrophySummary`), and presence as `online?` / `platform` /
  `last_online_at`. Everything else via `#raw`.
- No public account-ID→profile method; `find` by username covers the need.
- Unlike backlog's client, the gem does NOT set `verify: false` — SSL
  verification stays on for all hosts.

## 4. Trophies: `title_summary` and `groups`

Following the resource's conventions (`online_id` first positional arg
defaulting to the authenticated account; keywords for the rest):

- `trophies.title_summary(online_id = nil, title_ids:)` — wraps the
  `npTitleIds` endpoint (`/api/trophy/v1/users/%s/titles/trophyTitles`). API
  caps at 5 IDs per request; the gem accepts any number and chunks into
  batches of 5, returning a lazy enumerator of `TitleTrophySummary` models:
  `np_title_id` + `trophy_titles` (array reusing `TrophyTitle`, since one
  disc ID can map to multiple trophy sets).
- `trophies.groups(online_id = nil, np_communication_id:, platform: nil)` —
  wraps the `trophyGroups` definition + earned endpoints, merged the same way
  `earned` merges trophies. Returns `TrophyGroup` models: `group_id`, `name`,
  `icon_url`, `defined_counts`, `earned_counts`, `progress` (count naming
  matches the existing `TrophyTitle`/`TrophySummary` models). Base game is
  group `"default"`, DLC packs `"001"`, `"002"`, … Same `platform:` handling
  as `earned` (`npServiceName=trophy` for pre-PS5 titles).
- No single-trophy method: `earned` already returns every trophy for a title
  with earned status merged; a single trophy is a filter over that.

## Error handling

No new error classes. Existing mapping covers the new endpoints (403 →
`PrivacyError`, 429 → `RateLimitError`, etc.); GraphQL body errors raise
`APIError` (see section 1).

## Testing and verification

- WebMock-stubbed specs in the existing style: new specs for `Profiles`, new
  models, GraphQL in `connection_spec`, new methods in `games_spec` and
  `trophies_spec`. Fixture shapes derived from the response handling in
  backlog_manager_old's client.
- `bin/smoke` gains live calls for `games.library`, `games.purchased`,
  `profiles.find`, `trophies.title_summary`, `trophies.groups` — the GraphQL
  hashes and legacy profile host are exactly the undocumented parts, so the
  smoke script is the real safety net.
- `bundle exec rake` (rspec + rubocop) must pass.
- README: usage examples for the new methods and the
  `games.purchased`-vs-`store.entitlements` distinction.

## Out of scope

- Changes to backlog_manager_old itself (the migration is a later project).
- Auth/token caching (Rails-side concern in backlog; gem auth already exists).
- Exposing a generic GraphQL query API.
