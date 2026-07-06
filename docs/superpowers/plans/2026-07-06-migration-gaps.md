# Migration Gaps Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add GraphQL persisted-query support (game library, purchased games), a user-profiles resource, and granular trophy endpoints (per-title summary, trophy groups) so backlog_manager_old can migrate to this gem.

**Architecture:** GraphQL stays an internal transport detail: `Connection` gains one `graphql` method; persisted-query hashes live as constants in the resources that use them (same isolation as `store.rb`). New capabilities extend existing resources (`Games`, `Trophies`) plus one new `Profiles` resource. All list calls return lazy enumerators of `Data.define` models with `#raw`, matching the existing pattern.

**Tech Stack:** Ruby >= 3.2, Faraday (+ faraday-retry), RSpec + WebMock, RuboCop. No new dependencies.

**Spec:** `docs/superpowers/specs/2026-07-06-migration-gaps-design.md`

## Global Constraints

- Ruby >= 3.2 (`TargetRubyVersion: 3.2`), double-quoted strings, LF line endings, max line length 120.
- `Metrics/MethodLength: 25`, `Metrics/AbcSize: 25`; model `Data.define` blocks are exempt from `Metrics/BlockLength`.
- Models: `Data.define` with `from_api` class constructor, snake_case readers, `raw` field carrying the untouched API hash. Predicates (`active?` etc.) are explicit methods delegating to the boolean field.
- Resources take `@connection` (and `@users` where an `online_id` arg exists); `online_id` is the first positional arg defaulting to `nil` = authenticated account.
- Every task ends with `bundle exec rake` (rspec + rubocop) green, then a commit.
- Do NOT set `verify: false` / disable SSL anywhere.
- The persisted-query sha256 hashes are copied from backlog_manager_old and must be used verbatim (they identify the query server-side).

---

### Task 1: Connection#graphql

**Files:**
- Modify: `lib/psn_client/connection.rb`
- Test: `spec/psn_client/connection_spec.rb`

**Interfaces:**
- Consumes: existing `Connection#request`/`#perform` private plumbing.
- Produces: `Connection#graphql(operation_name, variables, sha256_hash) -> Hash` — GET to `:mobile` `/api/graphql/v1/op` with persisted-query params and `Apollo-Require-Preflight: true`; raises `PSN::APIError` when the 200 body contains a non-empty `"errors"` array. Tasks 2, 3 call this.

- [ ] **Step 1: Write the failing tests**

Append inside the top-level `RSpec.describe PSN::Connection do` block in `spec/psn_client/connection_spec.rb`:

```ruby
  describe "#graphql" do
    let(:gql_url) { "https://m.np.playstation.com/api/graphql/v1/op" }

    it "performs a persisted-query GET with the Apollo preflight header" do
      stub_request(:get, gql_url)
        .with(query: {
                "operationName" => "getThing",
                "variables" => '{"limit":5}',
                "extensions" => '{"persistedQuery":{"version":1,"sha256Hash":"abc123"}}'
              },
              headers: { "Authorization" => "Bearer tok-1", "Apollo-Require-Preflight" => "true" })
        .to_return(json_response({ "data" => { "ok" => true } }))

      expect(connection.graphql("getThing", { "limit" => 5 }, "abc123")).to eq("data" => { "ok" => true })
    end

    it "raises APIError when the 200 body carries GraphQL errors" do
      stub_request(:get, gql_url)
        .with(query: hash_including("operationName" => "getThing"))
        .to_return(json_response({ "errors" => [{ "message" => "PersistedQueryNotFound" }] }))

      expect { connection.graphql("getThing", {}, "abc123") }
        .to raise_error(PSN::APIError, /PersistedQueryNotFound/)
    end

    it "refreshes and retries once on 401" do
      stub_request(:get, gql_url)
        .with(query: hash_including("operationName" => "getThing"))
        .to_return({ status: 401 }, json_response({ "data" => { "ok" => true } }))

      expect(connection.graphql("getThing", {}, "abc123")).to eq("data" => { "ok" => true })
      expect(auth).to have_received(:refresh!).once
    end
  end
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `bundle exec rspec spec/psn_client/connection_spec.rb -e graphql`
Expected: 3 failures, `NoMethodError`/`undefined method 'graphql'`.

- [ ] **Step 3: Implement**

In `lib/psn_client/connection.rb`:

Add after the `require` lines at the top:

```ruby
require "json"
```

Add constants after `DEFAULT_RETRY_OPTIONS`:

```ruby
    GRAPHQL_PATH = "/api/graphql/v1/op"
    GRAPHQL_HEADERS = { "Apollo-Require-Preflight" => "true" }.freeze
```

Add a public method after `post`:

```ruby
    # Persisted-query GraphQL GET. Sony's GraphQL can fail with HTTP 200 and
    # an errors array in the body, so that case is mapped to APIError here.
    def graphql(operation_name, variables, sha256_hash)
      extensions = { "persistedQuery" => { "version" => 1, "sha256Hash" => sha256_hash } }
      params = { "operationName" => operation_name,
                 "variables" => JSON.generate(variables),
                 "extensions" => JSON.generate(extensions) }
      body = request(:mobile, :get, GRAPHQL_PATH, params, headers: GRAPHQL_HEADERS)
      handle_graphql_errors(body)
      body
    end
```

Replace the private `request` and `perform` methods so per-request headers thread through:

```ruby
    def request(host, verb, path, payload, headers: {}, retried: false)
      resp = perform(host, verb, path, payload, headers)
      if resp.status == 401 && !retried
        @auth.refresh!
        return request(host, verb, path, payload, headers: headers, retried: true)
      end
      handle_errors(resp)
      resp.body
    end

    def perform(host, verb, path, payload, headers)
      connection(host).public_send(verb, path) do |req|
        req.headers["Authorization"] = "Bearer #{@auth.access_token}"
        headers.each { |name, value| req.headers[name] = value }
        verb == :get ? req.params.update(payload) : req.body = payload
      end
    end
```

Add a private method after `handle_errors`:

```ruby
    def handle_graphql_errors(body)
      errors = body.is_a?(Hash) ? body["errors"] : nil
      return if errors.nil? || errors.empty?

      messages = errors.filter_map { |e| e["message"] }.join("; ")
      raise APIError.new("PSN GraphQL error: #{messages}", response: { status: 200, body: body })
    end
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `bundle exec rspec spec/psn_client/connection_spec.rb`
Expected: all examples PASS (old and new).

- [ ] **Step 5: Full check and commit**

Run: `bundle exec rake`
Expected: rspec green, rubocop no offenses.

