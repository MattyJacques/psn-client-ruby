# frozen_string_literal: true

RSpec.describe PSN::Resources::Browse do
  subject(:browse) { described_class.new(connection) }

  let(:connection) { instance_double(PSN::Connection) }
  let(:headers) { { "apollographql-client-name" => "PlayStationApp-Android" } }

  describe "#experience" do
    it "returns the StoreExperience nav tree via metGetExperience" do
      allow(connection).to receive(:graphql)
        .with("metGetExperience", { "clientId" => described_class::EMS_CLIENT_ID },
              described_class::EXPERIENCE_HASH, host: :mobile, headers: headers)
        .and_return({ "data" => { "emsExperienceRetrieve" => fixture("ems_experience") } })

      experience = browse.experience
      expect(experience).to be_a(PSN::StoreExperience)
      expect(experience.id).to eq("7bbceafe-bfa8-11ee-b375-5e45f4e139ac")
      expect(experience.nav_items.map(&:name)).to eq(%w[Latest Browse])
      expect(experience.nav_items.first.view_collection_id)
        .to eq("31ce2664-cfd1-11ee-9d6a-d6ec549ae369")
    end

    it "returns a hollow model when the experience is unknown" do
      allow(connection).to receive(:graphql)
        .and_return({ "data" => { "emsExperienceRetrieve" => nil } })

      experience = browse.experience(client_id: "nope")
      expect(experience.nav_items).to eq([])
    end
  end
end
