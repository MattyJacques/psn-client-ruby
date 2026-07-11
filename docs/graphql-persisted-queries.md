# PSN GraphQL persisted queries

Community-documented Sony persisted queries this gem uses or could use.
Compiled 2026-07-09 from community sources (listed at the bottom); every query
in the "verified" section was tested live against the API on that date.

## How the API works

Both GraphQL hosts serve the same path, `GET /api/graphql/v1/op`, with three
query parameters: `operationName`, `variables` (JSON) and `extensions`
(JSON: `{"persistedQuery":{"version":1,"sha256Hash":"<hash>"}}`). There is no
way to send arbitrary query text — Sony's servers only accept operations whose
sha256 hash is already registered, so an operation is only usable if its hash
is known. `PSN::Connection#graphql` wraps all of this.

- **`:web` host (`web.np.playstation.com`)** — backs the web store and
  library.playstation.com. The store catalog queries are served
  **anonymously** (no Authorization header needed); the account-scoped ones
  (library, friends) need the normal Bearer token.
- **`:mobile` host (`m.np.playstation.com`)** — backs the PlayStation App.
  Always needs a Bearer token, and the app's queries expect the
  `apollographql-client-name: PlayStationApp-Android` header (see
  `Resources::Search::HEADERS` / `Trophies::GAME_HELP_HEADERS`).

Failure modes seen in testing: HTTP 200 with an `errors` array (mapped to
`APIError` by `Connection`), HTTP 400 with `errors` when variables are missing
or a hash no longer matches the schema, and
`Access denied! You need to be authorized to perform this action!` when an
anonymous call hits an account-scoped operation.

### EMS variable recipes (2026-07-11)

The EMS (Experience Management System) queries and the oracle profile queries
have no public schema — variable shapes were reverse-engineered from the
store's own network traffic. Recorded here so they can be re-derived if Sony
rotates anything:

- The EMS `clientId` (`b6de8d4d-bf9b-11ee-ad2a-aea73dc1ea43`,
  `Resources::Browse::EMS_CLIENT_ID`) comes from `store.playstation.com`'s
  server-rendered HTML: the embedded Apollo cache contains a call to
  `emsExperienceRetrieve({"clientId":"b6de8d4d-…"})`, and the page's
  `data-telemetry-meta` attributes carry `emsExperienceId` / `emsViewId` /
  `emsCategoryId` for the experience/view UUIDs.
- `metGetViews` takes `{"viewInputs": [{"viewId": <uuid>, "experienceId": <uuid>}]}`;
  `metGetCategoryGrid`/`metGetCategoryGrids` take `{"id"/"grids": [...], "pageArgs": {"size", "offset"}}`;
  `metGetCategoryStrands` takes `{"strands": [{"id", "pageArgs"}]}`.
- `localizedKeyId` (a `metGetDefaultView` variable) values are the
  `localizedName` strings carried by EMS links, e.g. `cat.gma.July_Savings` —
  there is no enumeration endpoint, only ones seen in the wild.
- The oracle queries (`getProfileOracle`, `queryOracleUserProfileFullSubscription`)
  400 with `Cannot query field "oracleUserProfileRetrieve"` unless the request
  carries the `apollographql-client-name: oracle` header — that header routes
  the request to the web toolbar's schema (`web-toolbar` also works; the gem
  uses `oracle`).
- General probing technique: Sony's validation errors name the missing
  variable and its GraphQL type, so an unknown operation's shape can be
  recovered by sending `{}`, reading the error, then retrying with `[{}]` (or
  the named field) until the errors stop — this is how the `viewInputs`/
  `grids`/`strands` array-of-object shapes above were found.

## Already implemented in the gem

