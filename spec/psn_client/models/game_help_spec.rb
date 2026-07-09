# frozen_string_literal: true

RSpec.describe PSN::GameHelp do
  it "maps access and tips with flattened contents" do
    help = described_class.from_api(fixture("trophy_tips"))
    expect(help).to be_access
    expect(help.tips.size).to eq(1)
    expect(help.tips.first).to be_a(PSN::TrophyTip)
    expect(help.tips.first.trophy_id).to eq("18")
    expect(help.tips.first.contents.first.display_name).to eq("Since 1995")
  end

  it "maps tip content fields" do
    content = described_class.from_api(fixture("trophy_tips")).tips.first.contents.first
    expect(content).to be_a(PSN::TipContent)
    expect(content.description).to eq("The gatcha prize you seek is inside a silver ball.")
    expect(content.media_type).to eq("VIDEO")
    expect(content.media_url).to eq("https://gms-ght.playstation-cloud.com/video/master_playlist.m3u8")
    expect(content.tip_id).to eq("NPWR20188_00__GATCHA_SECRET_H1")
  end

  it "reports no access on an empty or gated payload" do
    help = described_class.from_api({})
    expect(help).not_to be_access
    expect(help.tips).to eq([])
  end
end

RSpec.describe PSN::TrophyHelpInfo do
  it "maps the hint availability shape" do
    info = described_class.from_api(fixture("help_availability"))
    expect(info.trophy_id).to eq("18")
    expect(info.uds_object_id).to eq("GATCHA_SECRET")
    expect(info.help_type).to eq("HINT")
    expect(info.raw).to eq(fixture("help_availability"))
  end
end
