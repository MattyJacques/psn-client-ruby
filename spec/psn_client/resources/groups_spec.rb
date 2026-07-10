# frozen_string_literal: true

RSpec.describe PSN::Resources::Groups do
  subject(:groups) { described_class.new(connection) }

  let(:connection) { instance_double(PSN::Connection) }
  let(:base) { "/api/gamingLoungeGroups/v1" }
  let(:group_id) { "9999999999999999999999999999999999999999-100" }

  describe "#all" do
    it "walks offset pages and maps Group objects, stopping on an empty page" do
      allow(connection).to receive(:get)
        .with(:mobile, "#{base}/members/me/groups",
              { "includeFields" => "members", "limit" => 100, "offset" => 0 },
              headers: described_class::HEADERS)
        .and_return({ "groups" => [fixture("group")] })
      allow(connection).to receive(:get)
        .with(:mobile, "#{base}/members/me/groups",
              { "includeFields" => "members", "limit" => 100, "offset" => 1 },
              headers: described_class::HEADERS)
        .and_return({ "groups" => [] })

      result = groups.all.to_a
      expect(result.size).to eq(1)
      expect(result.first).to be_a(PSN::Group)
      expect(result.first.members.size).to eq(2)
    end
  end

  describe "#find" do
    it "fetches one group with full fields from the members/me nested path" do
      allow(connection).to receive(:get)
        .with(:mobile, "#{base}/members/me/groups/#{group_id}",
              { "includeFields" => "groupName,groupIcon,members,mainThread" },
              headers: described_class::HEADERS)
        .and_return(fixture("group"))

      expect(groups.find(group_id).latest_message.body).to eq("Hello world")
    end
  end

  describe "#messages" do
    let(:path) { "#{base}/members/me/groups/g1/threads/g1/messages" }

    it "walks the conversation backward until reachedEndOfPage using the before param" do
      allow(connection).to receive(:get)
        .with(:mobile, path, { "limit" => 20 }, headers: described_class::HEADERS)
        .and_return({ "messages" => [fixture("group_message")],
                      "next" => "9#100000000000001", "reachedEndOfPage" => false })
      allow(connection).to receive(:get)
        .with(:mobile, path, { "limit" => 20, described_class::CURSOR_PARAM => "9#100000000000001" },
              headers: described_class::HEADERS)
        .and_return({ "messages" => [fixture("group_message").merge("messageUid" => "9#2")],
                      "next" => "9#2", "reachedEndOfPage" => true })

      result = groups.messages("g1").to_a
      expect(result.size).to eq(2)
      expect(result.first).to be_a(PSN::GroupMessage)
      expect(result.last.uid).to eq("9#2")
    end

    it "is lazy" do
      allow(connection).to receive(:get)
        .and_return({ "messages" => [fixture("group_message")], "next" => "n", "reachedEndOfPage" => false })
      expect(groups.messages("g1").first(1).size).to eq(1)
      expect(connection).to have_received(:get).once
    end
  end
end
