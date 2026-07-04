# frozen_string_literal: true

module PSN
  module Resources
    # Internal: resolves friendly online IDs to Sony's numeric account IDs.
    class Users
      SEARCH_PATH = "/api/search/v1/universalSearch"

      def initialize(connection)
        @connection = connection
        @cache = {}
      end

      def account_id(online_id)
        return "me" if online_id.nil?

        @cache[online_id.downcase] ||= lookup(online_id)
      end

      private

      def lookup(online_id)
        body = { "searchTerm" => online_id, "domainRequests" => [{ "domain" => "SocialAllAccounts" }] }
        results = @connection.post(:mobile, SEARCH_PATH, body).dig("domainResponses", 0, "results") || []
        match = results.find { |r| r.dig("socialMetadata", "onlineId")&.casecmp?(online_id) }
        raise NotFoundError, "no PSN account found with online ID #{online_id.inspect}" unless match

        match.dig("socialMetadata", "accountId")
      end
    end
  end
end