```bash
git add lib/psn_client/connection.rb spec/psn_client/connection_spec.rb
git commit -m "feat: GraphQL persisted-query support in Connection"
```

---

### Task 2: games.library + LibraryTitle model

**Files:**
- Create: `lib/psn_client/models/library_title.rb`
- Create: `spec/fixtures/library_title.json`
- Create: `spec/psn_client/models/library_models_spec.rb`
- Modify: `lib/psn_client/models/mapping.rb` (add `subscription`)
- Modify: `lib/psn_client/resources/games.rb`
- Modify: `lib/psn_client.rb` (require line)
- Modify: `.rubocop.yml` (spec-file excludes)
- Test: `spec/psn_client/resources/games_spec.rb`

**Interfaces:**
- Consumes: `Connection#graphql(operation_name, variables, sha256_hash)` from Task 1; `Mapping.time`.
- Produces: `Games#library(limit: 200) -> Enumerator::Lazy` of `PSN::LibraryTitle` (fields: `name, title_id, platform, concept_id, entitlement_id, product_id, image_url, last_played_at, active?/active, subscription_service, raw`); `Mapping.subscription(value)` (`"NONE"` → nil). Task 7 (smoke/README) uses `library`.

- [ ] **Step 1: Create the fixture**

`spec/fixtures/library_title.json`:

```json
{
  "__typename": "GameLibraryTitle",
  "conceptId": "10000237",
  "entitlementId": "LIB-ENTITLEMENT-1",
  "image": { "__typename": "Media", "url": "https://image.api.playstation.com/astro.png" },
  "isActive": true,
  "lastPlayedDateTime": "2026-06-30T18:00:00.000Z",
  "name": "ASTRO's PLAYROOM",
  "platform": "PS5",
  "productId": "UP9000-PPSA01325_00-0000000000000000",
  "subscriptionService": "NONE",
  "titleId": "PPSA01325_00"
}
```

- [ ] **Step 2: Write the failing model spec**

`spec/psn_client/models/library_models_spec.rb`:

```ruby
# frozen_string_literal: true

RSpec.describe "library models" do
  describe PSN::LibraryTitle do
    subject(:title) { described_class.from_api(fixture("library_title")) }

    it "maps library title fields" do
      expect(title.name).to eq("ASTRO's PLAYROOM")
      expect(title.title_id).to eq("PPSA01325_00")
      expect(title.platform).to eq("PS5")
      expect(title.concept_id).to eq("10000237")
      expect(title.entitlement_id).to eq("LIB-ENTITLEMENT-1")
      expect(title.product_id).to eq("UP9000-PPSA01325_00-0000000000000000")
      expect(title.image_url).to eq("https://image.api.playstation.com/astro.png")
      expect(title.last_played_at).to eq(Time.utc(2026, 6, 30, 18, 0, 0))
      expect(title).to be_active
    end

    it "maps subscriptionService NONE to nil and keeps real services" do
      expect(title.subscription_service).to be_nil
      plus = described_class.from_api(fixture("library_title").merge("subscriptionService" => "PS_PLUS"))
      expect(plus.subscription_service).to eq("PS_PLUS")
    end
  end
end
```

Add the new spec file to both exclude lists in `.rubocop.yml` (it follows the same combined-file pattern as the existing model specs):

```yaml
RSpec/DescribeClass:
  Exclude:
    - "spec/psn_client/models/trophy_models_spec.rb"
    - "spec/psn_client/models/store_models_spec.rb"
    - "spec/psn_client/models/library_models_spec.rb"
```

```yaml
RSpec/SpecFilePathFormat:
  CustomTransform:
    PSN: psn_client
  Exclude:
    - "spec/psn_client/errors_spec.rb"
    - "spec/psn_client/models/game_title_spec.rb"
    - "spec/psn_client/models/trophy_models_spec.rb"
    - "spec/psn_client/models/library_models_spec.rb"
```

- [ ] **Step 3: Write the failing resource spec**

Append inside the top-level `RSpec.describe PSN::Resources::Games do` block in `spec/psn_client/resources/games_spec.rb`:

```ruby
  describe "#library" do
    it "fetches the game library via the getUserGameList persisted query" do
      response = { "data" => { "gameLibraryTitlesRetrieve" => { "games" => [fixture("library_title")] } } }
      allow(connection).to receive(:graphql)
        .with("getUserGameList",
              { "categories" => "ps4_game,ps5_native_game", "limit" => 200 },
              PSN::Resources::Games::LIBRARY_HASH)
        .and_return(response)

      result = games.library.to_a
      expect(result.size).to eq(1)
      expect(result.first).to be_a(PSN::LibraryTitle)
      expect(result.first.name).to eq("ASTRO's PLAYROOM")
    end

    it "passes a custom limit and returns a lazy enumerator" do
      allow(connection).to receive(:graphql)
        .with("getUserGameList", hash_including("limit" => 5), PSN::Resources::Games::LIBRARY_HASH)
        .and_return({ "data" => { "gameLibraryTitlesRetrieve" => { "games" => [] } } })

      expect(games.library(limit: 5)).to be_a(Enumerator::Lazy)
      expect(games.library(limit: 5).to_a).to eq([])
    end
  end
```

- [ ] **Step 4: Run tests to verify they fail**

Run: `bundle exec rspec spec/psn_client/models/library_models_spec.rb spec/psn_client/resources/games_spec.rb`
Expected: failures — `uninitialized constant PSN::LibraryTitle`, `undefined method 'library'`.

- [ ] **Step 5: Implement**

`lib/psn_client/models/library_title.rb`:

```ruby
# frozen_string_literal: true

module PSN
  LibraryTitle = Data.define(:name, :title_id, :platform, :concept_id, :entitlement_id,
                             :product_id, :image_url, :last_played_at, :active,
                             :subscription_service, :raw) do
    def self.from_api(hash)
      new(name: hash["name"], title_id: hash["titleId"], platform: hash["platform"],
          concept_id: hash["conceptId"], entitlement_id: hash["entitlementId"],
          product_id: hash["productId"], image_url: hash.dig("image", "url"),
          last_played_at: Mapping.time(hash["lastPlayedDateTime"]),
          active: hash["isActive"] == true,
          subscription_service: Mapping.subscription(hash["subscriptionService"]),
          raw: hash)
    end

    def active? = active
  end
end
```

Add to `lib/psn_client/models/mapping.rb` (after `platform`):

```ruby
    # "NONE" means a regular owned title -> nil; real services ("PS_PLUS", ...)
    # pass through unchanged.
    def subscription(value)
      value == "NONE" ? nil : value
    end
```

In `lib/psn_client/resources/games.rb`, add constants after `PAGE_SIZE` and the method after `played`:

