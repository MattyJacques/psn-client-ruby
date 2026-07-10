# frozen_string_literal: true

RSpec.describe "group models" do
  describe PSN::Mapping do
    it "converts epoch-milliseconds strings to UTC Time" do
      expect(described_class.epoch_ms("1751980000000")).to eq(Time.at(1_751_980_000).utc)
      expect(described_class.epoch_ms(nil)).to be_nil
    end
  end

  describe PSN::Group do
    subject(:group) { described_class.from_api(fixture("group")) }

    it "maps id, name, members and the latest message" do
      expect(group.id).to eq("9999999999999999999999999999999999999999-100")
      expect(group.name).to eq("Example Group")
      expect(group.favorite?).to be(false)
      expect(group.members.map(&:online_id)).to eq(%w[example_user example_friend])
      expect(group.members.first.role).to eq("owner")
      expect(group.latest_message).to be_a(PSN::GroupMessage)
      expect(group.latest_message.body).to eq("Hello world")
      expect(group.modified_at).to eq(Time.at(1_751_980_000).utc)
    end

    it "maps a minimal hash with nils and empty members" do
      minimal = described_class.from_api({ "groupId" => "x" })
      expect(minimal.name).to be_nil
      expect(minimal.members).to eq([])
      expect(minimal.latest_message).to be_nil
    end
  end

  describe PSN::GroupMessage do
    subject(:message) { described_class.from_api(fixture("group_message")) }

    it "maps uid, typed type, body, time and sender" do
      expect(message.uid).to eq("9#100000000000001")
      expect(message.type).to eq(1)
      expect(message.type_name).to eq(:text)
      expect(message.body).to eq("Hello world")
      expect(message.created_at).to eq(Time.at(1_751_980_000).utc)
      expect(message.sender_online_id).to eq("example_friend")
    end

    it "leaves unknown message types as nil type_name" do
      expect(described_class.from_api({ "messageType" => 999 }).type_name).to be_nil
    end
  end
end
