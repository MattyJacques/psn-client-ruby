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
end
