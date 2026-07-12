# frozen_string_literal: true

module PSN
  module Resources
    # Game and player search via the PlayStation App's persisted GraphQL
    # queries. Sony does not document these; operation names, hashes and
    # response keys are confined to this file (verify with bin/smoke).
    # The first page comes from the "context" (universal) search and
    # follow-up pages from the "domain" search — separate persisted
    # documents, each with its own hash per context.
    class Search
      CONTEXT_OPERATION = "metGetContextSearchResults"
      DOMAIN_OPERATION = "metGetDomainSearchResults"
      GAMES_CONTEXT = "MobileUniversalSearchGame"
      GAMES_CONTEXT_HASH = "a2fbc15433b37ca7bfcd7112f741735e13268f5e9ebd5ffce51b85acc126f41d"
      GAMES_DOMAIN_HASH = "b51624299bd17b3799f77c9f097cc8887a04d3873f0329095976a841595bc902"
      USERS_CONTEXT = "MobileUniversalSearchSocial"
      USERS_CONTEXT_HASH = "ac5fb2b82c4d086ca0d272fba34418ab327a7762dd2cd620e63f175bbc5aff10"
      USERS_DOMAIN_HASH = "23ece284bf8bdc50bfa30a4d97fd4d733e723beb7a42dff8c1ee883f8461a2e1"
      GAME_DOMAINS = { full_games: "MobileGames", add_ons: "MobileAddOns" }.freeze
      USERS_DOMAIN = "SocialAllAccounts"
      PAGE_SIZE = 20
      # The PlayStation App identifies itself on search requests.
      HEADERS = { "apollographql-client-name" => "PlayStationApp-Android" }.freeze
      # Per-context bundle of the persisted-query hashes and context name, so
      # result_items only threads one keyword through. The games domain query
      # rejects displayTitleLocale while the users one requires it (mirrors
      # the app's persisted documents) — hence locale_in_domain. The locale
      # itself comes from Connection#language.
      GAMES_QUERIES = { context: GAMES_CONTEXT, context_hash: GAMES_CONTEXT_HASH,
                        domain_hash: GAMES_DOMAIN_HASH, locale_in_domain: false }.freeze
      USERS_QUERIES = { context: USERS_CONTEXT, context_hash: USERS_CONTEXT_HASH,
                        domain_hash: USERS_DOMAIN_HASH, locale_in_domain: true }.freeze

      def initialize(connection)
        @connection = connection
      end

      # Store search. domain: :full_games or :add_ons.
      def games(term, domain: :full_games)
        items = result_items(term, domain: GAME_DOMAINS.fetch(domain), queries: GAMES_QUERIES)
        items.map { |item| CatalogItem.from_api(item["result"] || {}) }
      end

      # Player search by online ID or display name.
      def users(term)
        items = result_items(term, domain: USERS_DOMAIN, queries: USERS_QUERIES)
        items.map { |item| UserSearchResult.from_api(item["result"] || {}) }
      end

      private

      # Paginator.cursor tracks the running offset inside the enumerator, so
      # re-enumerating restarts cleanly from the context page at offset 0.
      def result_items(term, domain:, queries:)
        Paginator.cursor do |cursor, offset|
          if cursor.nil?
            context_page(term, domain, queries)
          else
            domain_page(term, domain, queries, cursor, offset)
          end
        end
      end

      def context_page(term, domain, queries)
        variables = { "searchTerm" => term, "searchContext" => queries.fetch(:context),
                      "displayTitleLocale" => @connection.language }
        response = @connection.graphql(CONTEXT_OPERATION, variables, queries.fetch(:context_hash), headers: HEADERS)
        results = response.dig("data", "universalContextSearch", "results") || []
        page = results.find { |r| r["domain"] == domain } || {}
        [page["searchResults"] || [], page["next"]]
      end

      def domain_page(term, domain, queries, cursor, offset)
        variables = { "searchTerm" => term, "searchDomain" => domain,
                      "pageSize" => PAGE_SIZE, "pageOffset" => offset,
                      "nextCursor" => cursor }
        variables["displayTitleLocale"] = @connection.language if queries.fetch(:locale_in_domain)
        response = @connection.graphql(DOMAIN_OPERATION, variables, queries.fetch(:domain_hash), headers: HEADERS)
        page = response.dig("data", "universalDomainSearch") || {}
        [page["searchResults"] || [], page["next"]]
      end
    end
  end
end
