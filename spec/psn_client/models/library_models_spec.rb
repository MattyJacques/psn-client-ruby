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

  describe PSN::PurchasedGame do
    subject(:game) { described_class.from_api(fixture("purchased_game")) }

    it "maps purchased game fields" do
      expect(game.name).to eq("Ghost of Tsushima")
      expect(game.title_id).to eq("CUSA13323_00")
      expect(game.platform).to eq("PS4")
      expect(game.concept_id).to eq("232076")
      expect(game.entitlement_id).to eq("PUR-ENTITLEMENT-1")
      expect(game.product_id).to eq("EP9000-CUSA13323_00-GHOSTSHIP0000000")
      expect(game.image_url).to eq("https://image.api.playstation.com/ghost.png")
      expect(game.membership).to eq("NONE")
      expect(game).to be_active
      expect(game).to be_downloadable
      expect(game).not_to be_pre_order
    end
  end
end
