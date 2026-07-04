# frozen_string_literal: true

RSpec.describe PSN::Error do
  it "exposes the response" do
    error = PSN::PrivacyError.new("blocked", response: { status: 403, body: "x" })
    expect(error).to be_a(described_class)
    expect(error.message).to eq("blocked")
    expect(error.response).to eq(status: 403, body: "x")
  end

  it "defines the hierarchy" do
    expect(PSN::AuthenticationError.ancestors).to include(described_class)
    expect(PSN::NotFoundError.ancestors).to include(described_class)
    expect(PSN::APIError.ancestors).to include(described_class)
  end

  it "carries retry_after on RateLimitError" do
    error = PSN::RateLimitError.new("slow down", retry_after: 30)
    expect(error.retry_after).to eq(30)
    expect(error.response).to be_nil
  end
end
