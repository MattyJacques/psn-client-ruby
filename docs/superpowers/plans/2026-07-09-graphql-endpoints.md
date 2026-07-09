# Sony GraphQL Persisted-Query Endpoints Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add four groups of Sony persisted GraphQL queries to psn-client-ruby: game/user search, store catalog lookups (product/concept/pricing/add-ons), trophy Game Help, and web-host category browsing + star ratings.

**Architecture:** `Connection#graphql` gains `host:`/`headers:` keywords (default `:mobile` keeps existing callers working). Two new resources — `client.search` (mobile host, authenticated) and `client.catalog` (web host `web.np.playstation.com`, anonymous-capable) — plus two Game Help methods on the existing `Trophies` resource. Per the repo rule, all knowledge of each undocumented endpoint (operation names, sha256 hashes, response root keys) is confined to its one resource file. New models are immutable `Data.define` value objects with `from_api` + `raw`, and all list endpoints return `Enumerator::Lazy` via `Paginator`.

**Tech Stack:** Ruby 3.2+, Faraday, RSpec + WebMock (`instance_double(PSN::Connection)` for resources), RuboCop, SimpleCov gate 99% line / 85% branch.

**Provenance of hashes/shapes (recorded here so the engineer doesn't have to re-research):**
- Search ops (`metGetContextSearchResults`, `metGetDomainSearchResults`): mirrored exactly from the actively-maintained [psnawp](https://github.com/isFakeAccount/psnawp) Python library (`src/psnawp_api/models/search/*.py`). The context (first-page) and domain (follow-up) queries have **different hashes per search context** (games vs users). Games domain pages do **not** send `displayTitleLocale`; users domain pages do — mirror this exactly, persisted queries are picky.
- Catalog ops: hashes from [mrt1m/playstation-store-api](https://github.com/mrt1m/playstation-store-api) and [Tustin/psn-php](https://github.com/Tustin/psn-php). **Response root keys and shapes were verified live on 2026-07-09 by anonymous curl against `web.np.playstation.com/api/graphql/v1/op`**: `metGetProductById` → `data.productRetrieve`; `metGetConceptById` → `data.conceptRetrieve`; `metGetPricingDataByConceptId` → `data.conceptRetrieve.defaultProduct.price`; `metGetAddOnsByTitleId` → `data.addOnProductsByTitleIdRetrieve` (`addOnProducts` + `pageInfo.totalCount`); `categoryGridRetrieve` → `data.categoryGridRetrieve` (`products` + `pageInfo.totalCount`); `wcaProductStarRatingRetrive` (Sony's typo, sic) → `data.productRetrieve.starRating`; `wcaConceptStarRatingRetrive` → `data.conceptRetrieve.defaultProduct.starRating`.
- Game Help ops (`metGetHintAvailability`, `metGetTips`): fully documented with request/response examples at [andshrew/PlayStation-Trophies APIv2.md](https://github.com/andshrew/PlayStation-Trophies/blob/master/docs/APIv2.md) (Game Help section). Both require the `apollographql-client-name: PlayStationApp-Android` header. `metGetTips` content is PS+-gated via a `hasAccess` boolean.
- One quirk verified live: `productRetrieve` returns `releaseDate` as a plain ISO string, while `conceptRetrieve` returns `{"type": ..., "value": "<iso>"}` — the two detail models parse it differently on purpose.

**File map:**

| File | Role |
|---|---|
| `lib/psn_client/connection.rb` (modify) | `graphql` gains `host:`/`headers:` |
| `lib/psn_client/models/price.rb` (create) | `PSN::Price` — Sony `SkuPrice` shape |
| `lib/psn_client/models/catalog_item.rb` (create) | `PSN::CatalogItem` — Product/Concept card (search results, category grids, add-on lists) |
| `lib/psn_client/models/user_search_result.rb` (create) | `PSN::UserSearchResult` — `Player` shape |
| `lib/psn_client/models/star_rating.rb` (create) | `PSN::StarRating` |
| `lib/psn_client/models/store_product.rb` (create) | `PSN::StoreProduct` — full product detail |
| `lib/psn_client/models/store_concept.rb` (create) | `PSN::StoreConcept` — full concept detail |
| `lib/psn_client/models/game_help.rb` (create) | `PSN::TrophyHelpInfo`, `PSN::GameHelp`, `PSN::TrophyTip`, `PSN::TipContent` |
| `lib/psn_client/resources/search.rb` (create) | search endpoint knowledge |
| `lib/psn_client/resources/catalog.rb` (create) | web-host catalog endpoint knowledge |
| `lib/psn_client/resources/trophies.rb` (modify) | Game Help endpoint knowledge |
| `lib/psn_client/client.rb`, `lib/psn_client.rb` (modify) | wiring + requires |
| `bin/smoke`, `CLAUDE.md`, `README.md` (modify) | live checks + docs |

Watch out for RuboCop `Metrics/ClassLength` max 100 (why catalog is NOT bolted onto `Store`), `RSpec/ExampleLength` max 15 (put big stub payloads in `let`), and `RSpec/MultipleExpectations` max 5 for resource specs.

---

### Task 0: Branch

- [ ] **Step 1: Create the feature branch**

```bash
cd /home/matty/Development/psn-client-ruby
git checkout -b feat/graphql-search-catalog-help
```

### Task 1: `Connection#graphql` host + headers

**Files:**
- Modify: `lib/psn_client/connection.rb:45-53`
- Test: `spec/psn_client/connection_spec.rb` (inside the existing `describe "#graphql"` block)

- [ ] **Step 1: Write the failing test**

Add inside `describe "#graphql"` (after the existing examples, before its closing `end`):

```ruby
    it "targets another host and merges extra headers when asked" do
      stub_request(:get, "https://web.np.playstation.com/api/graphql/v1/op")
        .with(query: hash_including("operationName" => "getThing"),
              headers: { "Apollo-Require-Preflight" => "true", "X-Extra" => "1" })
        .to_return(json_response({ "data" => { "ok" => true } }))

      body = connection.graphql("getThing", {}, "abc123", host: :web, headers: { "X-Extra" => "1" })
      expect(body).to eq("data" => { "ok" => true })
    end
```

- [ ] **Step 2: Run it to make sure it fails**

Run: `bundle exec rspec spec/psn_client/connection_spec.rb`
Expected: FAIL with `ArgumentError` (unknown keywords: `:host`, `:headers`).

- [ ] **Step 3: Implement**

In `lib/psn_client/connection.rb` replace the `graphql` method:

```ruby
    # Persisted-query GraphQL GET. Sony's GraphQL can fail with HTTP 200 and
    # an errors array in the body, so that case is mapped to APIError here.
    # The mobile app's queries live on :mobile; the web store's anonymous
    # catalog queries live on :web — same /api/graphql/v1/op path on both.
    def graphql(operation_name, variables, sha256_hash, host: :mobile, headers: {})
      extensions = { "persistedQuery" => { "version" => 1, "sha256Hash" => sha256_hash } }
      params = { "operationName" => operation_name,
                 "variables" => JSON.generate(variables),
                 "extensions" => JSON.generate(extensions) }
      body = request(host, :get, GRAPHQL_PATH, params, headers: GRAPHQL_HEADERS.merge(headers))
      handle_graphql_errors(body)
      body
    end
```

- [ ] **Step 4: Run the tests**

Run: `bundle exec rspec spec/psn_client/connection_spec.rb`
Expected: all PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/psn_client/connection.rb spec/psn_client/connection_spec.rb
git commit -m "feat: graphql connection accepts host and extra headers"
```

### Task 2: `PSN::Price` model

**Files:**
- Create: `lib/psn_client/models/price.rb`
- Create: `spec/fixtures/sku_price.json`
- Modify: `lib/psn_client.rb` (add require)
- Test: `spec/psn_client/models/price_spec.rb`

- [ ] **Step 1: Create the fixture** `spec/fixtures/sku_price.json` (shape verified live; values adjusted to exercise the discount branch):

```json
{
  "__typename": "SkuPrice",
  "basePrice": "$69.99",
  "basePriceValue": 6999,
  "discountedPrice": "$48.99",
  "discountedValue": 4899,
  "discountText": "-30%",
  "currencyCode": "USD",
  "campaignId": null,
  "endTime": "2026-07-23T14:59:00Z",
  "isExclusive": false,
  "isFree": false,
  "isTiedToSubscription": false,
  "qualifications": null,
  "rewardId": "",
  "serviceBranding": ["NONE"],
  "skuId": "UP6312-PPSA31381_00-0202050640964065-U001"
}
```

- [ ] **Step 2: Write the failing test** `spec/psn_client/models/price_spec.rb`:

```ruby
# frozen_string_literal: true

RSpec.describe PSN::Price do
  it "maps the SkuPrice shape" do
    price = described_class.from_api(fixture("sku_price"))
    expect(price.base_price).to eq("$69.99")
    expect(price.discounted_price).to eq("$48.99")
    expect(price.discounted_value).to eq(4899)
    expect(price.currency_code).to eq("USD")
    expect(price.end_time).to eq(Time.iso8601("2026-07-23T14:59:00Z"))
  end

  it "answers the predicates" do
    price = described_class.from_api(fixture("sku_price"))
    expect(price).to be_discounted
    expect(price).not_to be_free
    expect(price).not_to be_tied_to_subscription
    expect(price).not_to be_exclusive
    expect(price.raw).to eq(fixture("sku_price"))
  end

  it "is not discounted when values match and tolerates missing keys" do
    price = described_class.from_api({})
    expect(price).not_to be_discounted
    expect(price.end_time).to be_nil
  end
end
```

- [ ] **Step 3: Run it to make sure it fails**

Run: `bundle exec rspec spec/psn_client/models/price_spec.rb`
Expected: FAIL with `uninitialized constant PSN::Price`.

- [ ] **Step 4: Implement** `lib/psn_client/models/price.rb`:

```ruby
# frozen_string_literal: true

module PSN
  # A Sony SkuPrice: locale-formatted display strings ("$69.99") plus the
  # numeric minor-unit values ("basePriceValue" 6999 = $69.99).
  Price = Data.define(:base_price, :base_price_value, :discounted_price,
                      :discounted_value, :discount_text, :currency_code,
                      :end_time, :free, :tied_to_subscription, :exclusive,
                      :service_branding, :sku_id, :raw) do
    def self.from_api(hash)
      new(base_price: hash["basePrice"], base_price_value: hash["basePriceValue"],
          discounted_price: hash["discountedPrice"], discounted_value: hash["discountedValue"],
          discount_text: hash["discountText"], currency_code: hash["currencyCode"],
          end_time: Mapping.time(hash["endTime"]), free: hash["isFree"] == true,
          tied_to_subscription: hash["isTiedToSubscription"] == true,
          exclusive: hash["isExclusive"] == true,
          service_branding: hash["serviceBranding"], sku_id: hash["skuId"], raw: hash)
    end

    def free? = free
    def tied_to_subscription? = tied_to_subscription
    def exclusive? = exclusive

    def discounted?
      !!(base_price_value && discounted_value && discounted_value < base_price_value)
    end
  end
end
```

Add to `lib/psn_client.rb` after the `models/mapping` require:

```ruby
require_relative "psn_client/models/price"
```

- [ ] **Step 5: Run the tests, then commit**

Run: `bundle exec rspec spec/psn_client/models/price_spec.rb` — expected PASS.

```bash
git add lib/psn_client/models/price.rb lib/psn_client.rb spec/fixtures/sku_price.json spec/psn_client/models/price_spec.rb
git commit -m "feat: add Price model for Sony SkuPrice shape"
```

### Task 3: `PSN::CatalogItem` model

**Files:**
- Create: `lib/psn_client/models/catalog_item.rb`
- Create: `spec/fixtures/catalog_product.json`, `spec/fixtures/catalog_concept.json`
- Modify: `lib/psn_client.rb` (require after price)
- Test: `spec/psn_client/models/catalog_item_spec.rb`

- [ ] **Step 1: Create fixtures**

`spec/fixtures/catalog_product.json` (trimmed live `categoryGridRetrieve` product):

```json
{
  "__typename": "Product",
  "id": "UP6312-PPSA31381_00-0202050640964065",
  "name": "Fable Standard Edition",
  "npTitleId": "PPSA31381_00",
  "platforms": ["PS5"],
  "storeDisplayClassification": "FULL_GAME",
  "localizedStoreDisplayClassification": "Full Game",
  "media": [
    { "__typename": "Media", "role": "PREVIEW", "type": "VIDEO",
      "url": "https://vulcan.dl.playstation.net/img/rnd/202606/0719/preview.mp4" },
    { "__typename": "Media", "role": "BACKGROUND", "type": "IMAGE",
      "url": "https://image.api.playstation.com/vulcan/ap/rnd/202605/2823/background.png" },
    { "__typename": "Media", "role": "GAMEHUB_COVER_ART", "type": "IMAGE",
      "url": "https://image.api.playstation.com/vulcan/ap/rnd/202605/2823/cover.png" }
  ],
  "price": {
    "__typename": "SkuPrice",
    "basePrice": "$69.99", "basePriceValue": 6999,
    "discountedPrice": "$69.99", "discountedValue": 6999,
    "discountText": null, "currencyCode": "USD", "campaignId": null, "endTime": null,
    "isExclusive": false, "isFree": false, "isTiedToSubscription": false,
    "qualifications": null, "rewardId": "", "serviceBranding": ["NONE"],
    "skuId": "UP6312-PPSA31381_00-0202050640964065-U001"
  }
}
```

`spec/fixtures/catalog_concept.json` (unreleased-concept variant — exercises the nil branches):

```json
{
  "__typename": "Concept",
  "id": "10015869",
  "name": "Fable",
  "platforms": [],
  "storeDisplayClassification": null,
  "localizedStoreDisplayClassification": null,
  "media": [],
  "price": null
}
```

- [ ] **Step 2: Write the failing test** `spec/psn_client/models/catalog_item_spec.rb`:

```ruby
# frozen_string_literal: true

RSpec.describe PSN::CatalogItem do
  it "maps a released Product card" do
    item = described_class.from_api(fixture("catalog_product"))
    expect(item.name).to eq("Fable Standard Edition")
    expect(item.np_title_id).to eq("PPSA31381_00")
    expect(item.platforms).to eq(["PS5"])
    expect(item).not_to be_concept
    expect(item.classification).to eq("FULL_GAME")
  end

  it "prefers cover art for image_url and maps the price" do
    item = described_class.from_api(fixture("catalog_product"))
    expect(item.image_url).to eq("https://image.api.playstation.com/vulcan/ap/rnd/202605/2823/cover.png")
    expect(item.price).to be_a(PSN::Price)
    expect(item.price.base_price).to eq("$69.99")
    expect(item.raw).to eq(fixture("catalog_product"))
  end

  it "maps an unreleased Concept card with no price" do
    item = described_class.from_api(fixture("catalog_concept"))
    expect(item).to be_concept
    expect(item.price).to be_nil
    expect(item.image_url).to be_nil
    expect(item.platforms).to eq([])
  end

  it "falls back to the first image when there is no cover art" do
    media = [{ "role" => "SCREENSHOT", "type" => "IMAGE", "url" => "https://img/s.png" }]
    item = described_class.from_api(fixture("catalog_concept").merge("media" => media))
    expect(item.image_url).to eq("https://img/s.png")
  end
end
```

- [ ] **Step 3: Run it to make sure it fails**

Run: `bundle exec rspec spec/psn_client/models/catalog_item_spec.rb`
Expected: FAIL with `uninitialized constant PSN::CatalogItem`.

- [ ] **Step 4: Implement** `lib/psn_client/models/catalog_item.rb`:

```ruby
# frozen_string_literal: true

module PSN
  # A store catalog card: either a released Product or an unreleased Concept
  # (concept? true, price nil). Returned by search results, category grids
  # and add-on lists, which all share this Product/Concept shape.
  CatalogItem = Data.define(:name, :id, :np_title_id, :concept, :platforms,
                            :classification, :localized_classification,
                            :image_url, :price, :raw) do
    def self.from_api(hash)
      price = hash["price"]
      new(name: hash["name"], id: hash["id"], np_title_id: hash["npTitleId"],
          concept: hash["__typename"] == "Concept", platforms: hash["platforms"] || [],
          classification: hash["storeDisplayClassification"],
          localized_classification: hash["localizedStoreDisplayClassification"],
          image_url: cover_url(hash["media"] || []),
          price: price && Price.from_api(price), raw: hash)
    end

    # The store's box-art equivalent; falls back to any image.
    def self.cover_url(media)
      images = media.select { |m| m["type"] == "IMAGE" }
      cover = images.find { |m| m["role"] == "GAMEHUB_COVER_ART" } || images.first
      cover && cover["url"]
    end

    def concept? = concept
  end
end
```

Add to `lib/psn_client.rb` after the price require:

```ruby
require_relative "psn_client/models/catalog_item"
```

- [ ] **Step 5: Run the tests, then commit**

Run: `bundle exec rspec spec/psn_client/models/catalog_item_spec.rb` — expected PASS.

```bash
git add lib/psn_client/models/catalog_item.rb lib/psn_client.rb spec/fixtures/catalog_product.json spec/fixtures/catalog_concept.json spec/psn_client/models/catalog_item_spec.rb
git commit -m "feat: add CatalogItem model for store Product/Concept cards"
```

### Task 4: `PSN::UserSearchResult` model

**Files:**
- Create: `lib/psn_client/models/user_search_result.rb`
- Create: `spec/fixtures/user_search_player.json`
- Modify: `lib/psn_client.rb`
- Test: `spec/psn_client/models/user_search_result_spec.rb`

- [ ] **Step 1: Create the fixture** `spec/fixtures/user_search_player.json` (Player shape from psnawp's typed response):

```json
{
  "__typename": "Player",
  "accountId": "1234567890123456789",
  "avatarUrl": "https://static-resource.np.community.playstation.net/avatar_m/WWS_A/A0031_m.png",
  "displayName": "Matty",
  "displayNameHighlighted": ["Matty"],
  "firstName": "Matt",
  "id": "search-player-1",
  "isPsPlus": true,
  "itemType": "SOCIAL",
  "lastName": "J",
  "middleName": null,
  "onlineId": "matty_plays",
  "onlineIdHighlighted": ["matty_plays"],
  "profilePicUrl": "https://image.api.playstation.com/profile/pic.png",
  "relationshipState": null
}
```

- [ ] **Step 2: Write the failing test** `spec/psn_client/models/user_search_result_spec.rb`:

```ruby
# frozen_string_literal: true

RSpec.describe PSN::UserSearchResult do
  it "maps the Player shape" do
    user = described_class.from_api(fixture("user_search_player"))
    expect(user.online_id).to eq("matty_plays")
    expect(user.account_id).to eq("1234567890123456789")
    expect(user.display_name).to eq("Matty")
    expect(user.avatar_url).to eq("https://static-resource.np.community.playstation.net/avatar_m/WWS_A/A0031_m.png")
    expect(user).to be_ps_plus
  end

  it "keeps the raw payload and tolerates missing keys" do
    expect(described_class.from_api(fixture("user_search_player")).raw).to eq(fixture("user_search_player"))
    expect(described_class.from_api({})).not_to be_ps_plus
  end
end
```

- [ ] **Step 3: Run it to make sure it fails** — `bundle exec rspec spec/psn_client/models/user_search_result_spec.rb`, expected `uninitialized constant`.

- [ ] **Step 4: Implement** `lib/psn_client/models/user_search_result.rb`:

```ruby
# frozen_string_literal: true

module PSN
  # One player from a user search. account_id is the Sony numeric ID usable
  # with games/trophies lookups; relationship_state is nil for strangers.
  UserSearchResult = Data.define(:online_id, :account_id, :display_name,
                                 :avatar_url, :ps_plus, :relationship_state, :raw) do
    def self.from_api(hash)
      new(online_id: hash["onlineId"], account_id: hash["accountId"],
          display_name: hash["displayName"], avatar_url: hash["avatarUrl"],
          ps_plus: hash["isPsPlus"] == true,
          relationship_state: hash["relationshipState"], raw: hash)
    end

    def ps_plus? = ps_plus
  end
end
```

Add to `lib/psn_client.rb` after catalog_item:

```ruby
require_relative "psn_client/models/user_search_result"
```

- [ ] **Step 5: Run the tests, then commit**

```bash
bundle exec rspec spec/psn_client/models/user_search_result_spec.rb
git add lib/psn_client/models/user_search_result.rb lib/psn_client.rb spec/fixtures/user_search_player.json spec/psn_client/models/user_search_result_spec.rb
git commit -m "feat: add UserSearchResult model"
```

### Task 5: `Resources::Search` + client wiring

**Files:**
- Create: `lib/psn_client/resources/search.rb`
- Modify: `lib/psn_client.rb` (require before client), `lib/psn_client/client.rb`
- Test: `spec/psn_client/resources/search_spec.rb`, `spec/psn_client/client_spec.rb`

- [ ] **Step 1: Write the failing test** `spec/psn_client/resources/search_spec.rb`:

```ruby
# frozen_string_literal: true

RSpec.describe PSN::Resources::Search do
  subject(:search) { described_class.new(connection) }

  let(:connection) { instance_double(PSN::Connection) }
  let(:game_item) { { "id" => "hit-1", "result" => fixture("catalog_product") } }
  let(:games_context_response) do
    { "data" => { "universalContextSearch" => { "results" => [
      { "domain" => "MobileGames", "searchResults" => [game_item], "next" => "cur1" },
      { "domain" => "MobileAddOns", "searchResults" => [], "next" => "" }
    ] } } }
  end
  let(:games_domain_response) do
    { "data" => { "universalDomainSearch" =>
      { "searchResults" => [game_item.merge("id" => "hit-2")], "next" => "" } } }
  end

  describe "#games" do
    before do
      allow(connection).to receive(:graphql)
        .with("metGetContextSearchResults",
              { "searchTerm" => "fable", "searchContext" => "MobileUniversalSearchGame",
                "displayTitleLocale" => "en-US" },
              described_class::GAMES_CONTEXT_HASH, headers: described_class::HEADERS)
        .and_return(games_context_response)
      allow(connection).to receive(:graphql)
        .with("metGetDomainSearchResults",
              { "searchTerm" => "fable", "searchDomain" => "MobileGames",
                "pageSize" => 20, "pageOffset" => 1, "nextCursor" => "cur1" },
              described_class::GAMES_DOMAIN_HASH, headers: described_class::HEADERS)
        .and_return(games_domain_response)
    end

    it "yields the context page then walks domain pages" do
      results = search.games("fable").to_a
      expect(results.size).to eq(2)
      expect(results.first).to be_a(PSN::CatalogItem)
      expect(results.first.name).to eq("Fable Standard Edition")
    end

    it "is lazy: .first(1) only issues the context request" do
      expect(search.games("fable").first(1).size).to eq(1)
      expect(connection).to have_received(:graphql).once
    end

    it "rejects unknown domains" do
      expect { search.games("fable", domain: :nope) }.to raise_error(KeyError)
    end
  end

  describe "#users" do
    let(:users_context_response) do
      { "data" => { "universalContextSearch" => { "results" => [
        { "domain" => "SocialAllAccounts",
          "searchResults" => [{ "id" => "u1", "result" => fixture("user_search_player") }],
          "next" => "" }
      ] } } }
    end

    it "maps players from the social context search" do
      allow(connection).to receive(:graphql)
        .with("metGetContextSearchResults",
              { "searchTerm" => "matty", "searchContext" => "MobileUniversalSearchSocial",
                "displayTitleLocale" => "en-US" },
              described_class::USERS_CONTEXT_HASH, headers: described_class::HEADERS)
        .and_return(users_context_response)

      results = search.users("matty").to_a
      expect(results.size).to eq(1)
      expect(results.first).to be_a(PSN::UserSearchResult)
      expect(results.first.online_id).to eq("matty_plays")
    end
  end
end
```

Note the users example ends after one page because `next` is `""` — `Paginator.cursor` stops on empty cursors, so no domain stub is needed.

- [ ] **Step 2: Run it to make sure it fails** — `bundle exec rspec spec/psn_client/resources/search_spec.rb`, expected `uninitialized constant PSN::Resources::Search`.

- [ ] **Step 3: Implement** `lib/psn_client/resources/search.rb`:

```ruby
# frozen_string_literal: true

module PSN
  module Resources
    # Game and player search via the PlayStation App's persisted GraphQL
    # queries. Sony does not document these; operation names, hashes and
    # response keys are confined to this file (verify with bin/smoke).
    # The first page comes from the "context" (universal) search and
    # follow-up pages from the "domain" search — separate persisted
    # documents, each with its own hash per context.
    class Search
      CONTEXT_OPERATION = "metGetContextSearchResults"
      DOMAIN_OPERATION = "metGetDomainSearchResults"
      GAMES_CONTEXT = "MobileUniversalSearchGame"
      GAMES_CONTEXT_HASH = "a2fbc15433b37ca7bfcd7112f741735e13268f5e9ebd5ffce51b85acc126f41d"
      GAMES_DOMAIN_HASH = "b51624299bd17b3799f77c9f097cc8887a04d3873f0329095976a841595bc902"
      USERS_CONTEXT = "MobileUniversalSearchSocial"
      USERS_CONTEXT_HASH = "ac5fb2b82c4d086ca0d272fba34418ab327a7762dd2cd620e63f175bbc5aff10"
      USERS_DOMAIN_HASH = "23ece284bf8bdc50bfa30a4d97fd4d733e723beb7a42dff8c1ee883f8461a2e1"
      GAME_DOMAINS = { full_games: "MobileGames", add_ons: "MobileAddOns" }.freeze
      USERS_DOMAIN = "SocialAllAccounts"
      LOCALE = "en-US"
      PAGE_SIZE = 20
      # The PlayStation App identifies itself on search requests.
      HEADERS = { "apollographql-client-name" => "PlayStationApp-Android" }.freeze

      def initialize(connection)
        @connection = connection
      end

      # Store search. domain: :full_games or :add_ons.
      def games(term, domain: :full_games)
        items = result_items(term, domain: GAME_DOMAINS.fetch(domain), context: GAMES_CONTEXT,
                             context_hash: GAMES_CONTEXT_HASH, domain_hash: GAMES_DOMAIN_HASH)
        items.map { |item| CatalogItem.from_api(item["result"] || {}) }
      end

      # Player search by online ID or display name.
      def users(term)
        items = result_items(term, domain: USERS_DOMAIN, context: USERS_CONTEXT,
                             context_hash: USERS_CONTEXT_HASH, domain_hash: USERS_DOMAIN_HASH,
                             domain_extras: { "displayTitleLocale" => LOCALE })
        items.map { |item| UserSearchResult.from_api(item["result"] || {}) }
      end

      private

      # The games domain query rejects displayTitleLocale while the users one
      # requires it (mirrors the app's persisted documents) — hence
      # domain_extras rather than always sending it.
      def result_items(term, domain:, context:, context_hash:, domain_hash:, domain_extras: {})
        offset = 0
        Paginator.cursor do |cursor|
          items, next_cursor = if cursor.nil?
                                 context_page(term, context, domain, context_hash)
                               else
                                 domain_page(term, domain, domain_hash, cursor, offset, domain_extras)
                               end
          offset += items.size
          [items, next_cursor]
        end
      end

      def context_page(term, context, domain, hash)
        variables = { "searchTerm" => term, "searchContext" => context,
                      "displayTitleLocale" => LOCALE }
        response = @connection.graphql(CONTEXT_OPERATION, variables, hash, headers: HEADERS)
        results = response.dig("data", "universalContextSearch", "results") || []
        page = results.find { |r| r["domain"] == domain } || {}
        [page["searchResults"] || [], page["next"]]
      end

      def domain_page(term, domain, hash, cursor, offset, extras) # rubocop:disable Metrics/ParameterLists
        variables = { "searchTerm" => term, "searchDomain" => domain,
                      "pageSize" => PAGE_SIZE, "pageOffset" => offset,
                      "nextCursor" => cursor }.merge(extras)
        response = @connection.graphql(DOMAIN_OPERATION, variables, hash, headers: HEADERS)
        page = response.dig("data", "universalDomainSearch") || {}
        [page["searchResults"] || [], page["next"]]
      end
    end
  end
end
```

Add to `lib/psn_client.rb` after `resources/profiles`:

```ruby
require_relative "psn_client/resources/search"
```

Add to `lib/psn_client/client.rb` after the `profiles` line:

```ruby
    def search = @search ||= Resources::Search.new(@connection)
```

- [ ] **Step 4: Extend the client spec** — in `spec/psn_client/client_spec.rb`, inside `it "exposes memoized resource objects"`, add before the final `equal` expectation:

```ruby
    expect(client.search).to be_a(PSN::Resources::Search)
```

(The example already has 5 expectations; replace `expect(client.games).to equal(client.games)` with `expect(client.search).to equal(client.search)` if RuboCop `RSpec/MultipleExpectations` complains — max is 5.)

- [ ] **Step 5: Run the tests, then commit**

Run: `bundle exec rspec spec/psn_client/resources/search_spec.rb spec/psn_client/client_spec.rb` — expected PASS.

```bash
git add lib/psn_client/resources/search.rb lib/psn_client/client.rb lib/psn_client.rb spec/psn_client/resources/search_spec.rb spec/psn_client/client_spec.rb
git commit -m "feat: add Search resource for game and player search"
```

### Task 6: `PSN::StarRating` model

**Files:**
- Create: `lib/psn_client/models/star_rating.rb`
- Create: `spec/fixtures/star_rating.json`
- Modify: `lib/psn_client.rb`
- Test: `spec/psn_client/models/star_rating_spec.rb`

- [ ] **Step 1: Create the fixture** `spec/fixtures/star_rating.json` (shape verified live via `wcaProductStarRatingRetrive`):

```json
{
  "__typename": "StarRating",
  "averageRating": 4.6,
  "averageRatingForDisplay": "4.60",
  "totalRatingsCount": 15382,
  "ratingsDistribution": [
    { "__typename": "StarRatingCount", "rating": 5, "percentage": "78%", "percentageRaw": 78.1 },
    { "__typename": "StarRatingCount", "rating": 4, "percentage": "12%", "percentageRaw": 12.0 },
    { "__typename": "StarRatingCount", "rating": 3, "percentage": "5%", "percentageRaw": 5.0 },
    { "__typename": "StarRatingCount", "rating": 2, "percentage": "2%", "percentageRaw": 2.0 },
    { "__typename": "StarRatingCount", "rating": 1, "percentage": "3%", "percentageRaw": 2.9 }
  ]
}
```

- [ ] **Step 2: Write the failing test** `spec/psn_client/models/star_rating_spec.rb`:

```ruby
# frozen_string_literal: true

RSpec.describe PSN::StarRating do
  it "maps average, total and the distribution by star count" do
    rating = described_class.from_api(fixture("star_rating"))
    expect(rating.average).to eq(4.6)
    expect(rating.average_display).to eq("4.60")
    expect(rating.total).to eq(15_382)
    expect(rating.distribution).to eq({ 5 => 78.1, 4 => 12.0, 3 => 5.0, 2 => 2.0, 1 => 2.9 })
    expect(rating.raw).to eq(fixture("star_rating"))
  end

  it "tolerates an empty payload" do
    rating = described_class.from_api({})
    expect(rating.distribution).to eq({})
  end
end
```

- [ ] **Step 3: Run it to make sure it fails** — expected `uninitialized constant PSN::StarRating`.

- [ ] **Step 4: Implement** `lib/psn_client/models/star_rating.rb`:

```ruby
# frozen_string_literal: true

module PSN
  # Store user ratings for a product. distribution maps star count (5..1)
  # to the percentage of ratings with that score.
  StarRating = Data.define(:average, :average_display, :total, :distribution, :raw) do
    def self.from_api(hash)
      distribution = (hash["ratingsDistribution"] || []).to_h do |entry|
        [entry["rating"], entry["percentageRaw"]]
      end
      new(average: hash["averageRating"], average_display: hash["averageRatingForDisplay"],
          total: hash["totalRatingsCount"], distribution: distribution, raw: hash)
    end
  end
end
```

Add to `lib/psn_client.rb` after user_search_result:

```ruby
require_relative "psn_client/models/star_rating"
```

- [ ] **Step 5: Run the tests, then commit**

```bash
bundle exec rspec spec/psn_client/models/star_rating_spec.rb
git add lib/psn_client/models/star_rating.rb lib/psn_client.rb spec/fixtures/star_rating.json spec/psn_client/models/star_rating_spec.rb
git commit -m "feat: add StarRating model"
```

### Task 7: `StoreProduct` and `StoreConcept` models

**Files:**
- Create: `lib/psn_client/models/store_product.rb`, `lib/psn_client/models/store_concept.rb`
- Create: `spec/fixtures/store_product.json`, `spec/fixtures/store_concept.json`
- Modify: `lib/psn_client.rb`
- Test: `spec/psn_client/models/store_product_spec.rb`, `spec/psn_client/models/store_concept_spec.rb`

- [ ] **Step 1: Create fixtures**

`spec/fixtures/store_product.json` (trimmed live `productRetrieve` — note `releaseDate` is a plain string here):

```json
{
  "__typename": "Product",
  "id": "UP6312-PPSA31381_00-0202050640964065",
  "invariantName": "Fable Standard Edition",
  "name": "Fable Standard Edition",
  "npTitleId": "PPSA31381_00",
  "platforms": ["PS5"],
  "publisherName": "Microsoft Corporation",
  "releaseDate": "2027-02-23T16:00:00Z",
  "storeDisplayClassification": "FULL_GAME",
  "localizedStoreDisplayClassification": "Full Game",
  "topCategory": "GAME",
  "concept": { "__typename": "Concept", "id": "10015869" },
  "combinedLocalizedGenres": [
    { "__typename": "LocalizedGenreSubGenre", "value": "Adventure" },
    { "__typename": "LocalizedGenreSubGenre", "value": "Fantasy" }
  ],
  "descriptions": [
    { "__typename": "Description", "type": "SHORT", "value": "A hero returns." },
    { "__typename": "Description", "type": "LONG", "value": "Fable is an action RPG set in Albion." }
  ],
  "edition": { "__typename": "ProductEdition", "name": "Fable Standard Edition", "features": ["Fable Base Game"] },
  "contentRating": { "__typename": "ProductContentRating", "authority": "ESRB", "description": "ESRB Mature 17+" },
  "media": [
    { "__typename": "Media", "role": "GAMEHUB_COVER_ART", "type": "IMAGE",
      "url": "https://image.api.playstation.com/vulcan/cover.png" }
  ]
}
```

`spec/fixtures/store_concept.json` (trimmed live `conceptRetrieve` — `releaseDate` is an object here):

```json
{
  "__typename": "Concept",
  "id": "10015869",
  "invariantName": "Fable",
  "name": "Fable",
  "publisherName": "Microsoft Corporation",
  "releaseDate": { "__typename": "ReleaseDate", "type": "DAY_MONTH_YEAR", "value": "2027-02-23T16:00:00Z" },
  "combinedLocalizedGenres": [{ "__typename": "LocalizedGenreSubGenre", "value": "Adventure" }],
  "descriptions": [{ "__typename": "Description", "type": "LONG", "value": "Fable is an action RPG set in Albion." }],
  "media": [
    { "__typename": "Media", "role": "GAMEHUB_COVER_ART", "type": "IMAGE",
      "url": "https://image.api.playstation.com/vulcan/concept.png" }
  ],
  "defaultProduct": {
    "__typename": "Product",
    "id": "UP6312-PPSA31381_00-0202050640964065",
    "name": "Fable Standard Edition",
    "npTitleId": "PPSA31381_00",
    "platforms": ["PS5"],
    "storeDisplayClassification": "FULL_GAME",
    "localizedStoreDisplayClassification": "Full Game",
    "media": [],
    "price": null
  }
}
```

- [ ] **Step 2: Write the failing tests**

`spec/psn_client/models/store_product_spec.rb`:

```ruby
# frozen_string_literal: true

RSpec.describe PSN::StoreProduct do
  it "maps the product detail shape" do
    product = described_class.from_api(fixture("store_product"))
    expect(product.name).to eq("Fable Standard Edition")
    expect(product.np_title_id).to eq("PPSA31381_00")
    expect(product.publisher).to eq("Microsoft Corporation")
    expect(product.release_date).to eq(Time.iso8601("2027-02-23T16:00:00Z"))
    expect(product.concept_id).to eq("10015869")
  end

  it "maps genres, descriptions, edition, rating and image" do
    product = described_class.from_api(fixture("store_product"))
    expect(product.genres).to eq(%w[Adventure Fantasy])
    expect(product.short_description).to eq("A hero returns.")
    expect(product.description).to eq("Fable is an action RPG set in Albion.")
    expect(product.edition).to eq("Fable Standard Edition")
    expect(product.content_rating).to eq("ESRB Mature 17+")
  end

  it "keeps raw and tolerates an empty payload" do
    expect(described_class.from_api(fixture("store_product")).raw).to eq(fixture("store_product"))
    empty = described_class.from_api({})
    expect(empty.release_date).to be_nil
    expect(empty.genres).to eq([])
    expect(empty.description).to be_nil
  end
end
```

`spec/psn_client/models/store_concept_spec.rb`:

```ruby
# frozen_string_literal: true

RSpec.describe PSN::StoreConcept do
  it "maps the concept detail shape including the object-wrapped release date" do
    concept = described_class.from_api(fixture("store_concept"))
    expect(concept.name).to eq("Fable")
    expect(concept.publisher).to eq("Microsoft Corporation")
    expect(concept.release_date).to eq(Time.iso8601("2027-02-23T16:00:00Z"))
    expect(concept.genres).to eq(["Adventure"])
    expect(concept.description).to eq("Fable is an action RPG set in Albion.")
  end

  it "maps the default product as a CatalogItem" do
    concept = described_class.from_api(fixture("store_concept"))
    expect(concept.default_product).to be_a(PSN::CatalogItem)
    expect(concept.default_product.name).to eq("Fable Standard Edition")
    expect(concept.image_url).to eq("https://image.api.playstation.com/vulcan/concept.png")
    expect(concept.raw).to eq(fixture("store_concept"))
  end

  it "tolerates an empty payload" do
    empty = described_class.from_api({})
    expect(empty.default_product).to be_nil
    expect(empty.release_date).to be_nil
  end
end
```

- [ ] **Step 3: Run them to make sure they fail** — `bundle exec rspec spec/psn_client/models/store_product_spec.rb spec/psn_client/models/store_concept_spec.rb`, expected `uninitialized constant`.

- [ ] **Step 4: Implement**

`lib/psn_client/models/store_product.rb`:

```ruby
# frozen_string_literal: true

module PSN
  # Full store product detail (metGetProductById). Unlike CatalogItem this
  # carries no price — use Catalog#pricing with concept_id for that.
  StoreProduct = Data.define(:name, :id, :np_title_id, :invariant_name, :concept_id,
                             :platforms, :publisher, :release_date, :genres,
                             :classification, :localized_classification, :edition,
                             :short_description, :description, :content_rating,
                             :image_url, :raw) do
    def self.from_api(hash)
      new(name: hash["name"], id: hash["id"], np_title_id: hash["npTitleId"],
          invariant_name: hash["invariantName"], concept_id: hash.dig("concept", "id"),
          platforms: hash["platforms"] || [], publisher: hash["publisherName"],
          release_date: Mapping.time(hash["releaseDate"]),
          genres: (hash["combinedLocalizedGenres"] || []).map { |g| g["value"] },
          classification: hash["storeDisplayClassification"],
          localized_classification: hash["localizedStoreDisplayClassification"],
          edition: hash.dig("edition", "name"),
          short_description: description_of(hash, "SHORT"),
          description: description_of(hash, "LONG"),
          content_rating: hash.dig("contentRating", "description"),
          image_url: CatalogItem.cover_url(hash["media"] || []), raw: hash)
    end

    def self.description_of(hash, type)
      entry = (hash["descriptions"] || []).find { |d| d["type"] == type }
      entry && entry["value"]
    end
  end
end
```

`lib/psn_client/models/store_concept.rb`:

```ruby
# frozen_string_literal: true

module PSN
  # Full store concept detail (metGetConceptById): the franchise-level entry
  # a product belongs to; exists even before release. Note releaseDate is an
  # object here ({"type", "value"}), unlike StoreProduct's plain string.
  StoreConcept = Data.define(:name, :id, :invariant_name, :publisher, :release_date,
                             :genres, :description, :image_url, :default_product, :raw) do
    def self.from_api(hash)
      default_product = hash["defaultProduct"]
      new(name: hash["name"], id: hash["id"], invariant_name: hash["invariantName"],
          publisher: hash["publisherName"],
          release_date: Mapping.time(hash.dig("releaseDate", "value")),
          genres: (hash["combinedLocalizedGenres"] || []).map { |g| g["value"] },
          description: StoreProduct.description_of(hash, "LONG"),
          image_url: CatalogItem.cover_url(hash["media"] || []),
          default_product: default_product && CatalogItem.from_api(default_product), raw: hash)
    end
  end
end
```

Add to `lib/psn_client.rb` after star_rating (order matters — store_concept calls StoreProduct):

```ruby
require_relative "psn_client/models/store_product"
require_relative "psn_client/models/store_concept"
```

- [ ] **Step 5: Run the tests, then commit**

```bash
bundle exec rspec spec/psn_client/models
git add lib/psn_client/models/store_product.rb lib/psn_client/models/store_concept.rb lib/psn_client.rb spec/fixtures/store_product.json spec/fixtures/store_concept.json spec/psn_client/models/store_product_spec.rb spec/psn_client/models/store_concept_spec.rb
git commit -m "feat: add StoreProduct and StoreConcept detail models"
```

### Task 8: `Resources::Catalog` — lookups and ratings

**Files:**
- Create: `lib/psn_client/resources/catalog.rb`
- Modify: `lib/psn_client.rb`, `lib/psn_client/client.rb`
- Test: `spec/psn_client/resources/catalog_spec.rb`

- [ ] **Step 1: Write the failing test** `spec/psn_client/resources/catalog_spec.rb`:

```ruby
# frozen_string_literal: true

RSpec.describe PSN::Resources::Catalog do
  subject(:catalog) { described_class.new(connection) }

  let(:connection) { instance_double(PSN::Connection) }
  let(:product_id) { "UP6312-PPSA31381_00-0202050640964065" }

  describe "#product" do
    it "fetches product detail via metGetProductById" do
      allow(connection).to receive(:graphql)
        .with("metGetProductById", { "productId" => product_id },
              described_class::PRODUCT_HASH, host: :web)
        .and_return({ "data" => { "productRetrieve" => fixture("store_product") } })

      product = catalog.product(product_id)
      expect(product).to be_a(PSN::StoreProduct)
      expect(product.name).to eq("Fable Standard Edition")
    end
  end

  describe "#concept" do
    it "fetches concept detail via metGetConceptById (conceptId + empty productId)" do
      allow(connection).to receive(:graphql)
        .with("metGetConceptById", { "conceptId" => "10015869", "productId" => "" },
              described_class::CONCEPT_HASH, host: :web)
        .and_return({ "data" => { "conceptRetrieve" => fixture("store_concept") } })

      expect(catalog.concept(10_015_869).name).to eq("Fable")
    end
  end

  describe "#pricing" do
    it "returns the default product's Price" do
      response = { "data" => { "conceptRetrieve" => { "defaultProduct" => { "price" => fixture("sku_price") } } } }
      allow(connection).to receive(:graphql)
        .with("metGetPricingDataByConceptId", { "conceptId" => "10015869" },
              described_class::PRICING_HASH, host: :web)
        .and_return(response)

      price = catalog.pricing("10015869")
      expect(price).to be_a(PSN::Price)
      expect(price.discounted_price).to eq("$48.99")
    end

    it "returns nil when the concept has no purchasable product" do
      allow(connection).to receive(:graphql).and_return({ "data" => { "conceptRetrieve" => {} } })
      expect(catalog.pricing("10015869")).to be_nil
    end
  end

  describe "#product_rating" do
    it "returns the StarRating via wcaProductStarRatingRetrive" do
      allow(connection).to receive(:graphql)
        .with("wcaProductStarRatingRetrive", { "productId" => product_id },
              described_class::PRODUCT_RATING_HASH, host: :web)
        .and_return({ "data" => { "productRetrieve" => { "starRating" => fixture("star_rating") } } })

      expect(catalog.product_rating(product_id).average).to eq(4.6)
    end
  end

  describe "#concept_rating" do
    it "returns the default product's StarRating" do
      response = { "data" => { "conceptRetrieve" => { "defaultProduct" => { "starRating" => fixture("star_rating") } } } }
      allow(connection).to receive(:graphql)
        .with("wcaConceptStarRatingRetrive", { "conceptId" => "10015869" },
              described_class::CONCEPT_RATING_HASH, host: :web)
        .and_return(response)

      expect(catalog.concept_rating("10015869").total).to eq(15_382)
    end
  end
end
```

- [ ] **Step 2: Run it to make sure it fails** — expected `uninitialized constant PSN::Resources::Catalog`.

- [ ] **Step 3: Implement** `lib/psn_client/resources/catalog.rb`:

```ruby
# frozen_string_literal: true

module PSN
  module Resources
    # Public store catalog: product/concept detail, pricing, add-ons,
    # category browsing and star ratings. These persisted queries live on
    # the web store's GraphQL host (:web) and need no account context —
    # Sony serves them anonymously. Undocumented; operation names, hashes
    # and response root keys are confined to this file and were verified
    # live 2026-07 (see bin/smoke).
    class Catalog
      HOST = :web
      PRODUCT_OPERATION = "metGetProductById"
      PRODUCT_HASH = "a128042177bd93dd831164103d53b73ef790d56f51dae647064cb8f9d9fc9d1a"
      CONCEPT_OPERATION = "metGetConceptById"
      CONCEPT_HASH = "cc90404ac049d935afbd9968aef523da2b6723abfb9d586e5f77ebf7c5289006"
      PRICING_OPERATION = "metGetPricingDataByConceptId"
      PRICING_HASH = "abcb311ea830e679fe2b697a27f755764535d825b24510ab1239a4ca3092bd09"
      # "Retrive" is Sony's typo, not ours.
      PRODUCT_RATING_OPERATION = "wcaProductStarRatingRetrive"
      PRODUCT_RATING_HASH = "cedd370c39e89da20efa7b2e55710e88cb6e6843cc2f8203f7e73ba4751e7253"
      CONCEPT_RATING_OPERATION = "wcaConceptStarRatingRetrive"
      CONCEPT_RATING_HASH = "e12dc5cef72296a437b4d71e0b130010bf3707ab981b585ba00d1d5773ce2092"

      def initialize(connection)
        @connection = connection
      end

      # Full detail for a released product ("UP6312-PPSA31381_00-...").
      def product(product_id)
        response = graphql(PRODUCT_OPERATION, { "productId" => product_id }, PRODUCT_HASH)
        StoreProduct.from_api(response.dig("data", "productRetrieve") || {})
      end

      # Full detail for a concept (numeric ID; see StoreProduct#concept_id).
      # The persisted query requires productId to be present but empty.
      def concept(concept_id)
        variables = { "conceptId" => concept_id.to_s, "productId" => "" }
        response = graphql(CONCEPT_OPERATION, variables, CONCEPT_HASH)
        StoreConcept.from_api(response.dig("data", "conceptRetrieve") || {})
      end

      # Current price for a concept's default product, or nil when nothing
      # is purchasable yet.
      def pricing(concept_id)
        response = graphql(PRICING_OPERATION, { "conceptId" => concept_id.to_s }, PRICING_HASH)
        price = response.dig("data", "conceptRetrieve", "defaultProduct", "price")
        price && Price.from_api(price)
      end

      # Star ratings, or nil when the item has none.
      def product_rating(product_id)
        response = graphql(PRODUCT_RATING_OPERATION, { "productId" => product_id }, PRODUCT_RATING_HASH)
        rating = response.dig("data", "productRetrieve", "starRating")
        rating && StarRating.from_api(rating)
      end

      def concept_rating(concept_id)
        response = graphql(CONCEPT_RATING_OPERATION, { "conceptId" => concept_id.to_s }, CONCEPT_RATING_HASH)
        rating = response.dig("data", "conceptRetrieve", "defaultProduct", "starRating")
        rating && StarRating.from_api(rating)
      end

      private

      def graphql(operation, variables, hash)
        @connection.graphql(operation, variables, hash, host: HOST)
      end
    end
  end
end
```

Add to `lib/psn_client.rb` after `resources/search`:

```ruby
require_relative "psn_client/resources/catalog"
```

Add to `lib/psn_client/client.rb` after the `search` line:

```ruby
    def catalog = @catalog ||= Resources::Catalog.new(@connection)
```

And in `spec/psn_client/client_spec.rb` add alongside the other resource expectations:

```ruby
    expect(client.catalog).to be_a(PSN::Resources::Catalog)
```

(Keep the example at ≤5 expectations — fold `search`/`catalog`/`memoization` checks into a second example if needed, e.g. `it "exposes search and catalog resources"`.)

- [ ] **Step 4: Run the tests, then commit**

Run: `bundle exec rspec spec/psn_client/resources/catalog_spec.rb spec/psn_client/client_spec.rb` — expected PASS.

```bash
git add lib/psn_client/resources/catalog.rb lib/psn_client/client.rb lib/psn_client.rb spec/psn_client/resources/catalog_spec.rb spec/psn_client/client_spec.rb
git commit -m "feat: add Catalog resource - product, concept, pricing, ratings"
```

### Task 9: `Catalog#add_ons` and `Catalog#category`

**Files:**
- Modify: `lib/psn_client/resources/catalog.rb`
- Test: `spec/psn_client/resources/catalog_spec.rb`

- [ ] **Step 1: Write the failing tests** — add to `spec/psn_client/resources/catalog_spec.rb`:

```ruby
  describe "#add_ons" do
    it "walks offset pages of add-on products" do
      page = { "addOnProducts" => [fixture("catalog_product")], "pageInfo" => { "totalCount" => 1 } }
      allow(connection).to receive(:graphql)
        .with("metGetAddOnsByTitleId",
              { "npTitleId" => "PPSA31381_00", "pageArgs" => { "size" => 50, "offset" => 0 } },
              described_class::ADD_ONS_HASH, host: :web)
        .and_return({ "data" => { "addOnProductsByTitleIdRetrieve" => page } })

      result = catalog.add_ons("PPSA31381_00").to_a
      expect(result.size).to eq(1)
      expect(result.first).to be_a(PSN::CatalogItem)
    end
  end

  describe "#category" do
    let(:grid_variables) do
      { "id" => described_class::CATEGORIES[:ps5_games],
        "pageArgs" => { "size" => 50, "offset" => 0 },
        "sortBy" => { "name" => "productReleaseDate", "isAscending" => false },
        "filterBy" => [], "facetOptions" => [] }
    end

    it "accepts a category symbol and maps grid products" do
      grid = { "products" => [fixture("catalog_product")], "pageInfo" => { "totalCount" => 1 } }
      allow(connection).to receive(:graphql)
        .with("categoryGridRetrieve", grid_variables, described_class::CATEGORY_HASH, host: :web)
        .and_return({ "data" => { "categoryGridRetrieve" => grid } })

      result = catalog.category(:ps5_games).to_a
      expect(result.size).to eq(1)
      expect(result.first.name).to eq("Fable Standard Edition")
    end

    it "passes raw category UUIDs through and rejects unknown symbols" do
      allow(connection).to receive(:graphql)
        .with("categoryGridRetrieve", hash_including("id" => "some-uuid"),
              described_class::CATEGORY_HASH, host: :web)
        .and_return({ "data" => { "categoryGridRetrieve" => { "products" => [], "pageInfo" => { "totalCount" => 0 } } } })

      expect(catalog.category("some-uuid").to_a).to eq([])
      expect { catalog.category(:nope).to_a }.to raise_error(KeyError)
    end
  end
```

- [ ] **Step 2: Run them to make sure they fail** — expected `NoMethodError` / stub mismatch.

- [ ] **Step 3: Implement** — add to `lib/psn_client/resources/catalog.rb` (constants near the others, methods before `private`):

```ruby
      ADD_ONS_OPERATION = "metGetAddOnsByTitleId"
      ADD_ONS_HASH = "e98d01ff5c1854409a405a5f79b5a9bcd36a5c0679fb33f4e18113c157d4d916"
      CATEGORY_OPERATION = "categoryGridRetrieve"
      CATEGORY_HASH = "4ce7d410a4db2c8b635a48c1dcec375906ff63b19dadd87e073f8fd0c0481d35"
      # Store category UUIDs (from the web store's routes). Any other
      # category UUID string can be passed to #category directly.
      CATEGORIES = {
        ps5_games: "4cbf39e2-5749-4970-ba81-93a489e4570c",
        ps4_games: "44d8bb20-653e-431e-8ad0-c0a365f68d2f",
        ps_plus: "038b4df3-bb4c-48f8-8290-3feb35f0f0fd",
        deals: "803cee19-e5a1-4d59-a463-0b6b2701bf7c",
        free_games: "d9930400-c5c7-4a06-a28d-cc74888426dc",
        new_games: "e1699f77-77e1-43ca-a296-26d08abacb0f"
      }.freeze
      PAGE_SIZE = 50
```

```ruby
      # DLC and add-ons for a title ID ("PPSA31381_00").
      def add_ons(np_title_id)
        paginator = Paginator.offset(page_size: PAGE_SIZE) do |size, offset|
          variables = { "npTitleId" => np_title_id, "pageArgs" => { "size" => size, "offset" => offset } }
          response = graphql(ADD_ONS_OPERATION, variables, ADD_ONS_HASH)
          page = response.dig("data", "addOnProductsByTitleIdRetrieve") || {}
          [page["addOnProducts"] || [], page.dig("pageInfo", "totalCount")]
        end
        paginator.map { |product| CatalogItem.from_api(product) }
      end

      # Browse a store category: a CATEGORIES symbol or any category UUID.
      def category(id, sort: "productReleaseDate", ascending: false)
        category_id = id.is_a?(Symbol) ? CATEGORIES.fetch(id) : id
        paginator = Paginator.offset(page_size: PAGE_SIZE) do |size, offset|
          response = graphql(CATEGORY_OPERATION,
                             category_variables(category_id, size, offset, sort, ascending),
                             CATEGORY_HASH)
          grid = response.dig("data", "categoryGridRetrieve") || {}
          [grid["products"] || [], grid.dig("pageInfo", "totalCount")]
        end
        paginator.map { |product| CatalogItem.from_api(product) }
      end
```

And a private helper below `graphql`:

```ruby
      def category_variables(category_id, size, offset, sort, ascending)
        { "id" => category_id, "pageArgs" => { "size" => size, "offset" => offset },
          "sortBy" => { "name" => sort, "isAscending" => ascending },
          "filterBy" => [], "facetOptions" => [] }
      end
```

If RuboCop now flags `Metrics/ClassLength` (max 100 code lines), move ALL the `*_OPERATION`/`*_HASH`/`CATEGORIES` constant pairs into a single frozen constant-bearing module... do NOT. Instead check first: comments don't count toward ClassLength, and the class body should land just under 100. If it still trips, the sanctioned fix is to exclude nothing and instead extract `category_variables`-style private builders (code, not disables). Only as a last resort add a `# rubocop:disable Metrics/ClassLength` with a comment explaining the constants-heavy nature.

- [ ] **Step 4: Run the tests, then commit**

Run: `bundle exec rspec spec/psn_client/resources/catalog_spec.rb && bundle exec rubocop lib/psn_client/resources/catalog.rb` — expected PASS / no offenses.

```bash
git add lib/psn_client/resources/catalog.rb spec/psn_client/resources/catalog_spec.rb
git commit -m "feat: add Catalog add-ons and category browsing"
```

### Task 10: Game Help models

**Files:**
- Create: `lib/psn_client/models/game_help.rb`
- Create: `spec/fixtures/help_availability.json`, `spec/fixtures/trophy_tips.json`
- Modify: `lib/psn_client.rb`
- Test: `spec/psn_client/models/game_help_spec.rb`

- [ ] **Step 1: Create fixtures** (from andshrew's documented examples)

`spec/fixtures/help_availability.json`:

```json
{
  "__typename": "TrophyInfoWithHintAvailable",
  "helpType": "HINT",
  "id": "NPWR20188_00::18",
  "trophyId": "18",
  "udsObjectId": "GATCHA_SECRET"
}
```

`spec/fixtures/trophy_tips.json`:

```json
{
  "__typename": "Tips",
  "hasAccess": true,
  "trophies": [
    {
      "__typename": "TrophyTip",
      "id": "NPWR20188_00::18",
      "trophyId": "18",
      "totalGroupCount": 1,
      "groups": [
        {
          "__typename": "TipGroup",
          "groupId": null,
          "groupName": null,
          "tipContents": [
            {
              "__typename": "TipContent",
              "description": "The gatcha prize you seek is inside a silver ball.",
              "displayName": "Since 1995",
              "mediaId": "psn534f6d378d6841939cd709202c46a220",
              "mediaType": "VIDEO",
              "mediaUrl": "https://gms-ght.playstation-cloud.com/video/master_playlist.m3u8",
              "tipId": "NPWR20188_00__GATCHA_SECRET_H1"
            }
          ]
        }
      ]
    }
  ]
}
```

- [ ] **Step 2: Write the failing test** `spec/psn_client/models/game_help_spec.rb`:

```ruby
# frozen_string_literal: true

RSpec.describe PSN::GameHelp do
  it "maps access and tips with flattened contents" do
    help = described_class.from_api(fixture("trophy_tips"))
    expect(help).to be_access
    expect(help.tips.size).to eq(1)
    expect(help.tips.first).to be_a(PSN::TrophyTip)
    expect(help.tips.first.trophy_id).to eq("18")
    expect(help.tips.first.contents.first.display_name).to eq("Since 1995")
  end

  it "maps tip content fields" do
    content = described_class.from_api(fixture("trophy_tips")).tips.first.contents.first
    expect(content).to be_a(PSN::TipContent)
    expect(content.description).to eq("The gatcha prize you seek is inside a silver ball.")
    expect(content.media_type).to eq("VIDEO")
    expect(content.media_url).to eq("https://gms-ght.playstation-cloud.com/video/master_playlist.m3u8")
    expect(content.tip_id).to eq("NPWR20188_00__GATCHA_SECRET_H1")
  end

  it "reports no access on an empty or gated payload" do
    help = described_class.from_api({})
    expect(help).not_to be_access
    expect(help.tips).to eq([])
  end
end

RSpec.describe PSN::TrophyHelpInfo do
  it "maps the hint availability shape" do
    info = described_class.from_api(fixture("help_availability"))
    expect(info.trophy_id).to eq("18")
    expect(info.uds_object_id).to eq("GATCHA_SECRET")
    expect(info.help_type).to eq("HINT")
    expect(info.raw).to eq(fixture("help_availability"))
  end
end
```

Note: two top-level `RSpec.describe` blocks in one file — `RSpec/SpecFilePathFormat` matches on the FIRST described class (`PSN::GameHelp` → `game_help_spec.rb` ✓).

- [ ] **Step 3: Run it to make sure it fails** — expected `uninitialized constant PSN::GameHelp`.

- [ ] **Step 4: Implement** `lib/psn_client/models/game_help.rb` (the four Game Help shapes change together, so they share a file):

```ruby
# frozen_string_literal: true

module PSN
  # One trophy that has Game Help available (metGetHintAvailability).
  # Pass these straight to Trophies#game_help to fetch the actual tips.
  TrophyHelpInfo = Data.define(:trophy_id, :uds_object_id, :help_type, :raw) do
    def self.from_api(hash)
      new(trophy_id: hash["trophyId"], uds_object_id: hash["udsObjectId"],
          help_type: hash["helpType"], raw: hash)
    end
  end

  # metGetTips result. access? is false when the authenticated account has
  # no PS+ subscription — Sony still answers, but with the content gated.
  GameHelp = Data.define(:access, :tips, :raw) do
    def self.from_api(hash)
      new(access: hash["hasAccess"] == true,
          tips: (hash["trophies"] || []).map { |t| TrophyTip.from_api(t) }, raw: hash)
    end

    def access? = access
  end

  # Game Help for one trophy; contents flattens the group nesting.
  TrophyTip = Data.define(:trophy_id, :contents, :raw) do
    def self.from_api(hash)
      contents = (hash["groups"] || []).flat_map { |g| g["tipContents"] || [] }
      new(trophy_id: hash["trophyId"],
          contents: contents.map { |c| TipContent.from_api(c) }, raw: hash)
    end
  end

  # A single hint: text plus an optional (PS+-tokenized) video stream URL.
  TipContent = Data.define(:description, :display_name, :media_type, :media_url, :tip_id, :raw) do
    def self.from_api(hash)
      new(description: hash["description"], display_name: hash["displayName"],
          media_type: hash["mediaType"], media_url: hash["mediaUrl"],
          tip_id: hash["tipId"], raw: hash)
    end
  end
end
```

Add to `lib/psn_client.rb` after store_concept:

```ruby
require_relative "psn_client/models/game_help"
```

- [ ] **Step 5: Run the tests, then commit**

```bash
bundle exec rspec spec/psn_client/models/game_help_spec.rb
git add lib/psn_client/models/game_help.rb lib/psn_client.rb spec/fixtures/help_availability.json spec/fixtures/trophy_tips.json spec/psn_client/models/game_help_spec.rb
git commit -m "feat: add Game Help models"
```

### Task 11: `Trophies#game_help_availability` and `Trophies#game_help`

**Files:**
- Modify: `lib/psn_client/resources/trophies.rb`
- Test: `spec/psn_client/resources/trophies_spec.rb`

- [ ] **Step 1: Write the failing tests** — add to `spec/psn_client/resources/trophies_spec.rb` (it already has `connection`/`users` doubles; reuse its `subject`):

```ruby
  describe "#game_help_availability" do
    it "lists trophies with Game Help via metGetHintAvailability" do
      response = { "data" => { "hintAvailabilityRetrieve" => { "trophies" => [fixture("help_availability")] } } }
      allow(connection).to receive(:graphql)
        .with("metGetHintAvailability", { "npCommId" => "NPWR20188_00" },
              described_class::HELP_AVAILABILITY_HASH, headers: described_class::GAME_HELP_HEADERS)
        .and_return(response)

      result = trophies.game_help_availability(np_communication_id: "NPWR20188_00").to_a
      expect(result.size).to eq(1)
      expect(result.first).to be_a(PSN::TrophyHelpInfo)
      expect(result.first.uds_object_id).to eq("GATCHA_SECRET")
    end

    it "limits the check to specific trophy IDs when given" do
      response = { "data" => { "hintAvailabilityRetrieve" => { "trophies" => [] } } }
      allow(connection).to receive(:graphql)
        .with("metGetHintAvailability", { "npCommId" => "NPWR20188_00", "trophyIds" => %w[18 19] },
              described_class::HELP_AVAILABILITY_HASH, headers: described_class::GAME_HELP_HEADERS)
        .and_return(response)

      expect(trophies.game_help_availability(np_communication_id: "NPWR20188_00", trophy_ids: [18, 19]).to_a).to eq([])
    end
  end

  describe "#game_help" do
    let(:tips_variables) do
      { "npCommId" => "NPWR20188_00",
        "trophies" => [{ "trophyId" => "18", "udsObjectId" => "GATCHA_SECRET", "helpType" => "HINT" }] }
    end

    it "fetches tips for TrophyHelpInfo objects" do
      allow(connection).to receive(:graphql)
        .with("metGetTips", tips_variables, described_class::TIPS_HASH,
              headers: described_class::GAME_HELP_HEADERS)
        .and_return({ "data" => { "tipsRetrieve" => fixture("trophy_tips") } })

      info = PSN::TrophyHelpInfo.from_api(fixture("help_availability"))
      help = trophies.game_help(np_communication_id: "NPWR20188_00", trophies: [info])
      expect(help).to be_a(PSN::GameHelp)
      expect(help).to be_access
      expect(help.tips.first.contents.first.display_name).to eq("Since 1995")
    end

    it "accepts plain hashes with symbol keys" do
      allow(connection).to receive(:graphql)
        .with("metGetTips", tips_variables, described_class::TIPS_HASH,
              headers: described_class::GAME_HELP_HEADERS)
        .and_return({ "data" => { "tipsRetrieve" => fixture("trophy_tips") } })

      help = trophies.game_help(np_communication_id: "NPWR20188_00",
                                trophies: [{ trophy_id: 18, uds_object_id: "GATCHA_SECRET", help_type: "HINT" }])
      expect(help.tips.size).to eq(1)
    end
  end
```

If the existing spec names its subject differently (check the top of the file), match it.

- [ ] **Step 2: Run them to make sure they fail** — expected `NoMethodError: game_help_availability`.

- [ ] **Step 3: Implement** — in `lib/psn_client/resources/trophies.rb`, add constants after `GROUPS_EARNED_PATH`:

```ruby
      # Game Help (PS+ trophy hints) persisted queries. Undocumented; Sony
      # can change hashes and shape at any time — verify with bin/smoke.
      # Requests must identify as the PlayStation App or Sony rejects them.
      GAME_HELP_HEADERS = { "apollographql-client-name" => "PlayStationApp-Android" }.freeze
      HELP_AVAILABILITY_OPERATION = "metGetHintAvailability"
      HELP_AVAILABILITY_HASH = "71bf26729f2634f4d8cca32ff73aaf42b3b76ad1d2f63b490a809b66483ea5a7"
      TIPS_OPERATION = "metGetTips"
      TIPS_HASH = "93768752a9f4ef69922a543e2209d45020784d8781f57b37a5294e6e206c5630"
```

Add methods before `private`:

```ruby
      # Trophies in a title that have Game Help available. Pass trophy_ids
      # to limit the check; the results feed straight into #game_help.
      def game_help_availability(np_communication_id:, trophy_ids: nil)
        variables = { "npCommId" => np_communication_id }
        variables["trophyIds"] = trophy_ids.map(&:to_s) if trophy_ids
        response = @connection.graphql(HELP_AVAILABILITY_OPERATION, variables,
                                       HELP_AVAILABILITY_HASH, headers: GAME_HELP_HEADERS)
        trophies = response.dig("data", "hintAvailabilityRetrieve", "trophies") || []
        trophies.lazy.map { |t| TrophyHelpInfo.from_api(t) }
      end

      # The Game Help content itself. trophies takes TrophyHelpInfo objects
      # (from #game_help_availability) or hashes with :trophy_id,
      # :uds_object_id and :help_type. GameHelp#access? is false without PS+.
      def game_help(np_communication_id:, trophies:)
        variables = { "npCommId" => np_communication_id,
                      "trophies" => trophies.map { |t| help_request(t) } }
        response = @connection.graphql(TIPS_OPERATION, variables, TIPS_HASH,
                                       headers: GAME_HELP_HEADERS)
        GameHelp.from_api(response.dig("data", "tipsRetrieve") || {})
      end
```

Add a private helper after `service_params`:

```ruby
      def help_request(trophy)
        if trophy.is_a?(TrophyHelpInfo)
          { "trophyId" => trophy.trophy_id, "udsObjectId" => trophy.uds_object_id,
            "helpType" => trophy.help_type }
        else
          { "trophyId" => trophy[:trophy_id].to_s, "udsObjectId" => trophy[:uds_object_id],
            "helpType" => trophy[:help_type] }
        end
      end
```

- [ ] **Step 4: Run the tests, then commit**

Run: `bundle exec rspec spec/psn_client/resources/trophies_spec.rb && bundle exec rubocop lib/psn_client/resources/trophies.rb` — expected PASS / no offenses (watch `Metrics/ClassLength`; extract further private helpers if it trips).

```bash
git add lib/psn_client/resources/trophies.rb spec/psn_client/resources/trophies_spec.rb
git commit -m "feat: add trophy Game Help availability and tips"
```

### Task 12: bin/smoke sections + docs

**Files:**
- Modify: `bin/smoke`, `CLAUDE.md`, `README.md`

- [ ] **Step 1: Extend `bin/smoke`** — add before the final "Refresh token" lines:

```ruby
section("Search: 3 games matching 'astro'") do
  client.search.games("astro").first(3).each do |g|
    puts "#{g.name} [#{g.platforms.join('/')}] #{g.price&.discounted_price || '-'}"
  end
end

section("Search: 3 users matching 'test'") do
  client.search.users("test").first(3).each { |u| puts "#{u.online_id} plus=#{u.ps_plus?}" }
end

section("Catalog: product detail, pricing and rating via search") do
  hit = client.search.games("astro bot").first(1).first
  product = client.catalog.product(hit.id)
  puts "#{product.name} by #{product.publisher} (#{product.content_rating})"
  puts "price: #{client.catalog.pricing(product.concept_id)&.discounted_price || '-'}"
  rating = client.catalog.product_rating(hit.id)
  puts "rating: #{rating&.average_display} from #{rating&.total} ratings"
end

section("Catalog: 3 newest PS5 games") do
  client.catalog.category(:ps5_games).first(3).each { |g| puts "#{g.name} #{g.price&.base_price || '-'}" }
end

section("Catalog: add-ons for most recent played game") do
  id = client.games.played.first(1).first.title_id
  client.catalog.add_ons(id).first(3).each { |a| puts "#{a.name} #{a.price&.discounted_price || '-'}" }
end

section("Game Help for ASTRO's PLAYROOM (NPWR20188_00)") do
  infos = client.trophies.game_help_availability(np_communication_id: "NPWR20188_00").first(3)
  infos.each { |t| puts "trophy #{t.trophy_id} #{t.help_type} #{t.uds_object_id}" }
  help = client.trophies.game_help(np_communication_id: "NPWR20188_00", trophies: infos.first(1))
  puts "access=#{help.access?} tips=#{help.tips.flat_map(&:contents).map(&:display_name).join(', ')}"
end
```

- [ ] **Step 2: Update `CLAUDE.md`**

In the Architecture layer list, extend the Client bullet's resource list to `(client.games, client.trophies, client.store, client.profiles, client.search, client.catalog)`.

In the "Undocumented endpoints" section, replace the file list sentence so it reads:

```
Knowledge of each is deliberately confined to one file: `resources/store.rb`,
`resources/games.rb`, `resources/profiles.rb`, `resources/search.rb` (game/user
search), `resources/catalog.rb` (web-host store catalog, anonymous), and the
Game Help queries in `resources/trophies.rb`.
```

- [ ] **Step 3: Update `README.md`** — read its existing usage section and add matching examples:

```ruby
# Search the store and players
client.search.games("astro bot").first(5)
client.search.users("a_friend").first(5)

# Store catalog (no account data involved)
product = client.catalog.product("UP9000-PPSA01325_00-...")
client.catalog.pricing(product.concept_id)   # => PSN::Price or nil
client.catalog.product_rating(product.id)    # => PSN::StarRating or nil
client.catalog.category(:ps5_games).first(10)
client.catalog.add_ons("PPSA01325_00").first(10)

# Trophy Game Help (PS+ hints)
infos = client.trophies.game_help_availability(np_communication_id: "NPWR20188_00")
client.trophies.game_help(np_communication_id: "NPWR20188_00", trophies: infos.first(2))
```

Match the README's existing tone/format — extend its resource table/list if it has one.

- [ ] **Step 4: Commit**

```bash
bundle exec rubocop bin/smoke
git add bin/smoke CLAUDE.md README.md
git commit -m "docs: document search, catalog and Game Help; extend bin/smoke"
```

### Task 13: Full verification

- [ ] **Step 1: Run the whole suite exactly as CI does**

Run: `bundle exec rake`
Expected: rspec green with SimpleCov ≥99% line / ≥85% branch, rubocop no offenses. If coverage dips below the gate, the uncovered lines are almost certainly model branches (`|| []`, `&&` guards) — add a fixture-variant example to the relevant model spec rather than loosening the gate.

- [ ] **Step 2: Live smoke test (needs credentials — coordinate with Matty)**

Run: `PSN_NPSSO=... ruby bin/smoke` (or `PSN_REFRESH_TOKEN=...`).
Expected: every new section prints real data; `FAILED:` lines mean a hash or response key drifted — fix the constant/model, re-run, and record any newly discovered quirk as a comment in the resource file. The search and Game Help hashes came from third-party projects and MUST be smoke-verified before merge; the catalog ones were verified live on 2026-07-09.

- [ ] **Step 3: Commit any smoke-driven fixes, then hand off**

Use the superpowers:finishing-a-development-branch skill to decide merge/PR.

## Self-Review Notes

- Spec coverage: all four requested groups have tasks (search 2-5, catalog lookups 6-8, web-host browse/ratings 8-9, Game Help 10-11); the `Connection#graphql` host change the web-host group needs is Task 1.
- Type consistency check: `CatalogItem.cover_url` (Task 3) is reused by `StoreProduct`/`StoreConcept` (Task 7); `StoreProduct.description_of` is reused by `StoreConcept`; `described_class::*_HASH` constants referenced in specs are all defined in their resource files; `Price` is required before `CatalogItem`, and both before the resources, in `lib/psn_client.rb`.
- Known risks called out where they bite: RuboCop `Metrics/ClassLength` (Tasks 9, 11), `RSpec/MultipleExpectations` (Tasks 5, 8), search/Game Help hashes unverified until smoke (Task 13).
