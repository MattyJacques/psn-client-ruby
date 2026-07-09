# Store Wishlist Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Expose the authenticated account's PlayStation Store wishlist as `client.store.wishlist`, backed by the `metGetStoreWishlist` GraphQL persisted query.

**Architecture:** One new immutable model (`PSN::WishlistItem`, flat `Data.define` like the other models) and one new method on the existing `Resources::Store` class following the `Games#library` single-request pattern: `Connection#graphql` → dig the item array → `lazy.map` to models. No Connection, Auth, or Client changes.

**Tech Stack:** Ruby 3.2+, Faraday (already wired), RSpec + fixtures (`fixture("name")` helper), RuboCop, SimpleCov gate 99% line / 85% branch.

**Spec:** `docs/superpowers/specs/2026-07-08-store-wishlist-design.md`

## Global Constraints

- Everything lives under the `PSN` module (not `PsnClient`).
- RuboCop: double-quoted string literals (but single quotes inside interpolation — `Style/StringLiteralsInInterpolation` runs at its single-quote default), LF line endings, max line length 120, `NewCops: enable`. Run `bundle exec rubocop` before every commit.
- Specs: `RSpec.describe` (monkey-patching disabled), WebMock blocks real HTTP, fixtures live in `spec/fixtures/` loaded via `fixture("name")`.
- Undocumented-endpoint convention: the operation name and sha256 hash appear ONLY in `lib/psn_client/resources/store.rb`, with quirks recorded in comments there.
- SimpleCov gates `bundle exec rspec` at 99% line / 85% branch — every new branch (e.g. nil-price Concept) needs a test.
- The persisted query was verified live 2026-07-08: operationName `metGetStoreWishlist`, variables `{}`, sha256Hash `571149e8aa4d76af7dd33b92e1d6f8f828ebc5fa8f0f6bf51a8324a0e6d71324`, mobile host (the one `Connection#graphql` already uses). Response: `data.storeWishlist` = flat array, no pagination.

---

### Task 1: `PSN::WishlistItem` model

**Files:**
- Create: `spec/fixtures/wishlist_item.json`
- Create: `spec/fixtures/wishlist_concept.json`
- Create: `lib/psn_client/models/wishlist_item.rb`
- Modify: `lib/psn_client.rb` (add one `require_relative`)
- Test: `spec/psn_client/models/store_models_spec.rb` (append a `describe` block)

**Interfaces:**
- Consumes: nothing new — plain `Data.define` like `lib/psn_client/models/purchased_game.rb`.
- Produces: `PSN::WishlistItem.from_api(hash) → WishlistItem` with members `name, id, concept, platforms, image_url, classification, localized_classification, base_price, discounted_price, discount_text, free, tied_to_subscription, exclusive, service_branding, upsell_service_branding, upsell_text, sku_id, raw` and predicates `concept?`, `free?`, `tied_to_subscription?`, `exclusive?`. Task 2 relies on `WishlistItem.from_api`.

- [ ] **Step 1: Create the two fixtures (real captured API items, verbatim)**

`spec/fixtures/wishlist_item.json` — a released `Product` with PS Plus branding:

```json
{
  "__typename": "Product",
  "boxArt": {
    "__typename": "Media",
    "url": "https://image.api.playstation.com/vulcan/ap/rnd/202205/1307/QpeOEfRcYvTWs6oU7vwePeWK.png"
  },
  "id": "UP0102-PPSA07813_00-CLASSICRE2000001",
  "localizedStoreDisplayClassification": "Full Game",
  "name": "Resident Evil 2",
  "platforms": [
    "PS4",
    "PS5"
  ],
  "price": {
    "__typename": "SkuPrice",
    "basePrice": "£7.99",
    "discountText": null,
    "discountedPrice": "Included",
    "isExclusive": false,
    "isFree": true,
    "isTiedToSubscription": true,
    "serviceBranding": [
      "PS_PLUS"
    ],
    "skuId": "UP0102-PPSA07813_00-CLASSICRE2000001-E001",
    "upsellServiceBranding": [
      "NONE"
    ],
    "upsellText": null
  },
  "storeDisplayClassification": "FULL_GAME"
}
```

`spec/fixtures/wishlist_concept.json` — an unreleased `Concept` (nil price, empty platforms):

```json
{
  "__typename": "Concept",
  "boxArt": {
    "__typename": "Media",
    "url": "https://image.api.playstation.com/vulcan/ap/rnd/202505/2906/57a51bad6ae63fb29c8c4e92e5aabcb3d73dc2b0ba54b582.png"
  },
  "id": "10015616",
  "localizedStoreDisplayClassification": null,
  "name": "Shelter Survival",
  "platforms": [],
  "price": null,
  "storeDisplayClassification": null
}
```

- [ ] **Step 2: Write the failing model spec**

Append inside the top-level `RSpec.describe "store models" do` block of `spec/psn_client/models/store_models_spec.rb` (after the `PSN::Entitlement` describe):

