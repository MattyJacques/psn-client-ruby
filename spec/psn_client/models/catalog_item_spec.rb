# frozen_string_literal: true

RSpec.describe PSN::CatalogItem do
  it "maps a released Product card" do
    item = described_class.from_api(fixture("catalog_product"))
    expect(item.name).to eq("Fable Standard Edition")
    expect(item.np_title_id).to eq("PPSA31381_00")
    expect(item.platforms).to eq(["PS5"])
    expect(item).not_to be_concept
    expect(item.classification).to eq("FULL_GAME")
  end

  it "prefers cover art for image_url and maps the price" do
    item = described_class.from_api(fixture("catalog_product"))
    expect(item.image_url).to eq("https://image.api.playstation.com/vulcan/ap/rnd/202605/2823/cover.png")
    expect(item.price).to be_a(PSN::Price)
    expect(item.price.base_price).to eq("$69.99")
    expect(item.raw).to eq(fixture("catalog_product"))
  end

  it "maps an unreleased Concept card with no price" do
    item = described_class.from_api(fixture("catalog_concept"))
    expect(item).to be_concept
    expect(item.price).to be_nil
    expect(item.image_url).to be_nil
    expect(item.platforms).to eq([])
  end

  it "falls back to the first image when there is no cover art" do
    media = [{ "role" => "SCREENSHOT", "type" => "IMAGE", "url" => "https://img/s.png" }]
    item = described_class.from_api(fixture("catalog_concept").merge("media" => media))
    expect(item.image_url).to eq("https://img/s.png")
  end
end
