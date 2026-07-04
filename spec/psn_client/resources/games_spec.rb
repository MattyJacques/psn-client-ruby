# frozen_string_literal: true

RSpec.describe PSN::Resources::Games do
  subject(:games) { described_class.new(connection, users) }

  let(:connection) { instance_double(PSN::Connection) }
  let(:users) { instance_double(PSN::Resources::Users) }

  it "fetches all pages of played titles for the authenticated user" do
    allow(users).to receive(:account_id).with(nil).and_return("me")
    allow(connection).to receive(:get)
      .with(:mobile, "/api/gamelist/v2/users/me/titles", { "limit" => 200, "offset" => 0 })
      .and_return({ "titles" => [fixture("game_title")], "totalItemCount" => 1 })

    result = games.played.to_a
    expect(result.size).to eq(1)
    expect(result.first).to be_a(PSN::GameTitle)
    expect(result.first.name).to eq("ASTRO's PLAYROOM")
  end

  it "resolves another user's online ID and pages lazily" do
    allow(users).to receive(:account_id).with("friend").and_return("42")
    allow(connection).to receive(:get)
      .with(:mobile, "/api/gamelist/v2/users/42/titles", { "limit" => 200, "offset" => 0 })
      .and_return({ "titles" => Array.new(200) { fixture("game_title") }, "totalItemCount" => 400 })

    expect(games.played("friend")).to be_a(Enumerator::Lazy)
    expect(games.played("friend").first(3).size).to eq(3)
    expect(connection).to have_received(:get).once # second page never requested
  end
end