```ruby
      # getUserGameList persisted query. Sony can change hash and shape at
      # any time; all knowledge of them is confined to this file. Verify
      # with bin/smoke.
      LIBRARY_OPERATION = "getUserGameList"
      LIBRARY_HASH = "e0136f81d7d1fb6be58238c574e9a46e1c0cc2f7f6977a08a5a46f224523a004"
      LIBRARY_CATEGORIES = "ps4_game,ps5_native_game"
      LIBRARY_LIMIT = 200
```

```ruby
      # The authenticated account's game library, owned and subscription
      # titles alike. Single request: the persisted query has no offset.
      def library(limit: LIBRARY_LIMIT)
        response = @connection.graphql(LIBRARY_OPERATION,
                                       { "categories" => LIBRARY_CATEGORIES, "limit" => limit },
                                       LIBRARY_HASH)
        titles = response.dig("data", "gameLibraryTitlesRetrieve", "games") || []
        titles.lazy.map { |title| LibraryTitle.from_api(title) }
      end
```

In `lib/psn_client.rb`, add after the `game_title` require:

```ruby
require_relative "psn_client/models/library_title"
```

- [ ] **Step 6: Run tests to verify they pass**

Run: `bundle exec rspec spec/psn_client/models/library_models_spec.rb spec/psn_client/resources/games_spec.rb`
Expected: PASS.

- [ ] **Step 7: Full check and commit**

Run: `bundle exec rake`
Expected: green.

```bash
git add lib/psn_client.rb lib/psn_client/models/library_title.rb lib/psn_client/models/mapping.rb \
  lib/psn_client/resources/games.rb spec/fixtures/library_title.json \
  spec/psn_client/models/library_models_spec.rb spec/psn_client/resources/games_spec.rb .rubocop.yml
git commit -m "feat: game library via getUserGameList persisted query"
```

---

### Task 3: games.purchased + PurchasedGame model

**Files:**
- Create: `lib/psn_client/models/purchased_game.rb`
- Create: `spec/fixtures/purchased_game.json`
- Modify: `lib/psn_client/resources/games.rb`
- Modify: `lib/psn_client.rb` (require line)
- Test: `spec/psn_client/models/library_models_spec.rb`, `spec/psn_client/resources/games_spec.rb`

**Interfaces:**
- Consumes: `Connection#graphql` (Task 1); `Paginator.offset(page_size:)` — yields `(limit, offset)`, second yield value `nil` means "no total: page until an empty page".
- Produces: `Games#purchased -> Enumerator::Lazy` of `PSN::PurchasedGame` (fields: `name, title_id, platform, concept_id, entitlement_id, product_id, image_url, active?/active, downloadable?/downloadable, pre_order?/pre_order, membership, raw`). Task 7 uses `purchased`.

- [ ] **Step 1: Create the fixture**

`spec/fixtures/purchased_game.json`:

```json
{
  "__typename": "PurchasedGame",
  "conceptId": "232076",
  "entitlementId": "PUR-ENTITLEMENT-1",
  "image": { "__typename": "Media", "url": "https://image.api.playstation.com/ghost.png" },
  "isActive": true,
  "isDownloadable": true,
  "isPreOrder": false,
  "membership": "NONE",
  "name": "Ghost of Tsushima",
  "platform": "PS4",
  "productId": "EP9000-CUSA13323_00-GHOSTSHIP0000000",
  "titleId": "CUSA13323_00"
}
```

- [ ] **Step 2: Write the failing model spec**

Append inside the top-level `RSpec.describe "library models" do` block in `spec/psn_client/models/library_models_spec.rb`:

```ruby
  describe PSN::PurchasedGame do
    subject(:game) { described_class.from_api(fixture("purchased_game")) }

    it "maps purchased game fields" do
      expect(game.name).to eq("Ghost of Tsushima")
      expect(game.title_id).to eq("CUSA13323_00")
      expect(game.platform).to eq("PS4")
      expect(game.concept_id).to eq("232076")
      expect(game.entitlement_id).to eq("PUR-ENTITLEMENT-1")
      expect(game.product_id).to eq("EP9000-CUSA13323_00-GHOSTSHIP0000000")
      expect(game.image_url).to eq("https://image.api.playstation.com/ghost.png")
      expect(game.membership).to eq("NONE")
      expect(game).to be_active
      expect(game).to be_downloadable
      expect(game).not_to be_pre_order
    end
  end
```

- [ ] **Step 3: Write the failing resource spec**

Append inside the `RSpec.describe PSN::Resources::Games do` block in `spec/psn_client/resources/games_spec.rb`:

```ruby
  describe "#purchased" do
    def purchased_response(games_page)
      { "data" => { "purchasedTitlesRetrieve" => { "games" => games_page } } }
    end

    it "pages via start/size until an empty page (no total in the response)" do
      allow(connection).to receive(:graphql)
        .with("getPurchasedGameList", hash_including("size" => 200, "start" => 0),
              PSN::Resources::Games::PURCHASED_HASH)
        .and_return(purchased_response(Array.new(200) { fixture("purchased_game") }))
      allow(connection).to receive(:graphql)
        .with("getPurchasedGameList", hash_including("start" => 200),
              PSN::Resources::Games::PURCHASED_HASH)
        .and_return(purchased_response([]))

      result = games.purchased.to_a
      expect(result.size).to eq(200)
      expect(result.first).to be_a(PSN::PurchasedGame)
      expect(connection).to have_received(:graphql).twice
    end

    it "is lazy: .first(n) stops after the first page" do
      allow(connection).to receive(:graphql)
        .with("getPurchasedGameList",
              { "isActive" => true, "platform" => %w[ps4 ps5], "sortBy" => "ACTIVE_DATE",
                "sortDirection" => "desc", "size" => 200, "start" => 0 },
              PSN::Resources::Games::PURCHASED_HASH)
        .and_return(purchased_response(Array.new(200) { fixture("purchased_game") }))

      expect(games.purchased.first(3).size).to eq(3)
      expect(connection).to have_received(:graphql).once
    end
  end
```

- [ ] **Step 4: Run tests to verify they fail**

Run: `bundle exec rspec spec/psn_client/models/library_models_spec.rb spec/psn_client/resources/games_spec.rb`
Expected: failures — `uninitialized constant PSN::PurchasedGame`, `undefined method 'purchased'`.

- [ ] **Step 5: Implement**

`lib/psn_client/models/purchased_game.rb`:

