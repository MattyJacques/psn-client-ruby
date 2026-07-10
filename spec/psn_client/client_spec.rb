# frozen_string_literal: true

RSpec.describe PSN::Client do
  let(:token_url) { "https://ca.account.sony.com/api/authz/v3/oauth/token" }

  def stub_oauth
    stub_request(:post, token_url).to_return(
      status: 200,
      body: { access_token: "AT-1", refresh_token: "RT-1", expires_in: 3600 }.to_json,
      headers: { "Content-Type" => "application/json" }
    )
  end

  it "exposes memoized resource objects" do # rubocop:disable RSpec/MultipleExpectations
    client = described_class.new(refresh_token: "RT-0")
    expect(client.games).to be_a(PSN::Resources::Games)
    expect(client.trophies).to be_a(PSN::Resources::Trophies)
    expect(client.store).to be_a(PSN::Resources::Store)
    expect(client.profiles).to be_a(PSN::Resources::Profiles)
    expect(client.search).to equal(client.search)
    expect(client.social).to be_a(PSN::Resources::Social)
    expect(client.social).to equal(client.social)
  end

  it "exposes the search and catalog resources" do
    client = described_class.new(refresh_token: "RT-0")
    expect(client.search).to be_a(PSN::Resources::Search)
    expect(client.catalog).to be_a(PSN::Resources::Catalog)
    expect(client.catalog).to equal(client.catalog)
  end

  it "requires exactly one credential" do
    expect { described_class.new }.to raise_error(ArgumentError)
  end

  it "authenticates lazily and fetches games end-to-end" do
    stub_oauth
    stub_request(:get, "https://m.np.playstation.com/api/gamelist/v2/users/me/titles")
      .with(query: { "limit" => "200", "offset" => "0" },
            headers: { "Authorization" => "Bearer AT-1" })
      .to_return(status: 200,
                 body: { titles: [fixture("game_title")], totalItemCount: 1 }.to_json,
                 headers: { "Content-Type" => "application/json" })

    client = described_class.new(refresh_token: "RT-0")
    expect(WebMock).not_to have_requested(:post, token_url) # nothing yet: lazy

    games = client.games.played.to_a
    expect(games.first.name).to eq("ASTRO's PLAYROOM")
    expect(client.refresh_token).to eq("RT-1")
  end
end
