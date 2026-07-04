# psn-client-ruby

Unofficial Ruby client for the PlayStation Network API: games played,
trophies earned, transaction history and entitlements.

## Installation

```ruby
gem "psn-client-ruby"
```

Requires Ruby >= 3.2.

## Authentication

PSN has no public API; this gem uses the same OAuth flow as the official
mobile app. You need an **NPSSO token**: sign in at playstation.com, then
visit <https://ca.account.sony.com/api/v1/ssocookie> (or use a helper
browser extension that fetches it for you). NPSSO tokens last about two
months.

```ruby
require "psn_client"

client = PSN::Client.new(npsso: "your-npsso")

# Persist client.refresh_token (lasts ~2 months, rotates on refresh) and
# skip the NPSSO next time:
client = PSN::Client.new(refresh_token: saved_token)
```

## Usage

All list calls return lazy enumerators — `.first(n)` only fetches the pages
it needs, `.to_a` fetches everything. Every object exposes `#raw` with the
untouched API response.

```ruby
# Games played (any account whose privacy settings allow it)
client.games.played.first(10).each { |g| puts "#{g.name} [#{g.platform}]" }
client.games.played("a_friend").to_a

# Trophies
client.trophies.summary                                  # level, counts
client.trophies.titles.to_a                              # per-game progress
client.trophies.earned(np_communication_id: "NPWR20188_00")
client.trophies.earned("a_friend", np_communication_id: "NPWR00000_00", platform: "PS4")

# Purchases (authenticated account only)
client.store.transactions.first(20)  # orders, refunds, wallet funding
client.store.entitlements.to_a       # everything owned incl. free claims
```

Amounts are integer minor units (`6999` + `"GBP"` = £69.99).

### Errors

All errors subclass `PSN::Error` (`#response` has status and body):
`AuthenticationError`, `PrivacyError` (target account is private),
`NotFoundError`, `RateLimitError` (`#retry_after`), `APIError`. Rate limits
are not retried automatically: a 429 raises `RateLimitError` immediately
with `#retry_after` so the caller decides when to retry.

## Development

```
bundle install
bundle exec rake        # rspec + rubocop
ruby bin/smoke          # live-API check; needs PSN_NPSSO or PSN_REFRESH_TOKEN
```

Note: the transaction/entitlement endpoints are undocumented and may change;
they live in `lib/psn_client/resources/store.rb` if they need updating.

## License

MIT
