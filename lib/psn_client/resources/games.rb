# frozen_string_literal: true

module PSN
  module Resources
    class Games
      TITLES_PATH = "/api/gamelist/v2/users/%s/titles"
      PAGE_SIZE = 200

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
    end
  end
end
