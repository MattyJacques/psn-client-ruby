# frozen_string_literal: true

RSpec.describe PSN::StoreConcept do
  it "maps the concept detail shape including the object-wrapped release date" do
    concept = described_class.from_api(fixture("store_concept"))
    expect(concept.name).to eq("Fable")
    expect(concept.publisher).to eq("Microsoft Corporation")
    expect(concept.release_date).to eq(Time.iso8601("2027-02-23T16:00:00Z"))
    expect(concept.genres).to eq(["Adventure"])
    expect(concept.description).to eq("Fable is an action RPG set in Albion.")
  end

  it "maps the default product as a CatalogItem" do
    concept = described_class.from_api(fixture("store_concept"))
    expect(concept.default_product).to be_a(PSN::CatalogItem)
    expect(concept.default_product.name).to eq("Fable Standard Edition")
    expect(concept.image_url).to eq("https://image.api.playstation.com/vulcan/concept.png")
    expect(concept.raw).to eq(fixture("store_concept"))
  end

  it "tolerates an empty payload" do
    empty = described_class.from_api({})
    expect(empty.default_product).to be_nil
    expect(empty.release_date).to be_nil
  end
end
