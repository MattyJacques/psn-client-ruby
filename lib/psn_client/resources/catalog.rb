# frozen_string_literal: true

module PSN
  module Resources
    # Public store catalog: product/concept detail, pricing, add-ons,
    # category browsing and star ratings. These persisted queries live on
    # the web store's GraphQL host (:web) and need no account context —
    # Sony serves them anonymously. Undocumented; operation names, hashes
    # and response root keys are confined to this file and were verified
    # live 2026-07 (see bin/smoke).
    class Catalog
      HOST = :web
      PRODUCT_OPERATION = "metGetProductById"
      PRODUCT_HASH = "a128042177bd93dd831164103d53b73ef790d56f51dae647064cb8f9d9fc9d1a"
      CONCEPT_OPERATION = "metGetConceptById"
      CONCEPT_HASH = "cc90404ac049d935afbd9968aef523da2b6723abfb9d586e5f77ebf7c5289006"
      PRICING_OPERATION = "metGetPricingDataByConceptId"
      PRICING_HASH = "abcb311ea830e679fe2b697a27f755764535d825b24510ab1239a4ca3092bd09"
      # "Retrive" is Sony's typo, not ours.
      PRODUCT_RATING_OPERATION = "wcaProductStarRatingRetrive"
      PRODUCT_RATING_HASH = "cedd370c39e89da20efa7b2e55710e88cb6e6843cc2f8203f7e73ba4751e7253"
      CONCEPT_RATING_OPERATION = "wcaConceptStarRatingRetrive"
      CONCEPT_RATING_HASH = "e12dc5cef72296a437b4d71e0b130010bf3707ab981b585ba00d1d5773ce2092"
      ADD_ONS_OPERATION = "metGetAddOnsByTitleId"
      ADD_ONS_HASH = "e98d01ff5c1854409a405a5f79b5a9bcd36a5c0679fb33f4e18113c157d4d916"
      CATEGORY_OPERATION = "categoryGridRetrieve"
      CATEGORY_HASH = "4ce7d410a4db2c8b635a48c1dcec375906ff63b19dadd87e073f8fd0c0481d35"
      # Concept detail slices: the web store product page broken into
      # sections. All take {"conceptId" => id} and return under
      # data.conceptRetrieve. Verified live 2026-07-09.
      CONTENT_RATING_OPERATION = "conceptRetrieveForContentRating"
      CONTENT_RATING_HASH = "b504e0bc68af3dc08bc56c0001b27da26ed15d70827420f80805b2d031a95aa8"
      MEDIA_OPERATION = "conceptRetrieveForMedia"
      MEDIA_HASH = "615a2c4618229aa2f11c10fe497eaf4fdc151e4dcc0b6b82e154aeacb0123c2d"
      COMPATIBILITY_OPERATION = "conceptRetrieveForCompatibilityNotices"
      COMPATIBILITY_HASH = "fb1a981a21d7a00ba72bd79d3998044d77207687a5aa1d3a17d90d7b7f3acb05"
      LEGAL_OPERATION = "wcaConceptRetrieveForLegalText"
      LEGAL_HASH = "b4c35dd0b4ec1541041699ac77e0f607d510d9b2b1e4ad9d2e743e1727f5aeb8"
      # Store category UUIDs (from the web store's routes). Any other
      # category UUID string can be passed to #category directly.
      CATEGORIES = {
        ps5_games: "4cbf39e2-5749-4970-ba81-93a489e4570c",
        ps4_games: "44d8bb20-653e-431e-8ad0-c0a365f68d2f",
        ps_plus: "038b4df3-bb4c-48f8-8290-3feb35f0f0fd",
        deals: "803cee19-e5a1-4d59-a463-0b6b2701bf7c",
        free_games: "d9930400-c5c7-4a06-a28d-cc74888426dc",
        new_games: "e1699f77-77e1-43ca-a296-26d08abacb0f"
      }.freeze
      PAGE_SIZE = 50

      def initialize(connection)
        @connection = connection
      end

      # Full detail for a released product ("UP6312-PPSA31381_00-...").
      def product(product_id)
        response = graphql(PRODUCT_OPERATION, { "productId" => product_id }, PRODUCT_HASH)
        StoreProduct.from_api(response.dig("data", "productRetrieve") || {})
      end

      # Full detail for a concept (numeric ID; see StoreProduct#concept_id).
      # The persisted query requires productId to be present but empty.
      def concept(concept_id)
        variables = { "conceptId" => concept_id.to_s, "productId" => "" }
        response = graphql(CONCEPT_OPERATION, variables, CONCEPT_HASH)
        StoreConcept.from_api(response.dig("data", "conceptRetrieve") || {})
      end

      # Current price for a concept's default product, or nil when nothing
      # is purchasable yet.
      def pricing(concept_id)
        response = graphql(PRICING_OPERATION, { "conceptId" => concept_id.to_s }, PRICING_HASH)
        price = response.dig("data", "conceptRetrieve", "defaultProduct", "price")
        price && Price.from_api(price)
      end

      # Star ratings, or nil when the item has none.
      def product_rating(product_id)
        response = graphql(PRODUCT_RATING_OPERATION, { "productId" => product_id }, PRODUCT_RATING_HASH)
        rating = response.dig("data", "productRetrieve", "starRating")
        rating && StarRating.from_api(rating)
      end

      def concept_rating(concept_id)
        response = graphql(CONCEPT_RATING_OPERATION, { "conceptId" => concept_id.to_s }, CONCEPT_RATING_HASH)
        rating = response.dig("data", "conceptRetrieve", "defaultProduct", "starRating")
        rating && StarRating.from_api(rating)
      end

      # Age rating (PEGI/ESRB) for a concept, or nil when it has none.
      def content_rating(concept_id)
        response = graphql(CONTENT_RATING_OPERATION, { "conceptId" => concept_id.to_s }, CONTENT_RATING_HASH)
        rating = response.dig("data", "conceptRetrieve", "contentRating")
        rating && ContentRating.from_api(rating)
      end

      # All art/video assets for a concept's default product.
      def media(concept_id)
        response = graphql(MEDIA_OPERATION, { "conceptId" => concept_id.to_s }, MEDIA_HASH)
        entries = response.dig("data", "conceptRetrieve", "defaultProduct", "media") || []
        entries.map { |entry| MediaItem.from_api(entry) }
      end

      # Play-compatibility and accessibility notices for a concept.
      def compatibility_notices(concept_id)
        response = graphql(COMPATIBILITY_OPERATION, { "conceptId" => concept_id.to_s }, COMPATIBILITY_HASH)
        CompatibilityNotices.from_api(response.dig("data", "conceptRetrieve") || {})
      end

      # Legal notices and privacy policy for a concept's default product.
      def legal_text(concept_id)
        response = graphql(LEGAL_OPERATION, { "conceptId" => concept_id.to_s }, LEGAL_HASH)
        LegalText.from_api(response.dig("data", "conceptRetrieve", "defaultProduct") || {})
      end

      # DLC and add-ons for a title ID ("PPSA31381_00").
      def add_ons(np_title_id)
        paginator = Paginator.offset(page_size: PAGE_SIZE) do |size, offset|
          variables = { "npTitleId" => np_title_id, "pageArgs" => { "size" => size, "offset" => offset } }
          response = graphql(ADD_ONS_OPERATION, variables, ADD_ONS_HASH)
          page = response.dig("data", "addOnProductsByTitleIdRetrieve") || {}
          [page["addOnProducts"] || [], page.dig("pageInfo", "totalCount")]
        end
        paginator.map { |product| CatalogItem.from_api(product) }
      end

      # Browse a store category: a CATEGORIES symbol or any category UUID.
      def category(id, sort: "productReleaseDate", ascending: false)
        category_id = id.is_a?(Symbol) ? CATEGORIES.fetch(id) : id
        paginator = Paginator.offset(page_size: PAGE_SIZE) do |size, offset|
          response = graphql(CATEGORY_OPERATION,
                             category_variables(category_id, size, offset, sort, ascending),
                             CATEGORY_HASH)
          grid = response.dig("data", "categoryGridRetrieve") || {}
          [grid["products"] || [], grid.dig("pageInfo", "totalCount")]
        end
        paginator.map { |product| CatalogItem.from_api(product) }
      end

      private

      def graphql(operation, variables, hash)
        @connection.graphql(operation, variables, hash, host: HOST)
      end

      def category_variables(category_id, size, offset, sort, ascending)
        { "id" => category_id, "pageArgs" => { "size" => size, "offset" => offset },
          "sortBy" => { "name" => sort, "isAscending" => ascending },
          "filterBy" => [], "facetOptions" => [] }
      end
    end
  end
end
