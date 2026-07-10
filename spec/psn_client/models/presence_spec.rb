# frozen_string_literal: true

RSpec.describe PSN::Presence do
  subject(:presence) { described_class.from_api(fixture("presence")) }

  it "maps availability, status, platform and last-online time" do
    expect(presence.availability).to eq("availableToPlay")
    expect(presence).to be_online
    expect(presence).to be_available
    expect(presence.platform).to eq("PS5")
    expect(presence.last_online_at).to eq(Time.utc(2026, 7, 9, 21, 14, 2))
  end

  it "maps the now-playing titles" do
    title = presence.now_playing.first
    expect(title).to be_a(PSN::PresenceTitle)
    expect(title.np_title_id).to eq("PPSA01325_00")
    expect(title.name).to eq("ASTRO's PLAYROOM")
    expect(title.icon_url).to eq("https://image.api.playstation.com/vulcan/img/rnd/202010/astro-icon.png")
  end

  it "handles an offline user with no platform info or titles" do
    offline = described_class.from_api({ "availability" => "unavailable" })
    expect(offline).not_to be_online
    expect(offline).not_to be_available
    expect(offline.platform).to be_nil
    expect(offline.last_online_at).to be_nil
    expect(offline.now_playing).to eq([])
  end

  it "keeps the raw response" do
    expect(presence.raw).to eq(fixture("presence"))
  end
end
