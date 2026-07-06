# frozen_string_literal: true

RSpec.describe PSN::Resources::Trophies do
  subject(:trophies) { described_class.new(connection, users) }

  let(:connection) { instance_double(PSN::Connection) }
  let(:users) { instance_double(PSN::Resources::Users, account_id: "me") }

  describe "#titles" do
    it "returns lazy TrophyTitle objects" do
      allow(connection).to receive(:get)
        .with(:mobile, "/api/trophy/v1/users/me/trophyTitles", { "limit" => 100, "offset" => 0 })
        .and_return({ "trophyTitles" => [fixture("trophy_title")], "totalItemCount" => 1 })

      result = trophies.titles.to_a
      expect(result.first).to be_a(PSN::TrophyTitle)
      expect(result.first.np_communication_id).to eq("NPWR20188_00")
    end
  end

  describe "#summary" do
    it "returns a TrophySummary" do
      allow(connection).to receive(:get)
        .with(:mobile, "/api/trophy/v1/users/me/trophySummary", {})
        .and_return(fixture("trophy_summary"))

      expect(trophies.summary.level).to eq(401)
    end
  end

  describe "#earned" do
    def stub_trophy_calls(params)
      definition2 = fixture("trophy_definition").merge("trophyId" => 2, "trophyName" => "Hidden Gem")
      allow(connection).to receive(:get)
        .with(:mobile, "/api/trophy/v1/npCommunicationIds/NPWR20188_00/trophyGroups/all/trophies", params)
        .and_return({ "trophies" => [fixture("trophy_definition"), definition2] })
      allow(connection).to receive(:get)
        .with(:mobile, "/api/trophy/v1/users/me/npCommunicationIds/NPWR20188_00/trophyGroups/all/trophies", params)
        .and_return({ "trophies" => [fixture("trophy_earned")] })
    end

    it "merges definitions with earned status" do
      stub_trophy_calls({})
      result = trophies.earned(np_communication_id: "NPWR20188_00").to_a

      expect(result.size).to eq(2)
      expect(result[0].name).to eq("One Small Step")
      expect(result[0]).to be_earned
      expect(result[0].earned_at).to eq(Time.utc(2025, 1, 2, 20, 15, 0))
    end

    it "marks unearned trophies correctly" do
      stub_trophy_calls({})
      result = trophies.earned(np_communication_id: "NPWR20188_00").to_a

      expect(result[1].name).to eq("Hidden Gem")
      expect(result[1]).not_to be_earned
    end

    it "adds npServiceName=trophy for non-PS5 platforms" do
      stub_trophy_calls({ "npServiceName" => "trophy" })
      result = trophies.earned(np_communication_id: "NPWR20188_00", platform: "PS4").to_a
      expect(result.size).to eq(2)
    end

    it "omits npServiceName for PS5 titles" do
      stub_trophy_calls({})
      trophies.earned(np_communication_id: "NPWR20188_00", platform: "PS5").to_a
      expect(connection).to have_received(:get).twice
    end
  end

  describe "#title_summary" do
    it "chunks title IDs into batches of 5 per request" do
      allow(users).to receive(:account_id).with(nil).and_return("me")
      ids = %w[A_00 B_00 C_00 D_00 E_00 F_00]
      allow(connection).to receive(:get)
        .with(:mobile, "/api/trophy/v1/users/me/titles/trophyTitles",
              { "npTitleIds" => "A_00,B_00,C_00,D_00,E_00" })
        .and_return({ "titles" => [fixture("title_trophy_summary")] })
      allow(connection).to receive(:get)
        .with(:mobile, "/api/trophy/v1/users/me/titles/trophyTitles", { "npTitleIds" => "F_00" })
        .and_return({ "titles" => [fixture("title_trophy_summary")] })

      result = trophies.title_summary(title_ids: ids).to_a
      expect(result.size).to eq(2)
      expect(result.first).to be_a(PSN::TitleTrophySummary)
      expect(connection).to have_received(:get).twice
    end

    it "is lazy across batches and resolves the online ID" do
      allow(users).to receive(:account_id).with("friend").and_return("42")
      allow(connection).to receive(:get)
        .with(:mobile, "/api/trophy/v1/users/42/titles/trophyTitles",
              { "npTitleIds" => "A_00,B_00,C_00,D_00,E_00" })
        .and_return({ "titles" => [fixture("title_trophy_summary")] })

      result = trophies.title_summary("friend", title_ids: %w[A_00 B_00 C_00 D_00 E_00 F_00])
      expect(result.first(1).size).to eq(1)
      expect(connection).to have_received(:get).once # second batch never requested
    end
  end
end
