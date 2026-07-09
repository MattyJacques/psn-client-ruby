# Store Wishlist — Design

**Date:** 2026-07-08
**Status:** Approved

## Goal

Expose the authenticated account's PlayStation Store wishlist as
`client.store.wishlist`, backed by the `metGetStoreWishlist` GraphQL
persisted query.

## Background

The wishlist is only reachable through Sony's undocumented persisted-query
GraphQL endpoint. The query was captured from the mobile host
(`m.np.playstation.com`), which `Connection#graphql` already targets, so no
Connection changes are needed:

- operationName: `metGetStoreWishlist`
- variables: `{}` (empty — the whole wishlist comes back in one request,
  no pagination)
- sha256Hash: `571149e8aa4d76af7dd33b92e1d6f8f828ebc5fa8f0f6bf51a8324a0e6d71324`

Verified live on 2026-07-08. The response is
`data.storeWishlist` — a flat array of items. Each item is one of two
`__typename`s:

- **`Product`** — a purchasable store item. Has `id` (product ID like
  `EP0102-PPSA31246_00-REREQUIEM0000000`), `name`, `boxArt.url`,
  `platforms` (array, e.g. `["PS4", "PS5"]`),
  `storeDisplayClassification` (e.g. `FULL_GAME`, `GAME_BUNDLE`),
  `localizedStoreDisplayClassification`, and a `price` object (`SkuPrice`):
  `basePrice` / `discountedPrice` (locale-formatted strings like `"£64.99"`
  or `"Included"` — Sony returns no numeric amount), `discountText`,
  `isFree`, `isTiedToSubscription`, `isExclusive`, `serviceBranding`
  (array, e.g. `["PS_PLUS"]`), `skuId`, `upsellServiceBranding`,
  `upsellText`.
- **`Concept`** — a wishlisted unreleased game. Same keys, but `price` is
  `null`, `platforms` may be empty, classifications are `null`, and `id` is
  a numeric concept ID string.

## Design

### `Resources::Store#wishlist`

New method in `lib/psn_client/resources/store.rb`, following the
`Games#library` single-request pattern:

- Constants `WISHLIST_OPERATION` and `WISHLIST_HASH` live in this file,
  per the undocumented-endpoints convention (all knowledge of a Sony
  internal confined to one file, quirks recorded in comments, verified
  with `bin/smoke`).
- One `@connection.graphql(WISHLIST_OPERATION, {}, WISHLIST_HASH)` call;
  dig `data.storeWishlist`, default to `[]`; return
  `items.lazy.map { |item| WishlistItem.from_api(item) }`.

### `PSN::WishlistItem` model

New `lib/psn_client/models/wishlist_item.rb`, immutable `Data.define`
with `from_api(hash)` and `raw`, flat like `PurchasedGame`/`LibraryTitle`
(approach A — price fields flattened onto the item, nil/false for
Concepts):

| member | source | notes |
|---|---|---|
| `name` | `name` | |
| `id` | `id` | product ID or numeric concept ID |
| `concept` | `__typename == "Concept"` | `concept?` predicate; unreleased game |
| `platforms` | `platforms` | array — plural because the API returns one |
| `image_url` | `boxArt.url` | |
| `classification` | `storeDisplayClassification` | e.g. `"FULL_GAME"`; nil for Concepts |
| `localized_classification` | `localizedStoreDisplayClassification` | e.g. `"Full Game"`; nil for Concepts |
| `base_price` | `price.basePrice` | formatted string, nil for Concepts |
| `discounted_price` | `price.discountedPrice` | formatted string (can be `"Included"`) |
| `discount_text` | `price.discountText` | e.g. `"-50%"`; nil when no discount |
| `free` | `price.isFree == true` | `free?` predicate |
| `tied_to_subscription` | `price.isTiedToSubscription == true` | `tied_to_subscription?` predicate |
| `exclusive` | `price.isExclusive == true` | `exclusive?` predicate |
| `service_branding` | `price.serviceBranding` | array, e.g. `["PS_PLUS"]`; nil for Concepts |
| `upsell_service_branding` | `price.upsellServiceBranding` | array; nil for Concepts |
| `upsell_text` | `price.upsellText` | nil when no upsell offer |
| `sku_id` | `price.skuId` | nil for Concepts |
| `raw` | whole item hash | untouched API response |

Every field the query returns is mapped; nothing is left raw-only.

No `Mapping` additions: platforms arrive as display strings (`"PS5"`),
prices as formatted strings.

### Errors

Nothing new. `Connection#graphql` already maps HTTP errors and
200-with-`errors` GraphQL failures to the existing hierarchy.

### Tests

- Fixture `spec/fixtures/wishlist_item.json` distilled from the captured
  live response: one `Product` with `PS_PLUS` branding and one `Concept`
  (nil price, empty platforms), so both shapes are covered.
- Spec additions in `spec/psn_client/resources/store_spec.rb` mirroring
  the `Games#library` spec: mocks `Connection#graphql` via
  `instance_double` (the house convention — WebMock guards the Connection
  layer itself), asserts mapped fields for both item types, the nil-price
  Concept case, the `Enumerator::Lazy` return type (the fetch itself is
  eager, matching `Games#library`), and the empty-wishlist `[]` default.
- Model coverage goes in the existing
  `spec/psn_client/models/store_models_spec.rb` alongside the other store
  models.
- SimpleCov gate (99% line / 85% branch) must stay green.

### Smoke

Add a "5 wishlist items" section to `bin/smoke`; run it live before
finishing to confirm the query still works end-to-end.

## Out of scope

- Wishlist mutations (add/remove) — read-only for now.
- Restoring `Store#transactions`/`#entitlements` via GraphQL (separate
  effort; those REST endpoints are edge-blocked).
- Price normalization to numeric amounts — Sony doesn't return one.
