# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Commands

```
bundle install
bundle exec rake                 # default task: rspec + rubocop (what CI runs)
bundle exec rspec                # all tests
bundle exec rspec spec/psn_client/resources/games_spec.rb          # one file
bundle exec rspec spec/psn_client/resources/games_spec.rb:42       # one example by line
bundle exec rubocop              # lint (add -a to autocorrect)
ruby bin/smoke                   # live-API check; needs PSN_NPSSO or PSN_REFRESH_TOKEN env var
```

CI (GitHub Actions) runs rspec on Ruby 3.2, 3.3, 3.4 and head (head is non-blocking), plus rubocop and bundler-audit jobs on 3.4; Dependabot files weekly gem/action update PRs. SimpleCov gates the rspec run at line 99% / branch 85%. RuboCop enforces double-quoted strings, LF line endings, max line length 120, `NewCops: enable`.

`bin/smoke` hits the real PSN API and is NOT part of the test suite — use it to verify the undocumented endpoints still work after changing them.

## Architecture

Unofficial Ruby gem for the PlayStation Network API. Everything lives under the `PSN` module (not `PsnClient`), loaded via `lib/psn_client.rb`.

Layers, top to bottom:

- **`PSN::Client`** (`client.rb`) — entry point; builds `Auth` + `Connection` once and memoizes resource objects (`client.games`, `client.trophies`, `client.store`, `client.profiles`, `client.search`, `client.catalog`).
- **Resources** (`lib/psn_client/resources/`) — one class per API area. Each knows its endpoint paths/page sizes as constants, calls `Connection`, and maps responses to models. `Resources::Users` is internal-only: it resolves friendly online IDs to Sony numeric account IDs (cached), and is injected into `Games` and `Trophies` — a `nil` online_id means the authenticated account (`"me"`).
- **`PSN::Connection`** (`connection.rb`) — shared Faraday HTTP layer. Keeps one connection per named host (`HOSTS`: `:mobile`, `:web`, `:community`, `:dms`); injects the Bearer token per request; retries 5xx; on a 401 refreshes the token once and retries; maps HTTP status to the error hierarchy. Also does persisted-query GraphQL GETs, where Sony can return HTTP 200 with an `errors` array — that is mapped to `APIError` too.
- **`PSN::Auth`** (`auth.rb`) — exchanges an NPSSO token or a saved refresh token for OAuth tokens (mutex-guarded, refreshes the ~1h access token early). Nothing is persisted; callers read `#refresh_token` and store it themselves.

Cross-cutting pieces:

- **`PSN::Paginator`** (`paginator.rb`) — all list endpoints return `Enumerator::Lazy` via `Paginator.offset` (total-count paging) or `Paginator.cursor`; nothing is fetched until consumed, so `.first(n)` only pulls the pages it needs. New list methods should follow this pattern.
- **Models** (`lib/psn_client/models/`) — immutable `Data.define` value objects with a `from_api(hash)` class method and a `raw` member holding the untouched API response. `Mapping` holds shared Sony-value converters (ISO8601 times, `PT..S` durations, platform names, trophy grade counts).
- **Errors** (`errors.rb`) — everything subclasses `PSN::Error` (carries `#response` with status/body): `AuthenticationError`, `PrivacyError` (403 = private account), `NotFoundError`, `RateLimitError` (`#retry_after`; 429s are never auto-retried — the caller decides), `APIError`.

### Undocumented endpoints

The transaction/entitlement endpoints, the GraphQL persisted queries (operation names + sha256 hashes), and the legacy profile2 endpoint are undocumented Sony internals that can change without notice. Knowledge of each is deliberately confined to one file each: `resources/store.rb`, `resources/games.rb`, `resources/profiles.rb`, `resources/search.rb` (game/user search), `resources/catalog.rb` (web-host store catalog, served anonymously), and the Game Help queries in `resources/trophies.rb`. Quirks discovered by live testing (e.g. the library limit cap of 100, profile2 rejecting `"me"`) are recorded in comments there — keep them accurate, and verify changes with `bin/smoke`.

## Tests

Specs use WebMock (no real HTTP) with JSON fixtures in `spec/fixtures/`, loaded via the `fixture("name")` helper from `spec_helper.rb`. Monkey-patching is disabled (`RSpec.describe`, not bare `describe`); example order is random.
