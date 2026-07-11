# frozen_string_literal: true

RSpec.describe PSN::Resources::Profiles do
  subject(:profiles) { described_class.new(connection, users) }

  let(:connection) { instance_double(PSN::Connection) }
  let(:users) { instance_double(PSN::Resources::Users) }

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

  it "resolves and memoizes the own online ID via account ID for the authenticated account" do
    allow(connection).to receive(:get).with(:dms, "/api/v1/devices/accounts/me", {})
                                      .and_return({ "accountId" => "7077443169688056897" })
    allow(connection).to receive(:get)
      .with(:mobile, "/api/userProfile/v1/internal/users/7077443169688056897/profiles", {})
      .and_return({ "onlineId" => "MattyJ" })
    allow(connection).to receive(:get)
      .with(:community, "/userProfile/v1/users/MattyJ/profile2", anything)
      .and_return({ "profile" => fixture("profile") })

    2.times { expect(profiles.find.online_id).to eq("MattyJ") }
    expect(connection).to have_received(:get).with(:dms, "/api/v1/devices/accounts/me", {}).once
    expect(connection).to have_received(:get)
      .with(:community, "/userProfile/v1/users/MattyJ/profile2", anything).twice
  end

  it "raises ArgumentError for an online ID with a path-breaking character and makes no HTTP call" do
    allow(connection).to receive(:get)

    expect { profiles.find("bad/id") }.to raise_error(ArgumentError, /invalid PSN online ID/)
    expect(connection).not_to have_received(:get)
  end

  it "raises ArgumentError for an online ID shorter than the minimum length" do
    allow(connection).to receive(:get)

    expect { profiles.find("ab") }.to raise_error(ArgumentError, /invalid PSN online ID/)
    expect(connection).not_to have_received(:get)
  end

  it "accepts a valid online ID containing letters, digits, hyphen and underscore" do
    allow(connection).to receive(:get)
      .with(:community, "/userProfile/v1/users/a_b-1/profile2",
            { "fields" => described_class::PROFILE2_FIELDS })
      .and_return({ "profile" => fixture("profile") })

    expect { profiles.find("a_b-1") }.not_to raise_error
  end

  describe "#shareable_link" do
    it "resolves the own account ID via DMS and fetches the cpss share link" do
      allow(connection).to receive(:get).with(:dms, "/api/v1/devices/accounts/me", {})
                                        .and_return({ "accountId" => "7077443169688056897" })
      allow(connection).to receive(:get)
        .with(:mobile, "/api/cpss/v1/share/profile/7077443169688056897", {})
        .and_return({ "shareUrl" => "https://profile.playstation.com/x/abc",
                      "shareImageUrl" => "https://image/qr.png",
                      "shareImageUrlDestination" => "https://profile.playstation.com/abc" })

      link = profiles.shareable_link
      expect(link).to be_a(PSN::ShareableLink)
      expect(link.url).to eq("https://profile.playstation.com/x/abc")
      expect(link.image_url).to eq("https://image/qr.png")
      expect(link.destination).to eq("https://profile.playstation.com/abc")
    end

    it "resolves another user's account ID without touching DMS" do
      allow(users).to receive(:account_id).with("friend").and_return("42")
      allow(connection).to receive(:get)
        .with(:mobile, "/api/cpss/v1/share/profile/42", {})
        .and_return({ "shareUrl" => "u", "shareImageUrl" => "i", "shareImageUrlDestination" => "d" })

      expect(profiles.shareable_link("friend").url).to eq("u")
      expect(connection).not_to have_received(:get).with(:dms, anything, anything)
    end

    it "memoizes the own account ID across calls" do
      allow(connection).to receive(:get).with(:dms, "/api/v1/devices/accounts/me", {})
                                        .and_return({ "accountId" => "7" })
      allow(connection).to receive(:get)
        .with(:mobile, "/api/cpss/v1/share/profile/7", {})
        .and_return({ "shareUrl" => "u", "shareImageUrl" => "i", "shareImageUrlDestination" => "d" })

      2.times { profiles.shareable_link }
      expect(connection).to have_received(:get).with(:dms, "/api/v1/devices/accounts/me", {}).once
    end
  end

  describe "#find_by_account_id" do
    it "returns a BasicProfile from the internal profiles endpoint" do
      allow(connection).to receive(:get)
        .with(:mobile, "/api/userProfile/v1/internal/users/1234567890/profiles", {})
        .and_return(fixture("basic_profile"))

      profile = profiles.find_by_account_id("1234567890")
      expect(profile).to be_a(PSN::BasicProfile)
      expect(profile.online_id).to eq("Example-Player")
      expect(profile.first_name).to eq("Ex")
      expect(profile).to be_plus
      expect(profile).not_to be_me
    end

    it "maps avatars into a size-keyed URL hash" do
      allow(connection).to receive(:get).and_return(fixture("basic_profile"))

      profile = profiles.find_by_account_id("1234567890")
      expect(profile.avatar_urls["xl"]).to eq("http://img.example.com/avatar_xl.png")
    end

    it "handles profiles without personalDetail" do
      allow(connection).to receive(:get)
        .and_return(fixture("basic_profile").except("personalDetail"))

      expect(profiles.find_by_account_id("1234567890").first_name).to be_nil
    end
  end
end
