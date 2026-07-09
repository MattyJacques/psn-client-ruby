# frozen_string_literal: true

RSpec.describe PSN::UserSearchResult do
  it "maps the Player shape" do
    user = described_class.from_api(fixture("user_search_player"))
    expect(user.online_id).to eq("matty_plays")
    expect(user.account_id).to eq("1234567890123456789")
    expect(user.display_name).to eq("Matty")
    expect(user.avatar_url).to eq("https://static-resource.np.community.playstation.net/avatar_m/WWS_A/A0031_m.png")
    expect(user).to be_ps_plus
  end

  it "keeps the raw payload and tolerates missing keys" do
    expect(described_class.from_api(fixture("user_search_player")).raw).to eq(fixture("user_search_player"))
    expect(described_class.from_api({})).not_to be_ps_plus
  end
end
