# frozen_string_literal: true

RSpec.describe PSN::GameTitle do
  subject(:title) { described_class.from_api(fixture("game_title")) }

  it "maps Sony's fields to Ruby types" do
    expect(title.name).to eq("ASTRO's PLAYROOM")
    expect(title.title_id).to eq("PPSA01325_00")
    expect(title.platform).to eq("PS5")
    expect(title.play_count).to eq(12)
    expect(title.first_played_at).to eq(Time.utc(2024, 12, 25, 10, 0, 0))
    expect(title.last_played_at).to eq(Time.utc(2025, 6, 1, 18, 30, 0))
  end

  it "parses ISO-8601 play duration into seconds" do
    expect(title.play_duration).to eq((15 * 3600) + (2 * 60) + 32)
  end

  it "keeps the raw hash and tolerates missing fields" do
    expect(title.raw["imageUrl"]).to include("playstation")
    sparse = described_class.from_api({ "titleId" => "X" })
    expect(sparse.name).to be_nil
    expect(sparse.play_duration).to be_nil
  end

  it "passes unknown categories through as-is" do
    weird = described_class.from_api({ "category" => "unknown_thing" })
    expect(weird.platform).to eq("unknown_thing")
  end
end
