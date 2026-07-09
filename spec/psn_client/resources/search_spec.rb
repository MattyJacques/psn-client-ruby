# frozen_string_literal: true

RSpec.describe PSN::Resources::Search do
  subject(:search) { described_class.new(connection) }

  let(:connection) { instance_double(PSN::Connection) }
  let(:game_item) { { "id" => "hit-1", "result" => fixture("catalog_product") } }
  let(:games_context_response) do
    { "data" => { "universalContextSearch" => { "results" => [
      { "domain" => "MobileGames", "searchResults" => [game_item], "next" => "cur1" },
      { "domain" => "MobileAddOns", "searchResults" => [], "next" => "" }
    ] } } }
  end
  let(:games_domain_response) do
    { "data" => { "universalDomainSearch" =>
      { "searchResults" => [game_item.merge("id" => "hit-2")], "next" => "" } } }
  end

  describe "#games" do
    before do
      allow(connection).to receive(:graphql)
        .with("metGetContextSearchResults",
              { "searchTerm" => "fable", "searchContext" => "MobileUniversalSearchGame",
                "displayTitleLocale" => "en-US" },
              described_class::GAMES_CONTEXT_HASH, headers: described_class::HEADERS)
        .and_return(games_context_response)
      allow(connection).to receive(:graphql)
        .with("metGetDomainSearchResults",
              { "searchTerm" => "fable", "searchDomain" => "MobileGames",
                "pageSize" => 20, "pageOffset" => 1, "nextCursor" => "cur1" },
              described_class::GAMES_DOMAIN_HASH, headers: described_class::HEADERS)
        .and_return(games_domain_response)
    end

    it "yields the context page then walks domain pages" do
      results = search.games("fable").to_a
      expect(results.size).to eq(2)
      expect(results.first).to be_a(PSN::CatalogItem)
      expect(results.first.name).to eq("Fable Standard Edition")
    end

    it "is lazy: .first(1) only issues the context request" do
      expect(search.games("fable").first(1).size).to eq(1)
      expect(connection).to have_received(:graphql).once
    end

    it "rejects unknown domains" do
      expect { search.games("fable", domain: :nope) }.to raise_error(KeyError)
    end
  end

  describe "#users" do
    let(:users_context_response) do
      { "data" => { "universalContextSearch" => { "results" => [
        { "domain" => "SocialAllAccounts",
          "searchResults" => [{ "id" => "u1", "result" => fixture("user_search_player") }],
          "next" => "" }
      ] } } }
    end

    it "maps players from the social context search" do
      allow(connection).to receive(:graphql)
        .with("metGetContextSearchResults",
              { "searchTerm" => "matty", "searchContext" => "MobileUniversalSearchSocial",
                "displayTitleLocale" => "en-US" },
              described_class::USERS_CONTEXT_HASH, headers: described_class::HEADERS)
        .and_return(users_context_response)

      results = search.users("matty").to_a
      expect(results.size).to eq(1)
      expect(results.first).to be_a(PSN::UserSearchResult)
      expect(results.first.online_id).to eq("matty_plays")
    end
  end
end
