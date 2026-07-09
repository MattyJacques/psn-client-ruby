# frozen_string_literal: true

RSpec.describe "store models" do
  describe PSN::Transaction do
    subject(:transaction) { described_class.from_api(fixture("transaction")) }

    it "maps id, date, type and payment method" do
      expect(transaction.transaction_id).to eq("1234567890123456789")
      expect(transaction.date).to eq(Time.utc(2025, 5, 20, 14, 3, 0))
      expect(transaction.type).to eq("PURCHASE")
      expect(transaction.payment_method).to eq("Visa **** 1234")
    end

    it "represents money as integer minor units plus currency" do
      expect(transaction.amount).to eq(6999)
      expect(transaction.amount).to be_an(Integer)
      expect(transaction.currency).to eq("GBP")
    end

    it "describes the transaction from its items" do
      expect(transaction.description).to eq("Stellar Blade")
    end

    it "survives a completely different shape via raw" do
      sparse = described_class.from_api({ "orderId" => "X-1" })
      expect(sparse.transaction_id).to eq("X-1")
      expect(sparse.amount).to be_nil
      expect(sparse.raw).to eq("orderId" => "X-1")
    end
  end

  describe PSN::Entitlement do
    subject(:entitlement) { described_class.from_api(fixture("entitlement")) }

    it "maps id, name, type and acquisition time" do
      expect(entitlement.id).to eq("UP9000-PPSA01325_00-GAME000000000000")
      expect(entitlement.name).to eq("ASTRO's PLAYROOM")
      expect(entitlement.type).to eq("PS5GD")
      expect(entitlement.acquired_at).to eq(Time.utc(2024, 12, 25, 9, 58, 0))
    end

    it "derives the platform from the entitlement type" do
      expect(entitlement.platform).to eq("PS5")
      vita = described_class.from_api({ "game_meta" => { "type" => "VITAGD" } })
      expect(vita.platform).to eq("VITA")
      unknown = described_class.from_api({ "game_meta" => { "type" => "SUBSCRIPTION" } })
      expect(unknown.platform).to be_nil
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
