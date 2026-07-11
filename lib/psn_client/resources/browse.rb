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
      VIEWS_OPERATION = "metGetViews"
      VIEWS_HASH = "6fd98ff7fecb603006fb5d92db176d5028435be163c8d1ee9f7c598ab4677dd1"
      DEFAULT_VIEW_OPERATION = "metGetDefaultView"
      DEFAULT_VIEW_HASH = "bec1b8a3b0bae8c08e3ce2c7fe2f38a69343434ccfbcdd82cc1f2e44f86b7c40"
      GRID_OPERATION = "metGetCategoryGrid"
      GRID_HASH = "b67a9e4414b80d8d762bf12a588c6125467ae0bb3bbe3cee3f7696c6984f8ef6"
      STRANDS_OPERATION = "metGetCategoryStrands"
      STRANDS_HASH = "55ab5f168bec56f8362b5519f59faaf786d4e1cfeabb8bc969d6a65545e14f4d"
      PAGE_SIZE = 50

      def initialize(connection)
        @connection = connection
      end

      # The store navigation root: nav items pointing at view collections.
      def experience(client_id: EMS_CLIENT_ID)
        response = graphql(EXPERIENCE_OPERATION, { "clientId" => client_id }, EXPERIENCE_HASH)
        StoreExperience.from_api(response.dig("data", "emsExperienceRetrieve") || {})
      end

      # Views by ID within an experience. IDs come from #experience nav items
      # (view_collection_id) or from EMS links in other views.
      def views(view_ids, experience_id:)
        inputs = Array(view_ids).map { |id| { "viewId" => id, "experienceId" => experience_id } }
        response = graphql(VIEWS_OPERATION, { "viewInputs" => inputs }, VIEWS_HASH)
        (response.dig("data", "emsViewsRetrieve") || []).map { |view| StoreView.from_api(view) }
      end

      # A category's default view (header + grid config). localized_key_id values
      # are the localizedName strings EMS links carry ("cat.gma....").
      def default_view(category_id, localized_key_id:, experience_id:)
        variables = { "categoryId" => category_id, "localizedKeyId" => localized_key_id,
                      "experienceId" => experience_id }
        response = graphql(DEFAULT_VIEW_OPERATION, variables, DEFAULT_VIEW_HASH)
        child_views = response.dig("data", "emsDefaultViewRetrieve", "childViews") || []
        child_views.map { |view| StoreView.from_api(view) }
      end

      # Browse a category grid lazily (same category UUIDs as
      # Catalog::CATEGORIES and EMS GRID components). Unlike Catalog#category
      # this is the App's grid, which also serves #facets.
      def grid(category_id)
        paginator = Paginator.offset(page_size: PAGE_SIZE) do |size, offset|
          page = grid_page(category_id, size, offset)
          [page["products"] || [], page.dig("pageInfo", "totalCount")]
        end
        paginator.map { |product| CatalogItem.from_api(product) }
      end

      # A category grid's facet and sorting options (with counts), from a
      # single-item page.
      def facets(category_id)
        GridOptions.from_api(grid_page(category_id, 1, 0))
      end

      # Products in one strand (a curated store row). Strand IDs appear in EMS
      # views and the web store's Apollo cache; there is no discovery endpoint.
      def strand(strand_id, size: 10)
        variables = { "strands" => [{ "id" => strand_id,
                                      "pageArgs" => { "size" => size, "offset" => 0 } }] }
        response = graphql(STRANDS_OPERATION, variables, STRANDS_HASH)
        strand = (response.dig("data", "categoryStrandsRetrieve") || []).first || {}
        (strand["products"] || []).map { |product| CatalogItem.from_api(product) }
      end

      private

      def graphql(operation, variables, hash)
        @connection.graphql(operation, variables, hash, host: :mobile, headers: HEADERS)
      end

      def grid_page(category_id, size, offset)
        response = graphql(GRID_OPERATION,
                           { "id" => category_id, "pageArgs" => { "size" => size, "offset" => offset } },
                           GRID_HASH)
        response.dig("data", "categoryGridRetrieve") || {}
      end
    end
  end
end
