# frozen_string_literal: true

RSpec.describe PSN::StarRating do
  it "maps average, total and the distribution by star count" do
    rating = described_class.from_api(fixture("star_rating"))
    expect(rating.average).to eq(4.6)
    expect(rating.average_display).to eq("4.60")
    expect(rating.total).to eq(15_382)
    expect(rating.distribution).to eq({ 5 => 78.1, 4 => 12.0, 3 => 5.0, 2 => 2.0, 1 => 2.9 })
    expect(rating.raw).to eq(fixture("star_rating"))
  end

  it "tolerates an empty payload" do
    rating = described_class.from_api({})
    expect(rating.distribution).to eq({})
  end
end