| Operation | Host | Resource |
| --- | --- | --- |
| `getUserGameList` (`e0136f81…`, app variant) | mobile | `resources/games.rb` |
| `getPurchasedGameList` (`827a423f…`) | mobile | `resources/games.rb` |
| `metGetStoreWishlist` (`571149e8…`) | mobile | `resources/store.rb` |
| `metGetHintAvailability` (`71bf2672…`) | mobile | `resources/trophies.rb` |
| `metGetTips` (`93768752…`) | mobile | `resources/trophies.rb` |
| `metGetContextSearchResults` (games `a2fbc154…`, users `ac5fb2b8…`) | mobile | `resources/search.rb` |
| `metGetDomainSearchResults` (games `b5162429…`, users `23ece284…`) | mobile | `resources/search.rb` |
| `metGetProductById` (`a1280421…`) | web | `resources/catalog.rb` |
| `metGetConceptById` (`cc90404a…`) | web | `resources/catalog.rb` |
| `metGetPricingDataByConceptId` (`abcb311e…`) | web | `resources/catalog.rb` |
| `wcaProductStarRatingRetrive` (`cedd370c…`) | web | `resources/catalog.rb` |
| `wcaConceptStarRatingRetrive` (`e12dc5ce…`) | web | `resources/catalog.rb` |
| `metGetAddOnsByTitleId` (`e98d01ff…`) | web | `resources/catalog.rb` |
| `categoryGridRetrieve` (`4ce7d410…`) | web | `resources/catalog.rb` |
| `conceptRetrieveForContentRating` (`b504e0bc…`) | web | `resources/catalog.rb` |
| `conceptRetrieveForMedia` (`615a2c46…`) | web | `resources/catalog.rb` |
| `conceptRetrieveForCompatibilityNotices` (`fb1a981a…`) | web | `resources/catalog.rb` |
| `wcaConceptRetrieveForLegalText` (`b4c35dd0…`) | web | `resources/catalog.rb` |
| `conceptRetrieveForCtasWithPrice` (`eab9d873…`) | web | `resources/catalog.rb` |
| `metGetConceptByProductIdQuery` (`0a4c9f36…`) | web | `resources/catalog.rb` |
| `getAddOnProductsByConcept` (`23c26f56…`) | web | `resources/catalog.rb` |
| `featuresRetrieve` (`010870e8…`) | web | `resources/catalog.rb` |
| `friendsWhoPlayRetrieveByConceptId` (`7bf9a61a…`, provisional) | web | `resources/games.rb` |
| `conceptRetrieveForGameInfo` (`156bf37e…`) | web | `resources/catalog.rb` |
| `conceptRetrieveForAccessibilityFeatures` (`5ad27cf7…`) | web | `resources/catalog.rb` |
| `conceptRetrieveForMediaCarousel` (`404d96e0…`) | web | `resources/catalog.rb` |
| `conceptRetrieveForUpsellWithCtas` (`278822e6…`) | web | `resources/catalog.rb` |
| `metGetExperience` (`054e61ee…`) | mobile | `resources/browse.rb` |
| `metGetViews` (`6fd98ff7…`) | mobile | `resources/browse.rb` |
| `metGetDefaultView` (`bec1b8a3…`) | mobile | `resources/browse.rb` |
| `metGetCategoryGrid` (`b67a9e44…`) | mobile | `resources/browse.rb` |
| `metGetCategoryStrands` (`55ab5f16…`) | mobile | `resources/browse.rb` |
| `getProfileOracle` (`fc0d765f…`) | web + `oracle` header | `resources/profiles.rb` |

## Verified candidates (anonymous, `:web` host)

All tested live 2026-07-09 with no Authorization header, using
`conceptId: "10015869"` / `productId: "UP6312-PPSA31381_00-0202050640964065"`
(Fable). These would mostly slot into `Resources::Catalog`, save for
`getDefaultView` below, which maps to `Browse#default_view`.

### Concept detail slices

Each takes `{"conceptId": "<id>"}` and returns under `data.conceptRetrieve`.
They are the web store product page broken into sections — useful when the
full `metGetConceptById` payload is more than a caller needs.

| Operation | sha256Hash | Returns |
| --- | --- | --- |
| `conceptRetrieveForGameTitle` | `d244286e38044363f1fb6707f719d41558c74542fc421503a38124ca87068812` | name, ownedTitles, publisherName, releaseDate, descriptions |
| `conceptRetrieveForGameTitle` (alt) | `e9faf8c60bf31d71c5e72ff36f9f5ebc713e62d93e975e538e72c1875de8c27b` | same minus descriptions — two registered variants of one operation; both live |
| `queryRetrieveTelemetryDataPDPConcept` | `3fc354c90bf032e8ce86f7ebbe761e8a9315b23d564612ff4587f8a6bbc16d19` | minimal id/name/defaultProduct (telemetry helper; little value) |

### Other verified queries

- **Alternate star-rating hashes** (both live; different field sets from the
  ones the gem uses): `wcaProductStarRatingRetrive`
  `375261278d57455869b962bb5642868cea24e067793814d5b41767b3b082a2d8` (adds
  concept, topCategory, webctas), `wcaConceptStarRatingRetrive`
  `8c3dea41cf2f56baf3e0e0bfdf5e7298fa2941ab7488b8d7859bb0200dfb99b9`. Useful
  as fallbacks if Sony retires the current hashes.
- **`getDefaultView`** (web host) —
  `fc2998417fe7297a559b7f3798bf1c5e1650d88e926269bf6d8bd2cce3fddc76`. Same
  `categoryId` (String!) / `experienceId` (ID!) / `localizedKeyId` (String!)
  trio as `metGetDefaultView`, now implemented as `Browse#default_view` (see
  "Already implemented in the gem"); this is the web store's version of the
  same operation, not yet needed since the mobile one covers the use case.

## Known hashes that need auth (unverified — check with `bin/smoke`)

