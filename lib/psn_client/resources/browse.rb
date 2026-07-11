# frozen_string_literal: true

module PSN
  module Resources
    # The store's EMS (Experience Management System) browse tree, as used by
    # the PlayStation App and web store: experience -> nav tree -> views ->
    # category grids/strands. Undocumented mobile-host persisted queries —
    # operation names, hashes, EMS_CLIENT_ID and variable shapes are confined
    # to this file; all were reverse-engineered and verified live 2026-07-11
    # (recipes in docs/graphql-persisted-queries.md; check with bin/smoke).
    class Browse
      # Sony rejects app-store queries that don't identify as the App.
      HEADERS = { "apollographql-client-name" => "PlayStationApp-Android" }.freeze
      EXPERIENCE_OPERATION = "metGetExperience"
      EXPERIENCE_HASH = "054e61ee68bbeadc21435caebcc4f2bba0919a99b06629d141b0b82dc55f10c4"
      # The web store's EMS client, scraped from store.playstation.com HTML —
      # the server-rendered Apollo cache embeds
      # emsExperienceRetrieve({"clientId": ...}). Sony can rotate it; re-derive
      # by grepping a store page for "emsExperienceRetrieve".
      EMS_CLIENT_ID = "b6de8d4d-bf9b-11ee-ad2a-aea73dc1ea43"

      def initialize(connection)
        @connection = connection
      end

      # The store navigation root: nav items pointing at view collections.
      def experience(client_id: EMS_CLIENT_ID)
        response = graphql(EXPERIENCE_OPERATION, { "clientId" => client_id }, EXPERIENCE_HASH)
        StoreExperience.from_api(response.dig("data", "emsExperienceRetrieve") || {})
      end

      private

      def graphql(operation, variables, hash)
        @connection.graphql(operation, variables, hash, host: :mobile, headers: HEADERS)
      end
    end
  end
end
