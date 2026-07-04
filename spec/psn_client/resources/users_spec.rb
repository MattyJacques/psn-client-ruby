# frozen_string_literal: true

RSpec.describe PSN::Resources::Users do
  subject(:users) { described_class.new(connection) }

  let(:connection) { instance_double(PSN::Connection) }

  def search_response(results)
    { "domainResponses" => [{ "results" => results }] }
  end

  it "returns 'me' for nil without any request" do
    expect(users.account_id(nil)).to eq("me")
  end

  it "resolves an online ID via universal search and caches it" do
    allow(connection).to receive(:post)
      .with(:mobile, "/api/search/v1/universalSearch",
            { "searchTerm" => "some_player", "domainRequests" => [{ "domain" => "SocialAllAccounts" }] })
      .and_return(search_response([
                                    { "socialMetadata" => { "onlineId" => "some_player_2", "accountId" => "999" } },
                                    { "socialMetadata" => { "onlineId" => "Some_Player", "accountId" => "123456789" } }
                                  ]))

    expect(users.account_id("some_player")).to eq("123456789")
    expect(users.account_id("SOME_PLAYER")).to eq("123456789")
    expect(connection).to have_received(:post).once
  end

  it "raises NotFoundError when no result matches exactly" do
    allow(connection).to receive(:post).and_return(search_response([]))
    expect { users.account_id("ghost_user") }.to raise_error(PSN::NotFoundError, /ghost_user/)
  end
end
