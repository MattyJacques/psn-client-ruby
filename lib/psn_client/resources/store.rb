# frozen_string_literal: true

module PSN
  module Resources
    # Purchases and wishlist for the AUTHENTICATED account only. Sony does
    # not document these endpoints and has changed them before; all knowledge
    # of their hosts, paths and response keys is confined to this file so a
    # change only lands here (and in the store models). Verify with bin/smoke.
    class Store
      # The mobile-app entitlements endpoint (the old :web
      # /api/entitlements/v2/users/me/internal_entitlements is edge-blocked
      # like the transactions endpoint). Serves PS4/PS5 entitlements only —
      # the app API does not return PS3/Vita items.
      ENTITLEMENTS_PATH = "/api/entitlement/v2/users/me/internal/entitlements"
      ENTITLEMENTS_PARAMS = {
        "entitlementType" => "1,2,3,4,5",
        "fields" => "titleMeta,gameMeta,conceptMeta,rewardMeta," \
                    "rewardMeta.retentionPolicy,rewardMeta.rewardMembershipType",
        "gameMetaPackageType" => "PSGD,PS4GD"
      }.freeze
      PAGE_SIZE = 50
      # metGetStoreWishlist persisted query. Sony can change hash and shape
      # at any time; verify with bin/smoke. Takes no variables — the whole
      # wishlist comes back in one request, so there is no paging.
      WISHLIST_OPERATION = "metGetStoreWishlist"
      WISHLIST_HASH = "571149e8aa4d76af7dd33b92e1d6f8f828ebc5fa8f0f6bf51a8324a0e6d71324"

      # Sony decommissioned the REST transaction-history endpoint at the CDN
      # edge (Akamai 403 HTML before auth; verified live 2026-07-08). The web
      # store now uses a GraphQL persisted query whose whitelisted hash is not
      # publicly known. Old endpoint, kept for the record:
      #   GET :web /api/transact/v1/purchases/transactions  (cursor paging)
      TRANSACTIONS_ERROR = "Sony decommissioned the transactions endpoint at its CDN edge; " \
                           "no working replacement is known (see resources/store.rb)"

      def initialize(connection)
        @connection = connection
      end

      # Monetary transaction history. Decommissioned by Sony — always raises.
      def transactions
        raise APIError, TRANSACTIONS_ERROR
      end

      # Everything the account owns on PS4/PS5: games, DLC, free claims.
      # title_ids: optional title-ID filter (Array or comma-separated String).
      def entitlements(title_ids: nil)
        extra = title_ids ? { "titleId" => Array(title_ids).join(",") } : {}
        paginator = Paginator.offset(page_size: PAGE_SIZE) do |limit, offset|
          response = @connection.get(:mobile, ENTITLEMENTS_PATH,
                                     ENTITLEMENTS_PARAMS.merge(extra, { "limit" => limit, "offset" => offset }))
          [response["entitlements"] || [], response["totalResults"]]
        end
        paginator.map { |e| Entitlement.from_api(e) }
      end

      # The store wishlist: released products with prices and unreleased
      # concepts alike (check #concept? — concepts have no price).
      def wishlist
        response = @connection.graphql(WISHLIST_OPERATION, {}, WISHLIST_HASH)
        items = response.dig("data", "storeWishlist") || []
        items.lazy.map { |item| WishlistItem.from_api(item) }
      end
    end
  end
end
