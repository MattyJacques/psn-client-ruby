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

      private

      def graphql(operation, variables, hash)
        @connection.graphql(operation, variables, hash, host: HOST)
      end
    end
  end
end
