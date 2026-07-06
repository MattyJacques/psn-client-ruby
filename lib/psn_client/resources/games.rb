# frozen_string_literal: true

module PSN
  module Resources
    class Games
      TITLES_PATH = "/api/gamelist/v2/users/%s/titles"
      PAGE_SIZE = 200
      # getUserGameList persisted query. Sony can change hash and shape at
      # any time; all knowledge of them is confined to this file. Verify
      # with bin/smoke.
      LIBRARY_OPERATION = "getUserGameList"
      LIBRARY_HASH = "e0136f81d7d1fb6be58238c574e9a46e1c0cc2f7f6977a08a5a46f224523a004"
      LIBRARY_CATEGORIES = "ps4_game,ps5_native_game"
      LIBRARY_LIMIT = 200

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
    end
  end
end
