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

  describe PSN::TitleTrophySummary do
    subject(:summary) { described_class.from_api(fixture("title_trophy_summary")) }

    it "maps the title ID and nested trophy titles" do
      expect(summary.np_title_id).to eq("PPSA01325_00")
      expect(summary.trophy_titles.size).to eq(1)
      expect(summary.trophy_titles.first).to be_a(PSN::TrophyTitle)
      expect(summary.trophy_titles.first.np_communication_id).to eq("NPWR20188_00")
      expect(summary.trophy_titles.first.progress).to eq(71)
    end

    it "maps a title with no trophy sets to an empty array" do
      none = described_class.from_api(fixture("title_trophy_summary").merge("trophyTitles" => []))
      expect(none.trophy_titles).to eq([])
    end
  end

  describe PSN::TrophyGroup do
    subject(:group) do
      described_class.from_api(fixture("trophy_group_definition").merge(fixture("trophy_group_earned")))
    end

    it "maps merged definition and earned fields" do
      expect(group.group_id).to eq("default")
      expect(group.name).to eq("ASTRO's PLAYROOM")
      expect(group.icon_url).to match(%r{^https://})
      expect(group.defined_counts).to eq(bronze: 24, silver: 12, gold: 6, platinum: 1)
      expect(group.earned_counts).to eq(bronze: 20, silver: 8, gold: 2, platinum: 0)
      expect(group.progress).to eq(83)
    end

    it "leaves earned fields nil when only the definition is present" do
      definition_only = described_class.from_api(fixture("trophy_group_definition"))
      expect(definition_only.earned_counts).to be_nil
      expect(definition_only.progress).to be_nil
    end
  end
end