Tested anonymously and refused with "Access denied", or never tested because
they are account-scoped. Hashes from the ioBroker adapter and psn-php maps.
`friendsWhoPlayRetrieveByConceptId` and the `getUserGameList` web variant are
no longer listed here — both are now recorded in the gem
(`resources/games.rb`: `#friends_who_play` is a provisional method for the
former, `LIBRARY_HASH_WEB` is a fallback constant for the latter). Likewise
`metGetExperience`, `metGetViews`, `metGetDefaultView`, `metGetCategoryGrid`,
`metGetCategoryStrands` and `getProfileOracle` moved to "Already implemented"
once their variable shapes were reverse-engineered (see the EMS variable
recipes above).

| Operation | sha256Hash | Notes |
| --- | --- | --- |
| `backwardCompatibility` | `be14d5cbae5a065dc9ef5e33f7de93d1f6c01c6aa28e4b44b94bea37e4fd0c03` | hash registered on web host; variables unknown |
| `metGetWebCheckoutCart` | `2d4165c4de76877a32f3d08c91ce2af0e01d69300131fed0a8022868235e85b1` | app checkout cart |
| `metGetCategoryGrids` | `cc0b6513521c59a321bf62334fa23a92f22cd2ce1abe9f014fadac6379e414a8` | verified live 2026-07-11 — batch variant of `metGetCategoryGrid` (`{"grids": [{"id", "pageArgs"}]}`); not implemented (same data) |
| `queryOracleUserProfileFullSubscription` | `3fe5e3cb6e16f83be98ccaa694823e10bdf428f9c7ff8e314b8464ad8976319d` | verified live 2026-07-11 with the oracle header — fallback for `getProfileOracle` (adds `isAuthorized`, drops `name`/`avatar`) |

## Dead or not worth implementing

- **`getCartItemCount`** `98136bcbc72e0fefccd8ecd6d3b3309225a6889c19df6e54581d86ff1c15d88a`
  — schema now rejects it (`Cannot query field "webCheckoutCartRetrieve"`);
  the hash outlived the schema. Kept here so nobody re-tries it.
- **`getAccountOracle`** `27a52f5d0866e53ce12c036030dae21c62fe65ab8debbceff1c40cd6b462d96d`
  — verified live 2026-07-11 (`{"accountId": <id>}`) but returns the
  PlayStation Stars loyalty account — service shuts down 2026-11-02.
- **PlayStation Stars loyalty queries** — `metGetAccount`,
  `metGetPointsHistory`, `metGetUserCollectibles`, `metGetCollectibleDisplay`,
  `metGetCollectibleScenes`, `metGetStatusLevels`, `metGetCampaignGroup`,
  `metLoyaltyCampaignByIdRetrieve`, `metGetRewardGroup`,
  `metLoyaltyRewardbyId`, `metLoyaltyGetOwnedCollectibleById` (hashes in the
  ioBroker constants file, request/response detail on andshrew's PlayStation
  Stars site). The program stopped accruals 2025-07-23 and shuts down
  entirely 2026-11-02 — don't build on it.

## Finding new hashes

From psn-api's notes, confirmed by how this list was assembled: open a page on
`library.playstation.com` or `store.playstation.com` with DevTools, filter
network requests to `web.np.playstation.com/api/graphql/v1/op`, and URL-decode
`operationName` + `extensions` to capture new operations and hashes. The hash
is the sha256 of the exact query text, which can be dug out of Sony's app
bundle JS (search for `PersistedQueryLink`). For the mobile host, MITM the
PlayStation App. Verify anything new with `bin/smoke` before relying on it.

## Sources

- [achievements-app/psn-api — operationHashes.ts](https://github.com/achievements-app/psn-api/blob/main/src/graphql/operationHashes.ts)
- [Lucky-ESA/ioBroker.playstation — lib/constants.js hashMap](https://github.com/Lucky-ESA/ioBroker.playstation/blob/main/lib/constants.js)
- [mrt1m/playstation-store-api — OperationSha256Enum.php](https://github.com/mrt1m/playstation-store-api/blob/main/src/Enum/OperationSha256Enum.php)
- [Tustin/psn-php — Api.php hashMap](https://github.com/Tustin/psn-php/blob/master/src/Api.php)
- [andshrew/PlayStation-Trophies — misc API docs (wishlist, search, store)](https://github.com/andshrew/PlayStation-Trophies/tree/master/docs/misc)
- [andshrew PlayStation Stars API docs](https://andshrew.github.io/PlayStation-Stars/)
- [isFakeAccount/psnawp — search models](https://github.com/isFakeAccount/psnawp)
- [PlayStation.Blog — PlayStation Stars coming to a close](https://blog.playstation.com/2025/05/21/playstation-stars-coming-to-a-close-as-sie-evaluates-new-ways-to-evolve-future-loyalty-program-efforts/)