```ruby
# frozen_string_literal: true

module PSN
  PurchasedGame = Data.define(:name, :title_id, :platform, :concept_id, :entitlement_id,
                              :product_id, :image_url, :active, :downloadable,
                              :pre_order, :membership, :raw) do
    def self.from_api(hash)
      new(name: hash["name"], title_id: hash["titleId"], platform: hash["platform"],
          concept_id: hash["conceptId"], entitlement_id: hash["entitlementId"],
          product_id: hash["productId"], image_url: hash.dig("image", "url"),
          active: hash["isActive"] == true, downloadable: hash["isDownloadable"] == true,
          pre_order: hash["isPreOrder"] == true, membership: hash["membership"],
          raw: hash)
    end

    def active? = active
    def downloadable? = downloadable
    def pre_order? = pre_order
  end
end
```

In `lib/psn_client/resources/games.rb`, add constants after `LIBRARY_LIMIT` and the method after `library`:

```ruby
      PURCHASED_OPERATION = "getPurchasedGameList"
      PURCHASED_HASH = "827a423f6a8ddca4107ac01395af2ec0eafd8396fc7fa204aaf9b7ed2eefa168"
      PURCHASED_PAGE_SIZE = 200
      PURCHASED_VARIABLES = { "isActive" => true, "platform" => %w[ps4 ps5],
                              "sortBy" => "ACTIVE_DATE", "sortDirection" => "desc" }.freeze
```

```ruby
      # Purchased games for the authenticated account: the games-only
      # storefront view. store.entitlements is the full ownership ledger.
      # The persisted query returns no total count, so pages are fetched
      # until an empty one comes back.
      def purchased
        paginator = Paginator.offset(page_size: PURCHASED_PAGE_SIZE) do |size, start|
          response = @connection.graphql(PURCHASED_OPERATION,
                                         PURCHASED_VARIABLES.merge("size" => size, "start" => start),
                                         PURCHASED_HASH)
          [response.dig("data", "purchasedTitlesRetrieve", "games") || [], nil]
        end
        paginator.map { |game| PurchasedGame.from_api(game) }
      end
```

In `lib/psn_client.rb`, add after the `library_title` require:

```ruby
require_relative "psn_client/models/purchased_game"
```

- [ ] **Step 6: Run tests to verify they pass**

Run: `bundle exec rspec spec/psn_client/models/library_models_spec.rb spec/psn_client/resources/games_spec.rb`
Expected: PASS.

- [ ] **Step 7: Full check and commit**

Run: `bundle exec rake`
Expected: green.

```bash
git add lib/psn_client.rb lib/psn_client/models/purchased_game.rb lib/psn_client/resources/games.rb \
  spec/fixtures/purchased_game.json spec/psn_client/models/library_models_spec.rb \
  spec/psn_client/resources/games_spec.rb
git commit -m "feat: purchased games via getPurchasedGameList persisted query"
```

---

### Task 4: Profiles resource + Profile model

**Files:**
- Create: `lib/psn_client/models/profile.rb`
- Create: `lib/psn_client/resources/profiles.rb`
- Create: `spec/fixtures/profile.json`
- Create: `spec/psn_client/models/profile_spec.rb`
- Create: `spec/psn_client/resources/profiles_spec.rb`
- Modify: `lib/psn_client/connection.rb` (`:community` host)
- Modify: `lib/psn_client/client.rb` (`profiles` accessor)
- Modify: `lib/psn_client.rb` (require lines)
- Modify: `.rubocop.yml` (SpecFilePathFormat exclude for the model spec)
- Test: `spec/psn_client/client_spec.rb`

**Interfaces:**
- Consumes: `Connection#get(host, path, params)`; existing `TrophySummary` model (`Data.define(:level, :progress, :tier, :earned_counts, :raw)`); `Mapping.time`, `Mapping.grade_counts`.
- Produces: `client.profiles -> Resources::Profiles`; `Profiles#find(online_id = nil) -> PSN::Profile` (fields: `online_id, account_id, avatar_url, plus?/plus, about_me, languages, verified?/verified, trophy_summary, online?/online, platform, last_online_at, raw`); `Connection::HOSTS[:community] = "https://us-prof.np.community.playstation.net"`. Task 7 uses `profiles.find`.

- [ ] **Step 1: Create the fixture**

`spec/fixtures/profile.json` (the inner `"profile"` object of a profile2 response):

```json
{
  "onlineId": "MattyJ",
  "accountId": "1234567890123456789",
  "npId": "TWF0dHlK@b6.gb",
  "avatarUrls": [
    { "size": "m", "avatarUrl": "https://static-resource.np.community.playstation.net/avatar_m.png" },
    { "size": "l", "avatarUrl": "https://static-resource.np.community.playstation.net/avatar_l.png" }
  ],
  "plus": 1,
  "aboutMe": "Backlog wrangler",
  "languagesUsed": ["en"],
  "trophySummary": {
    "level": 421,
    "progress": 37,
    "earnedTrophies": { "platinum": 12, "gold": 89, "silver": 320, "bronze": 1204 }
  },
  "isOfficiallyVerified": false,
  "personalDetailSharing": "no",
  "primaryOnlineStatus": "offline",
  "presences": [
    { "onlineStatus": "offline", "platform": "PS5", "lastOnlineDate": "2026-07-05T22:14:00.000Z" }
  ]
}
```

- [ ] **Step 2: Write the failing model spec**

`spec/psn_client/models/profile_spec.rb`:

```ruby
# frozen_string_literal: true

RSpec.describe PSN::Profile do
  subject(:profile) { described_class.from_api(fixture("profile")) }

  it "maps identity and account fields" do
    expect(profile.online_id).to eq("MattyJ")
    expect(profile.account_id).to eq("1234567890123456789")
    expect(profile.about_me).to eq("Backlog wrangler")
    expect(profile.languages).to eq(["en"])
    expect(profile).to be_plus
    expect(profile).not_to be_verified
  end

  it "picks the largest avatar" do
    expect(profile.avatar_url).to eq("https://static-resource.np.community.playstation.net/avatar_l.png")
  end

  it "maps the trophy summary into TrophySummary" do
    expect(profile.trophy_summary).to be_a(PSN::TrophySummary)
    expect(profile.trophy_summary.level).to eq(421)
    expect(profile.trophy_summary.progress).to eq(37)
    expect(profile.trophy_summary.earned_counts).to eq(bronze: 1204, silver: 320, gold: 89, platinum: 12)
  end

  it "maps presence" do
    expect(profile).not_to be_online
    expect(profile.platform).to eq("PS5")
    expect(profile.last_online_at).to eq(Time.utc(2026, 7, 5, 22, 14, 0))
  end

  it "tolerates missing optional sections" do
    bare = described_class.from_api(fixture("profile").except("trophySummary", "presences", "avatarUrls"))
    expect(bare.trophy_summary).to be_nil
    expect(bare.avatar_url).to be_nil
    expect(bare.online).to be(false)
    expect(bare.platform).to be_nil
  end
end
```

