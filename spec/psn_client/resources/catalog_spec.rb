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

    it "returns a hollow model for an unknown product" do
      allow(connection).to receive(:graphql).and_return({ "data" => { "productRetrieve" => nil } })

      product = catalog.product(product_id)
      expect(product).to be_a(PSN::StoreProduct)
      expect(product.name).to be_nil
      expect(product.raw).to eq({})
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

    it "returns a hollow model for an unknown concept" do
      allow(connection).to receive(:graphql).and_return({ "data" => { "conceptRetrieve" => nil } })

      concept = catalog.concept(10_015_869)
      expect(concept).to be_a(PSN::StoreConcept)
      expect(concept.name).to be_nil
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

    it "returns nil when the product has no ratings" do
      allow(connection).to receive(:graphql)
        .and_return({ "data" => { "productRetrieve" => { "starRating" => nil } } })
      expect(catalog.product_rating(product_id)).to be_nil
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

  describe "#add_ons" do
    it "walks offset pages of add-on products" do
      page = { "addOnProducts" => [fixture("catalog_product")], "pageInfo" => { "totalCount" => 1 } }
      allow(connection).to receive(:graphql)
        .with("metGetAddOnsByTitleId",
              { "npTitleId" => "PPSA31381_00", "pageArgs" => { "size" => 50, "offset" => 0 } },
              described_class::ADD_ONS_HASH, host: :web)
        .and_return({ "data" => { "addOnProductsByTitleIdRetrieve" => page } })

      result = catalog.add_ons("PPSA31381_00").to_a
      expect(result.size).to eq(1)
      expect(result.first).to be_a(PSN::CatalogItem)
    end

    it "is lazy: .first(1) only issues one request" do
      page = { "addOnProducts" => [fixture("catalog_product")], "pageInfo" => { "totalCount" => 51 } }
      allow(connection).to receive(:graphql)
        .with("metGetAddOnsByTitleId",
              { "npTitleId" => "PPSA31381_00", "pageArgs" => { "size" => 50, "offset" => 0 } },
              described_class::ADD_ONS_HASH, host: :web)
        .and_return({ "data" => { "addOnProductsByTitleIdRetrieve" => page } })

      expect(catalog.add_ons("PPSA31381_00").first(1).size).to eq(1)
      expect(connection).to have_received(:graphql).once
    end
  end

  describe "#category" do
    let(:grid_variables) do
      { "id" => described_class::CATEGORIES[:ps5_games],
        "pageArgs" => { "size" => 50, "offset" => 0 },
        "sortBy" => { "name" => "productReleaseDate", "isAscending" => false },
        "filterBy" => [], "facetOptions" => [] }
    end

    it "accepts a category symbol and maps grid products" do
      grid = { "products" => [fixture("catalog_product")], "pageInfo" => { "totalCount" => 1 } }
      allow(connection).to receive(:graphql)
        .with("categoryGridRetrieve", grid_variables, described_class::CATEGORY_HASH, host: :web)
        .and_return({ "data" => { "categoryGridRetrieve" => grid } })

      result = catalog.category(:ps5_games).to_a
      expect(result.size).to eq(1)
      expect(result.first.name).to eq("Fable Standard Edition")
    end

    it "passes raw category UUIDs through and rejects unknown symbols" do
      empty_grid = { "products" => [], "pageInfo" => { "totalCount" => 0 } }
      allow(connection).to receive(:graphql)
        .with("categoryGridRetrieve", hash_including("id" => "some-uuid"),
              described_class::CATEGORY_HASH, host: :web)
        .and_return({ "data" => { "categoryGridRetrieve" => empty_grid } })

      expect(catalog.category("some-uuid").to_a).to eq([])
      expect { catalog.category(:nope).to_a }.to raise_error(KeyError)
    end

    it "is lazy: .first(1) only issues one request" do
      grid = { "products" => [fixture("catalog_product")], "pageInfo" => { "totalCount" => 51 } }
      allow(connection).to receive(:graphql)
        .with("categoryGridRetrieve", grid_variables, described_class::CATEGORY_HASH, host: :web)
        .and_return({ "data" => { "categoryGridRetrieve" => grid } })

      expect(catalog.category(:ps5_games).first(1).size).to eq(1)
      expect(connection).to have_received(:graphql).once
    end
  end

  describe "#content_rating" do
    it "returns the concept-level ContentRating" do
      allow(connection).to receive(:graphql)
        .with("conceptRetrieveForContentRating", { "conceptId" => "10015869" },
              described_class::CONTENT_RATING_HASH, host: :web)
        .and_return({ "data" => { "conceptRetrieve" => { "contentRating" => fixture("content_rating") } } })

      rating = catalog.content_rating(10_015_869)
      expect(rating).to be_a(PSN::ContentRating)
      expect(rating.description).to eq("PEGI 18")
    end

    it "returns nil when the concept has no rating" do
      allow(connection).to receive(:graphql).and_return({ "data" => { "conceptRetrieve" => {} } })
      expect(catalog.content_rating("10015869")).to be_nil
    end
  end

  describe "#media" do
    it "maps the default product's media entries" do
      media = [{ "role" => "SCREENSHOT", "type" => "IMAGE", "url" => "https://x/1.jpg" },
               { "role" => "PREVIEW", "type" => "VIDEO", "url" => "https://x/1.mp4" }]
      allow(connection).to receive(:graphql)
        .with("conceptRetrieveForMedia", { "conceptId" => "10015869" },
              described_class::MEDIA_HASH, host: :web)
        .and_return({ "data" => { "conceptRetrieve" => { "defaultProduct" => { "media" => media } } } })

      result = catalog.media("10015869")
      expect(result.map(&:role)).to eq(%w[SCREENSHOT PREVIEW])
      expect(result.first).to be_a(PSN::MediaItem)
    end

    it "returns an empty array for a concept without a default product" do
      allow(connection).to receive(:graphql).and_return({ "data" => { "conceptRetrieve" => nil } })
      expect(catalog.media("10015869")).to eq([])
    end
  end

  describe "#compatibility_notices" do
    it "returns flattened CompatibilityNotices" do
      allow(connection).to receive(:graphql)
        .with("conceptRetrieveForCompatibilityNotices", { "conceptId" => "10015869" },
              described_class::COMPATIBILITY_HASH, host: :web)
        .and_return({ "data" => { "conceptRetrieve" => fixture("compatibility_concept") } })

      notices = catalog.compatibility_notices("10015869")
      expect(notices.compatibility).to eq([{ platform: "Common", type: "NO_OF_PLAYERS", value: "1" }])
    end

    it "returns an empty model for an unknown concept" do
      allow(connection).to receive(:graphql).and_return({ "data" => { "conceptRetrieve" => nil } })
      expect(catalog.compatibility_notices("10015869").compatibility).to eq([])
    end
  end

  describe "#legal_text" do
    it "returns the default product's LegalText" do
      allow(connection).to receive(:graphql)
        .with("wcaConceptRetrieveForLegalText", { "conceptId" => "10015869" },
              described_class::LEGAL_HASH, host: :web)
        .and_return({ "data" => { "conceptRetrieve" => { "defaultProduct" => fixture("legal_product") } } })

      legal = catalog.legal_text("10015869")
      expect(legal.publisher).to eq("Microsoft Corporation")
      expect(legal.notices.first[:sub_type]).to eq("SCEE_TOS")
    end

    it "returns an empty model for an unknown concept" do
      allow(connection).to receive(:graphql).and_return({ "data" => { "conceptRetrieve" => nil } })
      expect(catalog.legal_text("10015869").notices).to eq([])
    end
  end

  describe "#editions" do
    it "maps each product to an Edition" do
      response = { "data" => { "conceptRetrieve" => { "products" => [fixture("edition_product")] } } }
      allow(connection).to receive(:graphql)
        .with("conceptRetrieveForCtasWithPrice", { "conceptId" => "10015869" },
              described_class::EDITIONS_HASH, host: :web)
        .and_return(response)

      editions = catalog.editions("10015869")
      expect(editions.map(&:name)).to eq(["Fable Standard Edition"])
      expect(editions.first.price.base_price).to eq("£59.99")
    end

    it "returns an empty array for an unknown concept" do
      allow(connection).to receive(:graphql).and_return({ "data" => { "conceptRetrieve" => nil } })
      expect(catalog.editions("10015869")).to eq([])
    end
  end

  describe "#concept_for_product" do
    it "resolves a product to its StoreConcept in one request" do
      allow(connection).to receive(:graphql)
        .with("metGetConceptByProductIdQuery", { "productId" => product_id },
              described_class::CONCEPT_BY_PRODUCT_HASH, host: :web)
        .and_return({ "data" => { "productRetrieve" => { "concept" => fixture("store_concept") } } })

      concept = catalog.concept_for_product(product_id)
      expect(concept).to be_a(PSN::StoreConcept)
      expect(concept.name).to eq("Fable")
    end

    it "returns a hollow model for an unknown product" do
      allow(connection).to receive(:graphql).and_return({ "data" => { "productRetrieve" => nil } })

      concept = catalog.concept_for_product(product_id)
      expect(concept.name).to be_nil
      expect(concept.raw).to eq({})
    end
  end

  describe "#add_ons_by_concept" do
    let(:full_page) { { "data" => { "addOnProductsRetrieve" => { "addOnProducts" => [fixture("catalog_product")] } } } }
    let(:empty_page) { { "data" => { "addOnProductsRetrieve" => { "addOnProducts" => [] } } } }

    def stub_page(offset, response)
      allow(connection).to receive(:graphql)
        .with("getAddOnProductsByConcept",
              { "conceptId" => "229601", "pageArgs" => { "size" => 50, "offset" => offset } },
              described_class::CONCEPT_ADD_ONS_HASH, host: :web)
        .and_return(response)
    end

    it "pages until an empty page (response has no total count)" do
      stub_page(0, full_page)
      stub_page(1, empty_page)

      result = catalog.add_ons_by_concept(229_601).to_a
      expect(result.size).to eq(1)
      expect(result.first).to be_a(PSN::CatalogItem)
      expect(connection).to have_received(:graphql).twice
    end

    it "is lazy: .first(1) only issues one request" do
      stub_page(0, full_page)

      expect(catalog.add_ons_by_concept("229601").first(1).size).to eq(1)
      expect(connection).to have_received(:graphql).once
    end
  end

  describe "#plus_offers" do
    it "maps tier symbols to Sony tier labels and returns PlusOffers" do
      response = { "data" => { "tierSelectorOffersRetrieve" => { "offers" => [fixture("plus_offer")] } } }
      allow(connection).to receive(:graphql)
        .with("featuresRetrieve", { "tierLabel" => "TIER_20" },
              described_class::PLUS_OFFERS_HASH, host: :web)
        .and_return(response)

      offers = catalog.plus_offers(:extra)
      expect(offers.first).to be_a(PSN::PlusOffer)
      expect(offers.first.title).to eq("1 Month Subscription")
    end

    it "defaults to the essential tier and rejects unknown tiers" do
      response = { "data" => { "tierSelectorOffersRetrieve" => { "offers" => [] } } }
      allow(connection).to receive(:graphql)
        .with("featuresRetrieve", { "tierLabel" => "TIER_10" },
              described_class::PLUS_OFFERS_HASH, host: :web)
        .and_return(response)

      expect(catalog.plus_offers).to eq([])
      expect { catalog.plus_offers(:mega) }.to raise_error(KeyError)
    end
  end

  describe "#concept_for_title" do
    it "returns the raw mobile catalog body (provisional mapping)" do
      # Real responses are a top-level array of concepts (verified live 2026-07-10).
      body = [{ "id" => 10_015_869, "nameEn" => "ASTRO BOT", "titleIds" => %w[PPSA01325_00] }]
      allow(connection).to receive(:get)
        .with(:mobile, "/api/catalog/v2/titles/CUSA01433_00/concepts", {})
        .and_return(body)

      expect(catalog.concept_for_title("CUSA01433_00")).to eq(body)
    end
  end
end
