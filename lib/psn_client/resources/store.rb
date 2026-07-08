# frozen_string_literal: true

module PSN
  module Resources
    # Purchases for the AUTHENTICATED account only. Sony does not document
    # these endpoints and has changed them before; all knowledge of their
    # hosts, paths and response keys is confined to this file so a change
    # only lands here (and in the two store models). Verify with bin/smoke.
    class Store
      TRANSACTIONS_HOST = :web
      TRANSACTIONS_PATH = "/api/transact/v1/purchases/transactions"
      ENTITLEMENTS_HOST = :web
      ENTITLEMENTS_PATH = "/api/entitlements/v2/users/me/internal_entitlements"
      PAGE_SIZE = 50
      # metGetStoreWishlist persisted query. Sony can change hash and shape
      # at any time; verify with bin/smoke. Takes no variables — the whole
      # wishlist comes back in one request, so there is no paging.
      WISHLIST_OPERATION = "metGetStoreWishlist"
      WISHLIST_HASH = "571149e8aa4d76af7dd33b92e1d6f8f828ebc5fa8f0f6bf51a8324a0e6d71324"

      def initialize(connection)
        @connection = connection
      end

      # Monetary transaction history: orders, refunds, wallet funding.
      def transactions
        paginator = Paginator.cursor do |cursor|
          params = { "limit" => PAGE_SIZE }
          params["cursor"] = cursor if cursor
          response = @connection.get(TRANSACTIONS_HOST, TRANSACTIONS_PATH, params)
          [response["transactions"] || [], response["nextCursor"]]
        end
        paginator.map { |t| Transaction.from_api(t) }
      end

      # Everything the account owns: games, DLC, free claims.
      def entitlements
        paginator = Paginator.offset(page_size: PAGE_SIZE) do |limit, offset|
          response = @connection.get(ENTITLEMENTS_HOST, ENTITLEMENTS_PATH,
                                     { "limit" => limit, "offset" => offset })
          [response["entitlements"] || [], response["total_results"]]
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