Add the file to the `RSpec/SpecFilePathFormat` exclude list in `.rubocop.yml` (it lives under `models/`, which the cop's path transform doesn't expect — same as `game_title_spec.rb`):

```yaml
    - "spec/psn_client/models/profile_spec.rb"
```

- [ ] **Step 3: Write the failing resource spec**

`spec/psn_client/resources/profiles_spec.rb`:

```ruby
# frozen_string_literal: true

RSpec.describe PSN::Resources::Profiles do
  subject(:profiles) { described_class.new(connection) }

  let(:connection) { instance_double(PSN::Connection) }

  it "fetches a profile by online ID from the community host" do
    allow(connection).to receive(:get)
      .with(:community, "/userProfile/v1/users/MattyJ/profile2",
            { "fields" => described_class::PROFILE2_FIELDS })
      .and_return({ "profile" => fixture("profile") })

    profile = profiles.find("MattyJ")
    expect(profile).to be_a(PSN::Profile)
    expect(profile.online_id).to eq("MattyJ")
    expect(profile.account_id).to eq("1234567890123456789")
  end

  it "resolves and memoizes the own online ID for the authenticated account" do
    allow(connection).to receive(:get)
      .with(:mobile, "/api/userProfile/v1/internal/users/me/profiles", {})
      .and_return({ "onlineId" => "MattyJ" })
    allow(connection).to receive(:get)
      .with(:community, "/userProfile/v1/users/MattyJ/profile2", anything)
      .and_return({ "profile" => fixture("profile") })

    2.times { expect(profiles.find.online_id).to eq("MattyJ") }
    expect(connection).to have_received(:get)
      .with(:mobile, "/api/userProfile/v1/internal/users/me/profiles", {}).once
    expect(connection).to have_received(:get)
      .with(:community, "/userProfile/v1/users/MattyJ/profile2", anything).twice
  end
end
```

Also update the facade test — in `spec/psn_client/client_spec.rb`, inside `it "exposes memoized resource objects"`, add after the `store` expectation:

```ruby
    expect(client.profiles).to be_a(PSN::Resources::Profiles)
```

- [ ] **Step 4: Run tests to verify they fail**

Run: `bundle exec rspec spec/psn_client/models/profile_spec.rb spec/psn_client/resources/profiles_spec.rb spec/psn_client/client_spec.rb`
Expected: failures — `uninitialized constant PSN::Profile`, `uninitialized constant PSN::Resources::Profiles`.

- [ ] **Step 5: Implement**

In `lib/psn_client/connection.rb`, extend `HOSTS`:

```ruby
    HOSTS = {
      mobile: "https://m.np.playstation.com",
      web: "https://web.np.playstation.com",
      community: "https://us-prof.np.community.playstation.net"
    }.freeze
```

`lib/psn_client/models/profile.rb`:

```ruby
# frozen_string_literal: true

module PSN
  Profile = Data.define(:online_id, :account_id, :avatar_url, :plus, :about_me, :languages,
                        :verified, :trophy_summary, :online, :platform, :last_online_at, :raw) do
    AVATAR_SIZE_ORDER = %w[xl l m s].freeze

    def self.from_api(hash)
      presence = hash.dig("presences", 0) || {}
      new(online_id: hash["onlineId"], account_id: hash["accountId"],
          avatar_url: largest_avatar(hash["avatarUrls"]),
          plus: hash["plus"].to_i.positive?, about_me: hash["aboutMe"],
          languages: hash["languagesUsed"], verified: hash["isOfficiallyVerified"] == true,
          trophy_summary: summary(hash["trophySummary"]),
          online: presence["onlineStatus"] == "online", platform: presence["platform"],
          last_online_at: Mapping.time(presence["lastOnlineDate"]), raw: hash)
    end

    # profile2 nests the summary under different keys than the trophy API
    # ("level" instead of "trophyLevel", no tier), so map it by hand.
    def self.summary(hash)
      return nil unless hash

      TrophySummary.new(level: hash["level"], progress: hash["progress"], tier: nil,
                        earned_counts: Mapping.grade_counts(hash["earnedTrophies"]), raw: hash)
    end

    def self.largest_avatar(urls)
      return nil if urls.nil? || urls.empty?

      by_size = urls.to_h { |u| [u["size"], u["avatarUrl"]] }
      AVATAR_SIZE_ORDER.filter_map { |size| by_size[size] }.first || urls.first["avatarUrl"]
    end

    def plus? = plus
    def verified? = verified
    def online? = online
  end
end
```

`lib/psn_client/resources/profiles.rb`:

```ruby
# frozen_string_literal: true

module PSN
  module Resources
    # Rich user profiles via the legacy community profile2 endpoint (the
    # newer mobile profile API returns far fewer fields). For the
    # authenticated account the own online ID is resolved first, so every
    # caller gets the same rich shape back.
    class Profiles
      PROFILE2_PATH = "/userProfile/v1/users/%s/profile2"
      PROFILE2_FIELDS = "npId,onlineId,accountId,avatarUrls,plus,aboutMe,languagesUsed," \
                        "trophySummary(@default,level,progress,earnedTrophies)," \
                        "isOfficiallyVerified,primaryOnlineStatus," \
                        "presences(@default,@titleInfo,platform,lastOnlineDate)"
      ME_PATH = "/api/userProfile/v1/internal/users/me/profiles"

      def initialize(connection)
        @connection = connection
      end

      def find(online_id = nil)
        online_id ||= own_online_id
        response = @connection.get(:community, format(PROFILE2_PATH, online_id),
                                   { "fields" => PROFILE2_FIELDS })
        Profile.from_api(response["profile"])
      end

      private

      def own_online_id
        @own_online_id ||= @connection.get(:mobile, ME_PATH, {})["onlineId"]
      end
    end
  end
end
```

In `lib/psn_client/client.rb`, add after the `store` accessor:

```ruby
    def profiles = @profiles ||= Resources::Profiles.new(@connection)
```

In `lib/psn_client.rb`, add `require_relative "psn_client/models/profile"` after the `purchased_game` require and `require_relative "psn_client/resources/profiles"` after the `resources/store` require.

- [ ] **Step 6: Run tests to verify they pass**

Run: `bundle exec rspec spec/psn_client/models/profile_spec.rb spec/psn_client/resources/profiles_spec.rb spec/psn_client/client_spec.rb`
Expected: PASS.

- [ ] **Step 7: Full check and commit**

