# frozen_string_literal: true

RSpec.describe PSN::Resources::Profiles do
  subject(:profiles) { described_class.new(connection) }

  let(:connection) { instance_double(PSN::Connection) }

  it "fetches a profile by online ID from the community host" do
    allow(connection).to receive(:get)
      .with(:community, "/userProfile/v1/users/MattyJ/profile2",
            { "fields" => described_class::PROFILE2_FIELDS })
      .and_return({ "profile" => fixture("profile") })

    profile = profiles.find("MattyJ")
    expect(profile).to be_a(PSN::Profile)
    expect(profile.online_id).to eq("MattyJ")
    expect(profile.account_id).to eq("1234567890123456789")
  end

  it "resolves and memoizes the own online ID for the authenticated account" do
    allow(connection).to receive(:get)
      .with(:mobile, "/api/userProfile/v1/internal/users/me/profiles", {})
      .and_return({ "onlineId" => "MattyJ" })
    allow(connection).to receive(:get)
      .with(:community, "/userProfile/v1/users/MattyJ/profile2", anything)
      .and_return({ "profile" => fixture("profile") })

    2.times { expect(profiles.find.online_id).to eq("MattyJ") }
    expect(connection).to have_received(:get)
      .with(:mobile, "/api/userProfile/v1/internal/users/me/profiles", {}).once
    expect(connection).to have_received(:get)
      .with(:community, "/userProfile/v1/users/MattyJ/profile2", anything).twice
  end
end
