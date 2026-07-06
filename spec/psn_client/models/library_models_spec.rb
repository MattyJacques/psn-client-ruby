# frozen_string_literal: true

RSpec.describe "library models" do
  describe PSN::LibraryTitle do
    subject(:title) { described_class.from_api(fixture("library_title")) }

    it "maps library title fields" do
      expect(title.name).to eq("ASTRO's PLAYROOM")
      expect(title.title_id).to eq("PPSA01325_00")
      expect(title.platform).to eq("PS5")
      expect(title.concept_id).to eq("10000237")
      expect(title.entitlement_id).to eq("LIB-ENTITLEMENT-1")
      expect(title.product_id).to eq("UP9000-PPSA01325_00-0000000000000000")
      expect(title.image_url).to eq("https://image.api.playstation.com/astro.png")
      expect(title.last_played_at).to eq(Time.utc(2026, 6, 30, 18, 0, 0))
      expect(title).to be_active
    end

    it "maps subscriptionService NONE to nil and keeps real services" do
      expect(title.subscription_service).to be_nil
      plus = described_class.from_api(fixture("library_title").merge("subscriptionService" => "PS_PLUS"))
      expect(plus.subscription_service).to eq("PS_PLUS")
    end
  end
end
