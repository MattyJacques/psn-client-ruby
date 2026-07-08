# frozen_string_literal: true

module PSN
  module Resources
    class Games
      TITLES_PATH = "/api/gamelist/v2/users/%s/titles"
      # The gamelist endpoint caps limit at 200 (verified live: 200 works,
      # 201 returns HTTP 400), so this page size sits exactly at the maximum.
      PAGE_SIZE = 200
      # getUserGameList persisted query. Sony can change hash and shape at
      # any time; all knowledge of them is confined to this file. Verify
      # with bin/smoke.
      LIBRARY_OPERATION = "getUserGameList"
      LIBRARY_HASH = "e0136f81d7d1fb6be58238c574e9a46e1c0cc2f7f6977a08a5a46f224523a004"
      LIBRARY_CATEGORIES = "ps4_game,ps5_native_game"
      # The API rejects limits above 100 with a GraphQL Argument Validation
      # Error (verified live: 100 works, 101 does not).
      LIBRARY_LIMIT = 100
      PURCHASED_OPERATION = "getPurchasedGameList"
      PURCHASED_HASH = "827a423f6a8ddca4107ac01395af2ec0eafd8396fc7fa204aaf9b7ed2eefa168"
      # purchasedTitlesRetrieve enforces no server-side size cap (verified live:
      # accepted up to 5000); this page size is a conservative choice, not a limit.
      PURCHASED_PAGE_SIZE = 200
      PURCHASED_VARIABLES = { "isActive" => true, "platform" => %w[ps4 ps5],
                              "sortBy" => "ACTIVE_DATE", "sortDirection" => "desc" }.freeze

      def initialize(connection, users)
        @connection = connection
        @users = users
      end

      # Every title the account has played, most recent first.
      def played(online_id = nil)
        account_id = @users.account_id(online_id)
        paginator = Paginator.offset(page_size: PAGE_SIZE) do |limit, offset|
          response = @connection.get(:mobile, format(TITLES_PATH, account_id),
                                     { "limit" => limit, "offset" => offset })
          [response["titles"] || [], response["totalItemCount"]]
        end
        paginator.map { |title| GameTitle.from_api(title) }
      end

      # The authenticated account's game library, owned and subscription
      # titles alike. Single request: the persisted query has no offset.
      def library(limit: LIBRARY_LIMIT)
        response = @connection.graphql(LIBRARY_OPERATION,
                                       { "categories" => LIBRARY_CATEGORIES, "limit" => limit },
                                       LIBRARY_HASH)
        titles = response.dig("data", "gameLibraryTitlesRetrieve", "games") || []
        titles.lazy.map { |title| LibraryTitle.from_api(title) }
      end

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
    end
  end
end
