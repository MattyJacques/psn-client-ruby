# frozen_string_literal: true

RSpec.describe PSN::Price do
  it "maps the SkuPrice shape" do
    price = described_class.from_api(fixture("sku_price"))
    expect(price.base_price).to eq("$69.99")
    expect(price.discounted_price).to eq("$48.99")
    expect(price.discounted_value).to eq(4899)
    expect(price.currency_code).to eq("USD")
    expect(price.end_time).to eq(Time.iso8601("2026-07-23T14:59:00Z"))
  end

  it "answers the predicates" do
    price = described_class.from_api(fixture("sku_price"))
    expect(price).to be_discounted
    expect(price).not_to be_free
    expect(price).not_to be_tied_to_subscription
    expect(price).not_to be_exclusive
    expect(price.raw).to eq(fixture("sku_price"))
  end

  it "is not discounted when values match and tolerates missing keys" do
    price = described_class.from_api({})
    expect(price).not_to be_discounted
    expect(price.end_time).to be_nil
    matching = described_class.from_api({ "basePriceValue" => 6999, "discountedValue" => 6999 })
    expect(matching).not_to be_discounted
  end
end
