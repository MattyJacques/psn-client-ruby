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

## Verified candidates (anonymous, `:web` host)

All tested live 2026-07-09 with no Authorization header, using
`conceptId: "10015869"` / `productId: "UP6312-PPSA31381_00-0202050640964065"`
(Fable). These would all slot into `Resources::Catalog`.

### Concept detail slices

Each takes `{"conceptId": "<id>"}` and returns under `data.conceptRetrieve`.
They are the web store product page broken into sections — useful when the
full `metGetConceptById` payload is more than a caller needs.

| Operation | sha256Hash | Returns |
| --- | --- | --- |
| `conceptRetrieveForGameInfo` | `156bf37e6d6091b4d584ebf5f430a65e818b6120525dd82a0745352d21619da6` | descriptions, localizedGenres, publisherName, releaseDate |
| `conceptRetrieveForGameTitle` | `d244286e38044363f1fb6707f719d41558c74542fc421503a38124ca87068812` | name, ownedTitles, publisherName, releaseDate, descriptions |
| `conceptRetrieveForGameTitle` (alt) | `e9faf8c60bf31d71c5e72ff36f9f5ebc713e62d93e975e538e72c1875de8c27b` | same minus descriptions — two registered variants of one operation; both live |
| `conceptRetrieveForAccessibilityFeatures` | `5ad27cf7d1f053068dabf46cc131518a7b7d686e9d64daa1a500d8faab0444c2` | accessibilityNoticesByPlatform, platforms |
| `conceptRetrieveForMediaCarousel` | `404d96e0672728c19708b6519bcdc1427c5270ce76d9cb009cca39b8e68ace7b` | media (carousel set) |
| `conceptRetrieveForUpsellWithCtas` | `278822e6c6b9f304e4c788867b3e8a448c67847ac932d09213d5085811be3a18` | products (upsell editions), media |
| `queryRetrieveTelemetryDataPDPConcept` | `3fc354c90bf032e8ce86f7ebbe761e8a9315b23d564612ff4587f8a6bbc16d19` | minimal id/name/defaultProduct (telemetry helper; little value) |

### Other verified queries

- **Alternate star-rating hashes** (both live; different field sets from the
  ones the gem uses): `wcaProductStarRatingRetrive`
  `375261278d57455869b962bb5642868cea24e067793814d5b41767b3b082a2d8` (adds
  concept, topCategory, webctas), `wcaConceptStarRatingRetrive`
  `8c3dea41cf2f56baf3e0e0bfdf5e7298fa2941ab7488b8d7859bb0200dfb99b9`. Useful
  as fallbacks if Sony retires the current hashes.
- **`getDefaultView`** —
  `fc2998417fe7297a559b7f3798bf1c5e1650d88e926269bf6d8bd2cce3fddc76`. Hash is
  registered but requires `categoryId` (String!), `experienceId` (ID!) and
  `localizedKeyId` (String!) — the web store's view/experience system.
  Variable values not yet reverse-engineered; parked.

## Known hashes that need auth (unverified — check with `bin/smoke`)

Tested anonymously and refused with "Access denied", or never tested because
they are account-scoped. Hashes from the ioBroker adapter and psn-php maps.
`friendsWhoPlayRetrieveByConceptId` and the `getUserGameList` web variant are
no longer listed here — both are now recorded in the gem
(`resources/games.rb`: `#friends_who_play` is a provisional method for the
former, `LIBRARY_HASH_WEB` is a fallback constant for the latter).

| Operation | sha256Hash | Notes |
| --- | --- | --- |
| `backwardCompatibility` | `be14d5cbae5a065dc9ef5e33f7de93d1f6c01c6aa28e4b44b94bea37e4fd0c03` | hash registered on web host; variables unknown |
| `metGetWebCheckoutCart` | `2d4165c4de76877a32f3d08c91ce2af0e01d69300131fed0a8022868235e85b1` | app checkout cart |
| `metGetExperience` | `054e61ee68bbeadc21435caebcc4f2bba0919a99b06629d141b0b82dc55f10c4` | app store "experience" hub |
| `metGetViews` | `6fd98ff7fecb603006fb5d92db176d5028435be163c8d1ee9f7c598ab4677dd1` | app store browse: views → |
| `metGetDefaultView` | `bec1b8a3b0bae8c08e3ce2c7fe2f38a69343434ccfbcdd82cc1f2e44f86b7c40` | → default view → |
| `metGetCategoryGrids` | `cc0b6513521c59a321bf62334fa23a92f22cd2ce1abe9f014fadac6379e414a8` | → grids → |
| `metGetCategoryGrid` | `b67a9e4414b80d8d762bf12a588c6125467ae0bb3bbe3cee3f7696c6984f8ef6` | → one grid → |
| `metGetCategoryStrands` | `55ab5f168bec56f8362b5519f59faaf786d4e1cfeabb8bc969d6a65545e14f4d` | → strands (the app's store navigation tree) |
| `queryOracleUserProfileFullSubscription` | `3fe5e3cb6e16f83be98ccaa694823e10bdf428f9c7ff8e314b8464ad8976319d` | web account/subscription state ("oracle" = web account header) |
| `getAccountOracle` | `27a52f5d0866e53ce12c036030dae21c62fe65ab8debbceff1c40cd6b462d96d` | ditto |
| `getProfileOracle` | `fc0d765f537f3dce3e0d91c71e85daa401042ba43066acde9f8f584faced10df` | ditto |

## Dead or not worth implementing

- **`getCartItemCount`** `98136bcbc72e0fefccd8ecd6d3b3309225a6889c19df6e54581d86ff1c15d88a`
  — schema now rejects it (`Cannot query field "webCheckoutCartRetrieve"`);
  the hash outlived the schema. Kept here so nobody re-tries it.
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