Run: `bundle exec rake`
Expected: green.

```bash
git add lib/psn_client.rb lib/psn_client/client.rb lib/psn_client/connection.rb \
  lib/psn_client/models/profile.rb lib/psn_client/resources/profiles.rb \
  spec/fixtures/profile.json spec/psn_client/models/profile_spec.rb \
  spec/psn_client/resources/profiles_spec.rb spec/psn_client/client_spec.rb .rubocop.yml
git commit -m "feat: profiles resource with rich profile2 lookup"
```

---

### Task 5: trophies.title_summary + TitleTrophySummary model

**Files:**
- Create: `lib/psn_client/models/title_trophy_summary.rb`
- Create: `spec/fixtures/title_trophy_summary.json`
- Modify: `lib/psn_client/resources/trophies.rb`
- Modify: `lib/psn_client.rb` (require line)
- Test: `spec/psn_client/models/trophy_models_spec.rb`, `spec/psn_client/resources/trophies_spec.rb`

**Interfaces:**
- Consumes: `Connection#get`; `Users#account_id(online_id)`; existing `TrophyTitle.from_api`.
- Produces: `Trophies#title_summary(online_id = nil, title_ids:) -> Enumerator::Lazy` of `PSN::TitleTrophySummary` (fields: `np_title_id, trophy_titles` (array of `TrophyTitle`), `raw`). Task 7 uses `title_summary`.

- [ ] **Step 1: Create the fixture**

`spec/fixtures/title_trophy_summary.json`:

```json
{
  "npTitleId": "PPSA01325_00",
  "trophyTitles": [
    {
      "npServiceName": "trophy2",
      "npCommunicationId": "NPWR20188_00",
      "trophyTitleName": "ASTRO's PLAYROOM",
      "trophyTitlePlatform": "PS5",
      "progress": 71,
      "definedTrophies": { "bronze": 24, "silver": 12, "gold": 6, "platinum": 1 },
      "earnedTrophies": { "bronze": 20, "silver": 8, "gold": 2, "platinum": 0 }
    }
  ]
}
```

- [ ] **Step 2: Write the failing model spec**

Append inside the top-level `RSpec.describe "trophy models" do` block in `spec/psn_client/models/trophy_models_spec.rb`:

```ruby
  describe PSN::TitleTrophySummary do
    subject(:summary) { described_class.from_api(fixture("title_trophy_summary")) }

    it "maps the title ID and nested trophy titles" do
      expect(summary.np_title_id).to eq("PPSA01325_00")
      expect(summary.trophy_titles.size).to eq(1)
      expect(summary.trophy_titles.first).to be_a(PSN::TrophyTitle)
      expect(summary.trophy_titles.first.np_communication_id).to eq("NPWR20188_00")
      expect(summary.trophy_titles.first.progress).to eq(71)
    end

    it "maps a title with no trophy sets to an empty array" do
      none = described_class.from_api(fixture("title_trophy_summary").merge("trophyTitles" => []))
      expect(none.trophy_titles).to eq([])
    end
  end
```

- [ ] **Step 3: Write the failing resource spec**

Append inside the top-level `RSpec.describe PSN::Resources::Trophies do` block in `spec/psn_client/resources/trophies_spec.rb` (it uses the same `connection` / `users` instance_doubles as the existing examples):

```ruby
  describe "#title_summary" do
    it "chunks title IDs into batches of 5 per request" do
      allow(users).to receive(:account_id).with(nil).and_return("me")
      ids = %w[A_00 B_00 C_00 D_00 E_00 F_00]
      allow(connection).to receive(:get)
        .with(:mobile, "/api/trophy/v1/users/me/titles/trophyTitles",
              { "npTitleIds" => "A_00,B_00,C_00,D_00,E_00" })
        .and_return({ "titles" => [fixture("title_trophy_summary")] })
      allow(connection).to receive(:get)
        .with(:mobile, "/api/trophy/v1/users/me/titles/trophyTitles", { "npTitleIds" => "F_00" })
        .and_return({ "titles" => [fixture("title_trophy_summary")] })

      result = trophies.title_summary(title_ids: ids).to_a
      expect(result.size).to eq(2)
      expect(result.first).to be_a(PSN::TitleTrophySummary)
      expect(connection).to have_received(:get).twice
    end

    it "is lazy across batches and resolves the online ID" do
      allow(users).to receive(:account_id).with("friend").and_return("42")
      allow(connection).to receive(:get)
        .with(:mobile, "/api/trophy/v1/users/42/titles/trophyTitles",
              { "npTitleIds" => "A_00,B_00,C_00,D_00,E_00" })
        .and_return({ "titles" => [fixture("title_trophy_summary")] })

      result = trophies.title_summary("friend", title_ids: %w[A_00 B_00 C_00 D_00 E_00 F_00])
      expect(result.first(1).size).to eq(1)
      expect(connection).to have_received(:get).once # second batch never requested
    end
  end
```

- [ ] **Step 4: Run tests to verify they fail**

Run: `bundle exec rspec spec/psn_client/models/trophy_models_spec.rb spec/psn_client/resources/trophies_spec.rb`
Expected: failures — `uninitialized constant PSN::TitleTrophySummary`, `undefined method 'title_summary'`.

- [ ] **Step 5: Implement**

`lib/psn_client/models/title_trophy_summary.rb`:

```ruby
# frozen_string_literal: true

module PSN
  TitleTrophySummary = Data.define(:np_title_id, :trophy_titles, :raw) do
    def self.from_api(hash)
      new(np_title_id: hash["npTitleId"],
          trophy_titles: (hash["trophyTitles"] || []).map { |t| TrophyTitle.from_api(t) },
          raw: hash)
    end
  end
end
```

In `lib/psn_client/resources/trophies.rb`, add constants after `PAGE_SIZE`:

```ruby
      TITLE_SUMMARY_PATH = "/api/trophy/v1/users/%s/titles/trophyTitles"
      TITLE_IDS_PER_REQUEST = 5
```

Add the method after `summary`:

```ruby
      # Trophy progress for specific title IDs (CUSA/PPSA...). The API caps
      # each request at 5 IDs, so larger lists are fetched in lazy batches.
      def title_summary(online_id = nil, title_ids:)
        account_id = @users.account_id(online_id)
        title_ids.each_slice(TITLE_IDS_PER_REQUEST).lazy.flat_map do |batch|
          response = @connection.get(:mobile, format(TITLE_SUMMARY_PATH, account_id),
                                     { "npTitleIds" => batch.join(",") })
          (response["titles"] || []).map { |title| TitleTrophySummary.from_api(title) }
        end
      end
```

In `lib/psn_client.rb`, add after the `trophy_summary` require:

