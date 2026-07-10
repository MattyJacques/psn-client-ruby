# frozen_string_literal: true

RSpec.describe "store models" do
  describe PSN::Entitlement do
    subject(:entitlement) { described_class.from_api(fixture("entitlement")) }

    it "maps id, name, type, product/title ids and acquisition time" do
      expect(entitlement.id).to eq("EP0000-CUSA00000_00-EXAMPLEGAME00000")
      expect(entitlement.name).to eq("EXAMPLE GAME PS4")
      expect(entitlement.type).to eq("PS4GD")
      expect(entitlement.product_id).to eq("EP0000-CUSA00000_00-0000000000000000")
      expect(entitlement.title_id).to eq("CUSA00000_00")
      expect(entitlement.acquired_at).to eq(Time.utc(2024, 5, 2, 16, 2, 9))
    end

    it "derives the platform from entitlementAttributes[0].platformId" do
      expect(entitlement.platform).to eq("PS4")
    end

    it "maps defensively when fields are missing" do
      minimal = described_class.from_api({ "id" => "x" })
      expect(minimal.id).to eq("x")
      expect(minimal.name).to be_nil
      expect(minimal.type).to be_nil
      expect(minimal.platform).to be_nil
      expect(minimal.product_id).to be_nil
      expect(minimal.title_id).to be_nil
      expect(minimal.acquired_at).to be_nil
    end
  end

  describe PSN::WishlistItem do
    subject(:item) { described_class.from_api(fixture("wishlist_item")) }

    it "maps identity, platforms and artwork" do
      expect(item.name).to eq("Resident Evil 2")
      expect(item.id).to eq("UP0102-PPSA07813_00-CLASSICRE2000001")
      expect(item.platforms).to eq(%w[PS4 PS5])
      expect(item.image_url).to start_with("https://image.api.playstation.com/")
      expect(item).not_to be_concept
    end

    it "maps the store classification in both forms" do
      expect(item.classification).to eq("FULL_GAME")
      expect(item.localized_classification).to eq("Full Game")
    end

    it "flattens the price fields" do
      expect(item.base_price).to eq("£7.99")
      expect(item.discounted_price).to eq("Included")
      expect(item.discount_text).to be_nil
      expect(item.sku_id).to eq("UP0102-PPSA07813_00-CLASSICRE2000001-E001")
      expect(item.service_branding).to eq(["PS_PLUS"])
    end

    it "exposes the price flags as predicates and keeps upsell data" do
      expect(item).to be_free
      expect(item).to be_tied_to_subscription
      expect(item).not_to be_exclusive
      expect(item.upsell_service_branding).to eq(["NONE"])
      expect(item.upsell_text).to be_nil
    end

    it "maps an unreleased concept: no price, empty platforms, nil classification" do
      concept = described_class.from_api(fixture("wishlist_concept"))
      expect(concept).to be_concept
      expect(concept.id).to eq("10015616")
      expect(concept.platforms).to eq([])
      expect(concept.base_price).to be_nil
      expect(concept).not_to be_free
    end

    it "keeps the untouched API hash in raw" do
      expect(item.raw).to eq(fixture("wishlist_item"))
    end
  end
end
