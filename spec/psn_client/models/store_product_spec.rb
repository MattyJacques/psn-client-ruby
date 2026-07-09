# frozen_string_literal: true

RSpec.describe PSN::StoreProduct do
  it "maps the product detail shape" do
    product = described_class.from_api(fixture("store_product"))
    expect(product.name).to eq("Fable Standard Edition")
    expect(product.np_title_id).to eq("PPSA31381_00")
    expect(product.publisher).to eq("Microsoft Corporation")
    expect(product.release_date).to eq(Time.iso8601("2027-02-23T16:00:00Z"))
    expect(product.concept_id).to eq("10015869")
    expect(product.platforms).to eq(["PS5"])
    expect(product.invariant_name).to eq("Fable Standard Edition")
  end

  it "maps genres, descriptions, edition, rating and image" do
    product = described_class.from_api(fixture("store_product"))
    expect(product.genres).to eq(%w[Adventure Fantasy])
    expect(product.short_description).to eq("A hero returns.")
    expect(product.description).to eq("Fable is an action RPG set in Albion.")
    expect(product.edition).to eq("Fable Standard Edition")
    expect(product.content_rating).to eq("ESRB Mature 17+")
  end

  it "maps classification and image fields" do
    product = described_class.from_api(fixture("store_product"))
    expect(product.classification).to eq("FULL_GAME")
    expect(product.localized_classification).to eq("Full Game")
    expect(product.image_url).to eq("https://image.api.playstation.com/vulcan/cover.png")
  end

  it "keeps raw and tolerates an empty payload" do
    expect(described_class.from_api(fixture("store_product")).raw).to eq(fixture("store_product"))
    empty = described_class.from_api({})
    expect(empty.release_date).to be_nil
    expect(empty.genres).to eq([])
    expect(empty.description).to be_nil
  end
end
