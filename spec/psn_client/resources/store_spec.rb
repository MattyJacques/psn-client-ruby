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
    it "walks offset pages and maps Entitlement objects" do
      allow(connection).to receive(:get)
        .with(:web, "/api/entitlements/v2/users/me/internal_entitlements",
              { "limit" => 50, "offset" => 0 })
        .and_return({ "entitlements" => [fixture("entitlement")], "total_results" => 1 })

      result = store.entitlements.to_a
      expect(result.size).to eq(1)
      expect(result.first).to be_a(PSN::Entitlement)
      expect(result.first.name).to eq("ASTRO's PLAYROOM")
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