```ruby
  describe PSN::WishlistItem do
    subject(:item) { described_class.from_api(fixture("wishlist_item")) }

    it "maps identity, platforms and artwork" do
      expect(item.name).to eq("Resident Evil 2")
      expect(item.id).to eq("UP0102-PPSA07813_00-CLASSICRE2000001")
      expect(item.platforms).to eq(%w[PS4 PS5])
      expect(item.image_url).to start_with("https://image.api.playstation.com/")
      expect(item).not_to be_concept
    end

    it "maps the store classification in both forms" do
      expect(item.classification).to eq("FULL_GAME")
      expect(item.localized_classification).to eq("Full Game")
    end

    it "flattens the price fields" do
      expect(item.base_price).to eq("£7.99")
      expect(item.discounted_price).to eq("Included")
      expect(item.discount_text).to be_nil
      expect(item.sku_id).to eq("UP0102-PPSA07813_00-CLASSICRE2000001-E001")
      expect(item.service_branding).to eq(["PS_PLUS"])
    end

    it "exposes the price flags as predicates and keeps upsell data" do
      expect(item).to be_free
      expect(item).to be_tied_to_subscription
      expect(item).not_to be_exclusive
      expect(item.upsell_service_branding).to eq(["NONE"])
      expect(item.upsell_text).to be_nil
    end

    it "maps an unreleased concept: no price, empty platforms, nil classification" do
      concept = described_class.from_api(fixture("wishlist_concept"))
      expect(concept).to be_concept
      expect(concept.id).to eq("10015616")
      expect(concept.platforms).to eq([])
      expect(concept.base_price).to be_nil
      expect(concept).not_to be_free
    end

    it "keeps the untouched API hash in raw" do
      expect(item.raw).to eq(fixture("wishlist_item"))
    end
  end
```

- [ ] **Step 3: Run the spec to verify it fails**

Run: `bundle exec rspec spec/psn_client/models/store_models_spec.rb`
Expected: FAIL — `uninitialized constant PSN::WishlistItem` (the two existing describes still pass).

- [ ] **Step 4: Write the model**

Create `lib/psn_client/models/wishlist_item.rb`:

```ruby
# frozen_string_literal: true

module PSN
  # One PlayStation Store wishlist entry: either a released Product (has a
  # price) or an unreleased Concept (price is nil, platforms may be empty).
  # Prices are Sony's locale-formatted strings ("£64.99", "Included") — the
  # API returns no numeric amount.
  WishlistItem = Data.define(:name, :id, :concept, :platforms, :image_url,
                             :classification, :localized_classification,
                             :base_price, :discounted_price, :discount_text,
                             :free, :tied_to_subscription, :exclusive,
                             :service_branding, :upsell_service_branding,
                             :upsell_text, :sku_id, :raw) do
    def self.from_api(hash)
      price = hash["price"] || {}
      new(name: hash["name"], id: hash["id"], concept: hash["__typename"] == "Concept",
          platforms: hash["platforms"] || [], image_url: hash.dig("boxArt", "url"),
          classification: hash["storeDisplayClassification"],
          localized_classification: hash["localizedStoreDisplayClassification"],
          base_price: price["basePrice"], discounted_price: price["discountedPrice"],
          discount_text: price["discountText"], free: price["isFree"] == true,
          tied_to_subscription: price["isTiedToSubscription"] == true,
          exclusive: price["isExclusive"] == true,
          service_branding: price["serviceBranding"],
          upsell_service_branding: price["upsellServiceBranding"],
          upsell_text: price["upsellText"], sku_id: price["skuId"], raw: hash)
    end

    def concept? = concept
    def free? = free
    def tied_to_subscription? = tied_to_subscription
    def exclusive? = exclusive
  end
end
```

In `lib/psn_client.rb`, add after the `entitlement` require (line 19):

```ruby
require_relative "psn_client/models/wishlist_item"
```

- [ ] **Step 5: Run the spec to verify it passes**

Run: `bundle exec rspec spec/psn_client/models/store_models_spec.rb`
Expected: PASS, 0 failures.

- [ ] **Step 6: Lint and commit**

```bash
bundle exec rubocop
git add lib/psn_client/models/wishlist_item.rb lib/psn_client.rb \
        spec/fixtures/wishlist_item.json spec/fixtures/wishlist_concept.json \
        spec/psn_client/models/store_models_spec.rb
git commit -m "feat: add WishlistItem model"
```

Expected: rubocop reports no offenses; commit succeeds.

---

### Task 2: `Store#wishlist` + docs

**Files:**
- Modify: `lib/psn_client/resources/store.rb` (constants + method)
- Modify: `README.md:59-61` (document the new call)
- Modify: `bin/smoke` (new section after "5 purchased games", ~line 58)
- Test: `spec/psn_client/resources/store_spec.rb` (append a `describe` block)

**Interfaces:**
- Consumes: `PSN::WishlistItem.from_api(hash)` from Task 1; existing `Connection#graphql(operation_name, variables, sha256_hash) → Hash` (raises `PSN::APIError` on GraphQL errors — no error handling needed here).
- Produces: `Store#wishlist → Enumerator::Lazy` of `PSN::WishlistItem`, plus `Resources::Store::WISHLIST_HASH` (referenced by the spec).

