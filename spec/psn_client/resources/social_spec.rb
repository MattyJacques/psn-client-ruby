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
end
