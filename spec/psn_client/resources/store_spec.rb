# frozen_string_literal: true

RSpec.describe PSN::Resources::Store do
  subject(:store) { described_class.new(connection) }

  let(:connection) { instance_double(PSN::Connection) }

  describe "#transactions" do
    it "raises APIError without making any HTTP call" do
      allow(connection).to receive(:get)
      expect { store.transactions }.to raise_error(PSN::APIError, /decommissioned/)
      expect(connection).not_to have_received(:get)
    end
  end

  describe "#entitlements" do
    let(:params) do
      { "entitlementType" => "1,2,3,4,5",
        "fields" => "titleMeta,gameMeta,conceptMeta,rewardMeta," \
                    "rewardMeta.retentionPolicy,rewardMeta.rewardMembershipType",
        "gameMetaPackageType" => "PSGD,PS4GD", "limit" => 50, "offset" => 0 }
    end

    it "walks offset pages on the mobile host and maps Entitlement objects" do
      allow(connection).to receive(:get)
        .with(:mobile, "/api/entitlement/v2/users/me/internal/entitlements", params)
        .and_return({ "entitlements" => [fixture("entitlement")], "totalResults" => 1 })

      result = store.entitlements.to_a
      expect(result.size).to eq(1)
      expect(result.first).to be_a(PSN::Entitlement)
      expect(result.first.name).to eq("EXAMPLE GAME PS4")
    end

    it "joins title_ids into the titleId filter param" do
      allow(connection).to receive(:get)
        .with(:mobile, "/api/entitlement/v2/users/me/internal/entitlements",
              params.merge("titleId" => "PPSA01325_00,CUSA13323_00"))
        .and_return({ "entitlements" => [], "totalResults" => 0 })

      expect(store.entitlements(title_ids: %w[PPSA01325_00 CUSA13323_00]).to_a).to eq([])
    end
  end

  describe "#wishlist" do
    it "fetches the wishlist via the metGetStoreWishlist persisted query" do
      response = { "data" => { "storeWishlist" => [fixture("wishlist_item"), fixture("wishlist_concept")] } }
      allow(connection).to receive(:graphql)
        .with("metGetStoreWishlist", {}, PSN::Resources::Store::WISHLIST_HASH)
        .and_return(response)

      result = store.wishlist.to_a
      expect(result.size).to eq(2)
      expect(result.first).to be_a(PSN::WishlistItem)
      expect(result.first.name).to eq("Resident Evil 2")
      expect(result.last).to be_concept
    end

    it "returns a lazy enumerator and defaults to empty when the key is missing" do
      allow(connection).to receive(:graphql)
        .with("metGetStoreWishlist", {}, PSN::Resources::Store::WISHLIST_HASH)
        .and_return({ "data" => {} })

      expect(store.wishlist).to be_a(Enumerator::Lazy)
      expect(store.wishlist.to_a).to eq([])
    end
  end
end
