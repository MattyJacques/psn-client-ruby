# frozen_string_literal: true

RSpec.describe PSN::Profile do
  subject(:profile) { described_class.from_api(fixture("profile")) }

  it "maps identity and account fields" do
    expect(profile.online_id).to eq("MattyJ")
    expect(profile.account_id).to eq("1234567890123456789")
    expect(profile.about_me).to eq("Backlog wrangler")
    expect(profile.languages).to eq(["en"])
    expect(profile).to be_plus
    expect(profile).not_to be_verified
  end

  it "picks the largest avatar" do
    expect(profile.avatar_url).to eq("https://static-resource.np.community.playstation.net/avatar_l.png")
  end

  it "maps the trophy summary into TrophySummary" do
    expect(profile.trophy_summary).to be_a(PSN::TrophySummary)
    expect(profile.trophy_summary.level).to eq(421)
    expect(profile.trophy_summary.progress).to eq(37)
    expect(profile.trophy_summary.earned_counts).to eq(bronze: 1204, silver: 320, gold: 89, platinum: 12)
  end

  it "maps presence" do
    expect(profile).not_to be_online
    expect(profile.platform).to eq("PS5")
    expect(profile.last_online_at).to eq(Time.utc(2026, 7, 5, 22, 14, 0))
  end

  it "tolerates missing optional sections" do
    bare = described_class.from_api(fixture("profile").except("trophySummary", "presences", "avatarUrls"))
    expect(bare.trophy_summary).to be_nil
    expect(bare.avatar_url).to be_nil
    expect(bare.online).to be(false)
    expect(bare.platform).to be_nil
  end

  describe "#region" do
    it "extracts the region from a plain-form npId" do
      expect(profile.region).to eq("GB")
    end

    it "extracts the region from a fully base64-encoded npId" do
      hash = fixture("profile").merge("npId" => ["MattyJ@b6.us"].pack("m0"))
      expect(described_class.from_api(hash).region).to eq("US")
    end

    it "is nil when npId is missing" do
      hash = fixture("profile").tap { |h| h.delete("npId") }
      expect(described_class.from_api(hash).region).to be_nil
    end

    it "is nil when the npId does not decode to a two-letter region" do
      hash = fixture("profile").merge("npId" => "garbage")
      expect(described_class.from_api(hash).region).to be_nil
    end
  end
end
