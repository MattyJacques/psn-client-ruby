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
      LOCALE = "en-US"
      PAGE_SIZE = 20
      # The PlayStation App identifies itself on search requests.
      HEADERS = { "apollographql-client-name" => "PlayStationApp-Android" }.freeze
      # Per-context bundle of the two persisted-query hashes plus the context
      # name, so result_items only needs to thread one keyword through.
      GAMES_QUERIES = { context: GAMES_CONTEXT, context_hash: GAMES_CONTEXT_HASH,
                        domain_hash: GAMES_DOMAIN_HASH }.freeze
      USERS_QUERIES = { context: USERS_CONTEXT, context_hash: USERS_CONTEXT_HASH,
                        domain_hash: USERS_DOMAIN_HASH }.freeze

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
        items = result_items(term, domain: USERS_DOMAIN, queries: USERS_QUERIES,
                                   domain_extras: { "displayTitleLocale" => LOCALE })
        items.map { |item| UserSearchResult.from_api(item["result"] || {}) }
      end

      private

      # The games domain query rejects displayTitleLocale while the users one
      # requires it (mirrors the app's persisted documents) — hence
      # domain_extras rather than always sending it.
      def result_items(term, domain:, queries:, domain_extras: {})
        offset = 0
        Paginator.cursor do |cursor|
          items, next_cursor =
            if cursor.nil?
              context_page(term, domain, queries)
            else
              domain_page(term, domain, queries[:domain_hash], [cursor, offset], domain_extras)
            end
          offset += items.size
          [items, next_cursor]
        end
      end

      def context_page(term, domain, queries)
        variables = { "searchTerm" => term, "searchContext" => queries[:context],
                      "displayTitleLocale" => LOCALE }
        response = @connection.graphql(CONTEXT_OPERATION, variables, queries[:context_hash], headers: HEADERS)
        results = response.dig("data", "universalContextSearch", "results") || []
        page = results.find { |r| r["domain"] == domain } || {}
        [page["searchResults"] || [], page["next"]]
      end

      def domain_page(term, domain, hash, cursor_state, extras)
        cursor, offset = cursor_state
        variables = { "searchTerm" => term, "searchDomain" => domain,
                      "pageSize" => PAGE_SIZE, "pageOffset" => offset,
                      "nextCursor" => cursor }.merge(extras)
        response = @connection.graphql(DOMAIN_OPERATION, variables, hash, headers: HEADERS)
        page = response.dig("data", "universalDomainSearch") || {}
        [page["searchResults"] || [], page["next"]]
      end
    end
  end
end
