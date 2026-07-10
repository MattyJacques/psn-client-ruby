# frozen_string_literal: true

RSpec.describe PSN::Resources::Social do
  subject(:social) { described_class.new(connection, users) }

  let(:connection) { instance_double(PSN::Connection) }
  let(:users) { instance_double(PSN::Resources::Users) }

  describe "#presence" do
    it "fetches primary presence for the authenticated account" do
      allow(users).to receive(:account_id).with(nil).and_return("me")
      allow(connection).to receive(:get)
        .with(:mobile, "/api/userProfile/v1/internal/users/me/basicPresences", { "type" => "primary" })
        .and_return({ "basicPresence" => fixture("presence") })

      presence = social.presence
      expect(presence).to be_a(PSN::Presence)
      expect(presence).to be_online
      expect(presence.now_playing.first.name).to eq("ASTRO's PLAYROOM")
    end

    it "resolves another user's online ID and survives an empty body" do
      allow(users).to receive(:account_id).with("friend").and_return("42")
      allow(connection).to receive(:get)
        .with(:mobile, "/api/userProfile/v1/internal/users/42/basicPresences", { "type" => "primary" })
        .and_return({})

      expect(social.presence("friend")).not_to be_online
    end
  end

  describe "#friends" do
    it "pages friend account IDs lazily with a total count" do
      allow(users).to receive(:account_id).with(nil).and_return("me")
      allow(connection).to receive(:get)
        .with(:mobile, "/api/userProfile/v1/internal/users/me/friends", { "limit" => 100, "offset" => 0 })
        .and_return({ "friends" => Array.new(100, &:to_s), "totalItemCount" => 150 })
      allow(connection).to receive(:get)
        .with(:mobile, "/api/userProfile/v1/internal/users/me/friends", { "limit" => 100, "offset" => 100 })
        .and_return({ "friends" => Array.new(50) { |i| (100 + i).to_s }, "totalItemCount" => 150 })

      expect(social.friends).to be_a(Enumerator::Lazy)
      expect(social.friends.to_a.size).to eq(150)
      expect(social.friends.first(3)).to eq(%w[0 1 2])
    end

    it "resolves another user's online ID" do
      allow(users).to receive(:account_id).with("friend").and_return("42")
      allow(connection).to receive(:get)
        .with(:mobile, "/api/userProfile/v1/internal/users/42/friends", { "limit" => 100, "offset" => 0 })
        .and_return({ "friends" => ["7"], "totalItemCount" => 1 })

      expect(social.friends("friend").to_a).to eq(["7"])
    end
  end

  describe "#friend_requests" do
    it "returns account IDs of received requests for the authenticated account" do
      allow(connection).to receive(:get)
        .with(:mobile, "/api/userProfile/v1/internal/users/me/friends/receivedRequests",
              { "limit" => 100, "offset" => 0 })
        .and_return({ "receivedRequests" => %w[11 12], "totalItemCount" => 2 })

      expect(social.friend_requests.to_a).to eq(%w[11 12])
    end
  end

  describe "#blocked" do
    it "pages until an empty page (no total in the response)" do
      allow(connection).to receive(:get)
        .with(:mobile, "/api/userProfile/v1/internal/users/me/blocks", { "limit" => 100, "offset" => 0 })
        .and_return({ "blockList" => %w[5 6] })
      allow(connection).to receive(:get)
        .with(:mobile, "/api/userProfile/v1/internal/users/me/blocks", { "limit" => 100, "offset" => 2 })
        .and_return({ "blockList" => [] })

      expect(social.blocked.to_a).to eq(%w[5 6])
      expect(connection).to have_received(:get).twice
    end
  end

  describe "#friendship" do
    it "returns the raw friendship summary body (provisional mapping)" do
      body = { "friendRelation" => "friend", "personalDetailSharing" => "none" }
      allow(users).to receive(:account_id).with("friend").and_return("42")
      allow(connection).to receive(:get)
        .with(:mobile, "/api/userProfile/v1/internal/users/me/friends/42/summary", {})
        .and_return(body)

      expect(social.friendship("friend")).to eq(body)
    end
  end

  describe "#available_to_play" do
    it "returns the raw availability body (provisional mapping)" do
      body = { "availableToPlay" => [] }
      allow(connection).to receive(:get)
        .with(:mobile, "/api/userProfile/v1/internal/users/me/friends/subscribing/availableToPlay", {})
        .and_return(body)

      expect(social.available_to_play).to eq(body)
    end
  end
end