```ruby
require_relative "psn_client/models/title_trophy_summary"
```

- [ ] **Step 6: Run tests to verify they pass**

Run: `bundle exec rspec spec/psn_client/models/trophy_models_spec.rb spec/psn_client/resources/trophies_spec.rb`
Expected: PASS.

- [ ] **Step 7: Full check and commit**

Run: `bundle exec rake`
Expected: green.

```bash
git add lib/psn_client.rb lib/psn_client/models/title_trophy_summary.rb \
  lib/psn_client/resources/trophies.rb spec/fixtures/title_trophy_summary.json \
  spec/psn_client/models/trophy_models_spec.rb spec/psn_client/resources/trophies_spec.rb
git commit -m "feat: per-title trophy summary with batched npTitleIds"
```

---

### Task 6: trophies.groups + TrophyGroup model

**Files:**
- Create: `lib/psn_client/models/trophy_group.rb`
- Create: `spec/fixtures/trophy_group_definition.json`
- Create: `spec/fixtures/trophy_group_earned.json`
- Modify: `lib/psn_client/resources/trophies.rb`
- Modify: `lib/psn_client.rb` (require line)
- Test: `spec/psn_client/models/trophy_models_spec.rb`, `spec/psn_client/resources/trophies_spec.rb`

**Interfaces:**
- Consumes: `Connection#get`; `Users#account_id`; the resource's existing private `service_params(platform)` helper.
- Produces: `Trophies#groups(online_id = nil, np_communication_id:, platform: nil) -> Enumerator::Lazy` of `PSN::TrophyGroup` (fields: `group_id, name, icon_url, defined_counts, earned_counts, progress, raw`). Task 7 uses `groups`.

- [ ] **Step 1: Create the fixtures**

`spec/fixtures/trophy_group_definition.json`:

```json
{
  "trophyGroupId": "default",
  "trophyGroupName": "ASTRO's PLAYROOM",
  "trophyGroupIconUrl": "https://psnobj.prod.dl.playstation.net/psnobj/NPWR20188_00/group_default.png",
  "definedTrophies": { "bronze": 24, "silver": 12, "gold": 6, "platinum": 1 }
}
```

`spec/fixtures/trophy_group_earned.json`:

```json
{
  "trophyGroupId": "default",
  "progress": 83,
  "earnedTrophies": { "bronze": 20, "silver": 8, "gold": 2, "platinum": 0 },
  "lastUpdatedDateTime": "2026-06-01T10:00:00.000Z"
}
```

- [ ] **Step 2: Write the failing model spec**

Append inside the `RSpec.describe "trophy models" do` block in `spec/psn_client/models/trophy_models_spec.rb`:

```ruby
  describe PSN::TrophyGroup do
    subject(:group) do
      described_class.from_api(fixture("trophy_group_definition").merge(fixture("trophy_group_earned")))
    end

    it "maps merged definition and earned fields" do
      expect(group.group_id).to eq("default")
      expect(group.name).to eq("ASTRO's PLAYROOM")
      expect(group.icon_url).to match(%r{^https://})
      expect(group.defined_counts).to eq(bronze: 24, silver: 12, gold: 6, platinum: 1)
      expect(group.earned_counts).to eq(bronze: 20, silver: 8, gold: 2, platinum: 0)
      expect(group.progress).to eq(83)
    end

    it "leaves earned fields nil when only the definition is present" do
      definition_only = described_class.from_api(fixture("trophy_group_definition"))
      expect(definition_only.earned_counts).to be_nil
      expect(definition_only.progress).to be_nil
    end
  end
```

- [ ] **Step 3: Write the failing resource spec**

Append inside the `RSpec.describe PSN::Resources::Trophies do` block in `spec/psn_client/resources/trophies_spec.rb`:

```ruby
  describe "#groups" do
    it "merges group definitions with the account's earned progress" do
      allow(users).to receive(:account_id).with(nil).and_return("me")
      allow(connection).to receive(:get)
        .with(:mobile, "/api/trophy/v1/npCommunicationIds/NPWR20188_00/trophyGroups", {})
        .and_return({ "trophyGroups" => [fixture("trophy_group_definition")] })
      allow(connection).to receive(:get)
        .with(:mobile, "/api/trophy/v1/users/me/npCommunicationIds/NPWR20188_00/trophyGroups", {})
        .and_return({ "trophyGroups" => [fixture("trophy_group_earned")] })

      result = trophies.groups(np_communication_id: "NPWR20188_00").to_a
      expect(result.size).to eq(1)
      expect(result.first).to be_a(PSN::TrophyGroup)
      expect(result.first.progress).to eq(83)
      expect(result.first.defined_counts).to eq(bronze: 24, silver: 12, gold: 6, platinum: 1)
    end

    it "sends npServiceName=trophy for pre-PS5 platforms" do
      allow(users).to receive(:account_id).with(nil).and_return("me")
      allow(connection).to receive(:get)
        .with(:mobile, "/api/trophy/v1/npCommunicationIds/NPWR00001_00/trophyGroups",
              { "npServiceName" => "trophy" })
        .and_return({ "trophyGroups" => [fixture("trophy_group_definition")] })
      allow(connection).to receive(:get)
        .with(:mobile, "/api/trophy/v1/users/me/npCommunicationIds/NPWR00001_00/trophyGroups",
              { "npServiceName" => "trophy" })
        .and_return({ "trophyGroups" => [] })

      result = trophies.groups(np_communication_id: "NPWR00001_00", platform: "PS4").to_a
      expect(result.first.earned_counts).to be_nil
    end
  end
```

- [ ] **Step 4: Run tests to verify they fail**

Run: `bundle exec rspec spec/psn_client/models/trophy_models_spec.rb spec/psn_client/resources/trophies_spec.rb`
Expected: failures — `uninitialized constant PSN::TrophyGroup`, `undefined method 'groups'`.

- [ ] **Step 5: Implement**

`lib/psn_client/models/trophy_group.rb`:

```ruby
# frozen_string_literal: true

module PSN
  TrophyGroup = Data.define(:group_id, :name, :icon_url, :defined_counts,
                            :earned_counts, :progress, :raw) do
    def self.from_api(hash)
      new(group_id: hash["trophyGroupId"], name: hash["trophyGroupName"],
          icon_url: hash["trophyGroupIconUrl"],
          defined_counts: Mapping.grade_counts(hash["definedTrophies"]),
          earned_counts: Mapping.grade_counts(hash["earnedTrophies"]),
          progress: hash["progress"], raw: hash)
    end
  end
end
```

In `lib/psn_client/resources/trophies.rb`, add constants after `TITLE_IDS_PER_REQUEST`:

