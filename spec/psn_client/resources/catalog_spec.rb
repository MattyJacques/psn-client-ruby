# frozen_string_literal: true

RSpec.describe PSN::Resources::Catalog do
  subject(:catalog) { described_class.new(connection) }

  let(:connection) { instance_double(PSN::Connection) }
  let(:product_id) { "UP6312-PPSA31381_00-0202050640964065" }

  describe "#product" do
    it "fetches product detail via metGetProductById" do
      allow(connection).to receive(:graphql)
        .with("metGetProductById", { "productId" => product_id },
              described_class::PRODUCT_HASH, host: :web)
        .and_return({ "data" => { "productRetrieve" => fixture("store_product") } })

      product = catalog.product(product_id)
      expect(product).to be_a(PSN::StoreProduct)
      expect(product.name).to eq("Fable Standard Edition")
    end
  end

  describe "#concept" do
    it "fetches concept detail via metGetConceptById (conceptId + empty productId)" do
      allow(connection).to receive(:graphql)
        .with("metGetConceptById", { "conceptId" => "10015869", "productId" => "" },
              described_class::CONCEPT_HASH, host: :web)
        .and_return({ "data" => { "conceptRetrieve" => fixture("store_concept") } })

      expect(catalog.concept(10_015_869).name).to eq("Fable")
    end
  end

  describe "#pricing" do
    it "returns the default product's Price" do
      response = { "data" => { "conceptRetrieve" => { "defaultProduct" => { "price" => fixture("sku_price") } } } }
      allow(connection).to receive(:graphql)
        .with("metGetPricingDataByConceptId", { "conceptId" => "10015869" },
              described_class::PRICING_HASH, host: :web)
        .and_return(response)

      price = catalog.pricing("10015869")
      expect(price).to be_a(PSN::Price)
      expect(price.discounted_price).to eq("$48.99")
    end

    it "returns nil when the concept has no purchasable product" do
      allow(connection).to receive(:graphql).and_return({ "data" => { "conceptRetrieve" => {} } })
      expect(catalog.pricing("10015869")).to be_nil
    end
  end

  describe "#product_rating" do
    it "returns the StarRating via wcaProductStarRatingRetrive" do
      allow(connection).to receive(:graphql)
        .with("wcaProductStarRatingRetrive", { "productId" => product_id },
              described_class::PRODUCT_RATING_HASH, host: :web)
        .and_return({ "data" => { "productRetrieve" => { "starRating" => fixture("star_rating") } } })

      expect(catalog.product_rating(product_id).average).to eq(4.6)
    end
  end

  describe "#concept_rating" do
    it "returns the default product's StarRating" do
      rating = { "defaultProduct" => { "starRating" => fixture("star_rating") } }
      response = { "data" => { "conceptRetrieve" => rating } }
      allow(connection).to receive(:graphql)
        .with("wcaConceptStarRatingRetrive", { "conceptId" => "10015869" },
              described_class::CONCEPT_RATING_HASH, host: :web)
        .and_return(response)

      expect(catalog.concept_rating("10015869").total).to eq(15_382)
    end
  end
end