- [ ] **Step 1: Write the failing resource spec**

Append inside the top-level `RSpec.describe PSN::Resources::Store do` block of `spec/psn_client/resources/store_spec.rb` (after the `#entitlements` describe):

```ruby
  describe "#wishlist" do
    it "fetches the wishlist via the metGetStoreWishlist persisted query" do
      response = { "data" => { "storeWishlist" => [fixture("wishlist_item"), fixture("wishlist_concept")] } }
      allow(connection).to receive(:graphql)
        .with("metGetStoreWishlist", {}, PSN::Resources::Store::WISHLIST_HASH)
        .and_return(response)

      result = store.wishlist.to_a
      expect(result.size).to eq(2)
      expect(result.first).to be_a(PSN::WishlistItem)
      expect(result.first.name).to eq("Resident Evil 2")
      expect(result.last).to be_concept
    end

    it "returns a lazy enumerator and defaults to empty when the key is missing" do
      allow(connection).to receive(:graphql)
        .with("metGetStoreWishlist", {}, PSN::Resources::Store::WISHLIST_HASH)
        .and_return({ "data" => {} })

      expect(store.wishlist).to be_a(Enumerator::Lazy)
      expect(store.wishlist.to_a).to eq([])
    end
  end
```

- [ ] **Step 2: Run the spec to verify it fails**

Run: `bundle exec rspec spec/psn_client/resources/store_spec.rb`
Expected: FAIL — `uninitialized constant PSN::Resources::Store::WISHLIST_HASH` (existing examples still pass).

- [ ] **Step 3: Implement `Store#wishlist`**

In `lib/psn_client/resources/store.rb`, add the constants after `PAGE_SIZE = 50`:

```ruby
      # metGetStoreWishlist persisted query. Sony can change hash and shape
      # at any time; verify with bin/smoke. Takes no variables — the whole
      # wishlist comes back in one request, so there is no paging.
      WISHLIST_OPERATION = "metGetStoreWishlist"
      WISHLIST_HASH = "571149e8aa4d76af7dd33b92e1d6f8f828ebc5fa8f0f6bf51a8324a0e6d71324"
```

and the method after `#entitlements`:

```ruby
      # The store wishlist: released products with prices and unreleased
      # concepts alike (check #concept? — concepts have no price).
      def wishlist
        response = @connection.graphql(WISHLIST_OPERATION, {}, WISHLIST_HASH)
        items = response.dig("data", "storeWishlist") || []
        items.lazy.map { |item| WishlistItem.from_api(item) }
      end
```

- [ ] **Step 4: Run the spec to verify it passes**

Run: `bundle exec rspec spec/psn_client/resources/store_spec.rb`
Expected: PASS, 0 failures.

- [ ] **Step 5: Document in README and bin/smoke**

In `README.md`, extend the store block (lines 59–61):

```ruby
# Purchases and wishlist (authenticated account only)
client.store.transactions.first(20)  # orders, refunds, wallet funding
client.store.entitlements.to_a       # everything owned incl. free claims
client.store.wishlist.to_a           # store wishlist incl. unreleased concepts
```

(Note the heading line changes from `# Purchases (authenticated account only)`.)

In `bin/smoke`, add after the "5 purchased games" section:

```ruby
section("5 wishlist items") do
  client.store.wishlist.first(5).each do |w|
    puts "#{w.name} #{w.concept? ? '[concept]' : w.platforms.join('/')} #{w.discounted_price || '-'}"
  end
end
```

- [ ] **Step 6: Full suite, lint and commit**

```bash
bundle exec rake
git add lib/psn_client/resources/store.rb spec/psn_client/resources/store_spec.rb README.md bin/smoke
git commit -m "feat: add Store#wishlist via metGetStoreWishlist persisted query"
```

Expected: rake green (rspec incl. SimpleCov gate + rubocop); commit succeeds.

---

### Task 3: Live verification

**Files:** none changed — this task verifies the branch end-to-end.

**Interfaces:**
- Consumes: `bin/smoke` (needs `PSN_NPSSO` env var — defined in `~/.zshrc`; NPSSO tokens expire after ~2 months, refetch from https://ca.account.sony.com/api/v1/ssocookie if rejected).
- Produces: confirmation the persisted query works live, recorded in the final report.

- [ ] **Step 1: Run the full test suite once more**

Run: `bundle exec rake`
Expected: rspec green with coverage ≥ 99% line / 85% branch, rubocop 0 offenses.

- [ ] **Step 2: Run the live smoke check**

Run: `source ~/.zshrc && ruby bin/smoke`
Expected: the "5 wishlist items" section prints up to 5 lines like `Resident Evil 2 PS4/PS5 Included` with no `FAILED:` prefix. Other sections' results are informational (transactions/entitlements are known to FAIL — those REST endpoints are edge-blocked at Sony's CDN; that is pre-existing and not this feature's concern).

- [ ] **Step 3: Report**

No commit — report the smoke output for the wishlist section in the task summary.
