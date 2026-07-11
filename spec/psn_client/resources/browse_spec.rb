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

  describe "#views" do
    def stub_views
      variables = { "viewInputs" => [{ "viewId" => "de9da6a2-cce6-11ee-a31f-a2110459ffc0",
                                       "experienceId" => "7bbceafe-bfa8-11ee-b375-5e45f4e139ac" }] }
      allow(connection).to receive(:graphql)
        .with("metGetViews", variables, described_class::VIEWS_HASH, host: :mobile, headers: headers)
        .and_return({ "data" => { "emsViewsRetrieve" => [fixture("ems_view")] } })
    end

    def first_view
      browse.views("de9da6a2-cce6-11ee-a31f-a2110459ffc0",
                   experience_id: "7bbceafe-bfa8-11ee-b375-5e45f4e139ac").first
    end

    it "fetches views by id + experience via metGetViews" do
      stub_views
      expect(first_view).to be_a(PSN::StoreView)
      expect(first_view.components.map(&:component_type)).to eq(%w[IMAGE SIMPLE_TEXT GRID])
    end

    it "maps component links" do
      stub_views
      cta = first_view.components[1]
      expect(cta.text).to eq("Save Now")
      expect(cta.link.target).to eq("e97029b2-8c26-4185-b6d4-aa528ee2c526")
      expect(cta.link.localized_name).to eq("cat.gma.Example_Promo")
    end

    it "exposes GRID component browse config" do
      stub_views
      grid = first_view.components[2]
      expect(grid.category_id).to eq("e97029b2-8c26-4185-b6d4-aa528ee2c526")
      expect(grid.facet_list).to include("webBasePrice")
    end
  end

  describe "#default_view" do
    it "returns the category's child views via metGetDefaultView" do
      variables = { "categoryId" => "e97029b2-8c26-4185-b6d4-aa528ee2c526",
                    "localizedKeyId" => "cat.gma.Example_Promo",
                    "experienceId" => "7bbceafe-bfa8-11ee-b375-5e45f4e139ac" }
      allow(connection).to receive(:graphql)
        .with("metGetDefaultView", variables, described_class::DEFAULT_VIEW_HASH,
              host: :mobile, headers: headers)
        .and_return({ "data" => { "emsDefaultViewRetrieve" => { "childViews" => [fixture("ems_view")] } } })

      views = browse.default_view("e97029b2-8c26-4185-b6d4-aa528ee2c526",
                                  localized_key_id: "cat.gma.Example_Promo",
                                  experience_id: "7bbceafe-bfa8-11ee-b375-5e45f4e139ac")
      expect(views.size).to eq(1)
      expect(views.first.type).to eq("STORE_HERO_VIEW")
    end
  end
end