```ruby
      GROUPS_DEFINITIONS_PATH = "/api/trophy/v1/npCommunicationIds/%s/trophyGroups"
      GROUPS_EARNED_PATH = "/api/trophy/v1/users/%s/npCommunicationIds/%s/trophyGroups"
```

Add the public method after `earned`:

```ruby
      # Trophy groups for one title (base game is "default", DLC packs are
      # "001", "002", ...), each merged with the account's progress.
      def groups(online_id = nil, np_communication_id:, platform: nil)
        account_id = @users.account_id(online_id)
        params = service_params(platform)
        definitions = @connection.get(:mobile, format(GROUPS_DEFINITIONS_PATH, np_communication_id), params)
        earned = @connection.get(:mobile, format(GROUPS_EARNED_PATH, account_id, np_communication_id), params)
        merge_groups(definitions["trophyGroups"] || [], earned["trophyGroups"] || []).lazy
      end
```

Add the private helper after `merge`:

```ruby
      def merge_groups(definitions, earned)
        earned_by_id = earned.to_h { |g| [g["trophyGroupId"], g] }
        definitions.map { |d| TrophyGroup.from_api(d.merge(earned_by_id[d["trophyGroupId"]] || {})) }
      end
```

In `lib/psn_client.rb`, add after the `title_trophy_summary` require:

```ruby
require_relative "psn_client/models/trophy_group"
```

- [ ] **Step 6: Run tests to verify they pass**

Run: `bundle exec rspec spec/psn_client/models/trophy_models_spec.rb spec/psn_client/resources/trophies_spec.rb`
Expected: PASS.

- [ ] **Step 7: Full check and commit**

Run: `bundle exec rake`
Expected: green.

```bash
git add lib/psn_client.rb lib/psn_client/models/trophy_group.rb \
  lib/psn_client/resources/trophies.rb spec/fixtures/trophy_group_definition.json \
  spec/fixtures/trophy_group_earned.json spec/psn_client/models/trophy_models_spec.rb \
  spec/psn_client/resources/trophies_spec.rb
git commit -m "feat: trophy groups merged with earned progress"
```

---

### Task 7: README + bin/smoke

**Files:**
- Modify: `README.md`
- Modify: `bin/smoke`

**Interfaces:**
- Consumes: everything produced by Tasks 2-6 (`games.library`, `games.purchased`, `profiles.find`, `trophies.title_summary`, `trophies.groups`).
- Produces: user-facing docs and the live-API safety net.

- [ ] **Step 1: Update the README usage section**

In `README.md`, replace the usage example block (the ```` ```ruby ```` block starting `# Games played`) with:

```ruby
# Games played (any account whose privacy settings allow it)
client.games.played.first(10).each { |g| puts "#{g.name} [#{g.platform}]" }
client.games.played("a_friend").to_a

# Game library and purchases (authenticated account only, GraphQL)
client.games.library.to_a                 # owned + subscription titles
client.games.purchased.first(20)          # games-only storefront view

# Profiles
client.profiles.find                      # authenticated account
client.profiles.find("a_friend")          # avatar, PS Plus, presence, trophy level

# Trophies
client.trophies.summary                                  # level, counts
client.trophies.titles.to_a                              # per-game progress
client.trophies.earned(np_communication_id: "NPWR20188_00")
client.trophies.earned("a_friend", np_communication_id: "NPWR00000_00", platform: "PS4")
client.trophies.title_summary(title_ids: %w[PPSA01325_00 CUSA13323_00])
client.trophies.groups(np_communication_id: "NPWR20188_00")  # base game vs DLC

# Purchases (authenticated account only)
client.store.transactions.first(20)  # orders, refunds, wallet funding
client.store.entitlements.to_a       # everything owned incl. free claims
```

After that block, add a short paragraph:

```markdown
`games.purchased` and `store.entitlements` overlap but answer different
questions: `purchased` is the games-only library view (artwork,
`downloadable?`, `pre_order?`), `entitlements` is the complete ownership
ledger down to DLC and free claims, and `transactions` is the only source
of monetary data.
```

Also update the note near the end of the README from:

> Note: the transaction/entitlement endpoints are undocumented and may change; they live in `lib/psn_client/resources/store.rb` if they need updating.

to:

```markdown
Note: the transaction/entitlement endpoints, the GraphQL persisted queries
and the legacy profile endpoint are undocumented and may change; they live
in `lib/psn_client/resources/store.rb`, `lib/psn_client/resources/games.rb`
and `lib/psn_client/resources/profiles.rb` if they need updating.
```

- [ ] **Step 2: Extend bin/smoke**

Add these sections to `bin/smoke` before the final refresh-token output:

```ruby
section("Profile") do
  p = client.profiles.find
  puts "#{p.online_id} plus=#{p.plus?} level=#{p.trophy_summary&.level} avatar=#{p.avatar_url}"
end

section("5 library titles") do
  client.games.library.first(5).each { |g| puts "#{g.name} [#{g.platform}] sub=#{g.subscription_service || '-'}" }
end

section("5 purchased games") do
  client.games.purchased.first(5).each { |g| puts "#{g.name} [#{g.platform}] downloadable=#{g.downloadable?}" }
end

section("Trophy title summary for 2 recent games") do
  ids = client.games.played.first(2).map(&:title_id)
  client.trophies.title_summary(title_ids: ids).each do |s|
    s.trophy_titles.each { |t| puts "#{s.np_title_id}: #{t.name} #{t.progress}%" }
  end
end

section("Trophy groups for most recent trophy title") do
  title = client.trophies.titles.first(1).first
  client.trophies.groups(np_communication_id: title.np_communication_id,
                         platform: title.platform).each do |g|
    puts "#{g.group_id}: #{g.name} #{g.progress}%"
  end
end
```

- [ ] **Step 3: Full check**

Run: `bundle exec rake`
Expected: green (rubocop also lints `bin/smoke`).

- [ ] **Step 4: Commit**

```bash
git add README.md bin/smoke
git commit -m "docs: README and smoke coverage for library, purchases, profiles, trophy extras"
```

- [ ] **Step 5: Live verification (needs credentials — ask the user)**

The GraphQL hashes, response shapes and the legacy profile host are exactly the undocumented parts; the WebMock specs cannot prove them. Ask the user to run:

```powershell
$env:PSN_NPSSO = "<token>"; ruby bin/smoke
```

Expected: every section prints data (or a meaningful `PrivacyError` for restricted data); no `APIError: PSN GraphQL error: PersistedQueryNotFound`. If a section fails, the response-shape knowledge in the corresponding resource file is what needs adjusting.
