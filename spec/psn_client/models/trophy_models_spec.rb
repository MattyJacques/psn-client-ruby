# frozen_string_literal: true

RSpec.describe "trophy models" do
  describe PSN::TrophyTitle do
    subject(:title) { described_class.from_api(fixture("trophy_title")) }

    it "maps title fields and grade counts" do
      expect(title.name).to eq("ASTRO's PLAYROOM")
      expect(title.np_communication_id).to eq("NPWR20188_00")
      expect(title.np_service_name).to eq("trophy2")
      expect(title.platform).to eq("PS5")
      expect(title.progress).to eq(71)
      expect(title.earned_counts).to eq(bronze: 20, silver: 8, gold: 2, platinum: 0)
      expect(title.defined_counts).to eq(bronze: 24, silver: 12, gold: 6, platinum: 1)
    end
  end

  describe PSN::Trophy do
    subject(:trophy) { described_class.from_api(fixture("trophy_merged")) }

    it "maps trophy fields including grade symbol and earned time" do
      expect(trophy.id).to eq(1)
      expect(trophy.name).to eq("One Small Step")
      expect(trophy.detail).to eq("Take your first step.")
      expect(trophy.grade).to eq(:gold)
      expect(trophy.hidden).to be(false)
      expect(trophy.rarity).to eq(42.1)
      expect(trophy).to be_earned
      expect(trophy.earned_at).to eq(Time.utc(2025, 1, 2, 20, 15, 0))
    end

    it "defaults to unearned when earned data is absent" do
      unearned = described_class.from_api(fixture("trophy_merged").except("earned", "earnedDateTime"))
      expect(unearned.earned).to be(false)
      expect(unearned.earned_at).to be_nil
    end
  end

  describe PSN::TrophySummary do
    subject(:summary) { described_class.from_api(fixture("trophy_summary")) }

    it "maps level, tier and counts" do
      expect(summary.level).to eq(401)
      expect(summary.progress).to eq(60)
      expect(summary.tier).to eq(3)
      expect(summary.earned_counts).to eq(bronze: 800, silver: 400, gold: 100, platinum: 10)
    end
  end
end
