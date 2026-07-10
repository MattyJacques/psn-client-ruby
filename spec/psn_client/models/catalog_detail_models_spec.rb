# frozen_string_literal: true

RSpec.describe "PSN catalog detail models" do
  describe PSN::ContentRating do
    it "maps authority, rating and descriptor entries" do
      rating = described_class.from_api(fixture("content_rating"))
      expect(rating.authority).to eq("PEGI")
      expect(rating.name).to eq("PEGI_18")
      expect(rating.description).to eq("PEGI 18")
      expect(rating.url).to eq("https://cdn-a.sonyentertainmentnetwork.com/grc/images/ratings/hd/pegi/18.png")
      expect(rating.descriptors).to eq(
        [{ name: "PEGI_LANGUAGE", description: "Language",
           url: "https://cdn-a.sonyentertainmentnetwork.com/images/descriptors/hd/pegi/language.png" },
         { name: "PEGI_VIOLENCE", description: "Violence",
           url: "https://cdn-a.sonyentertainmentnetwork.com/images/descriptors/hd/pegi/violence.png" }]
      )
    end

    it "tolerates missing descriptors and keeps the raw hash" do
      rating = described_class.from_api({ "name" => "ESRB_M" })
      expect(rating.descriptors).to eq([])
      expect(rating.raw).to eq({ "name" => "ESRB_M" })
    end
  end

  describe PSN::MediaItem do
    it "maps role, type and url with type predicates" do
      item = described_class.from_api({ "role" => "SCREENSHOT", "type" => "IMAGE", "url" => "https://x/1.jpg" })
      expect(item.role).to eq("SCREENSHOT")
      expect(item).to be_image
      expect(item).not_to be_video
      expect(item.url).to eq("https://x/1.jpg")
    end

    it "recognises videos" do
      item = described_class.from_api({ "role" => "PREVIEW", "type" => "VIDEO", "url" => "https://x/1.mp4" })
      expect(item).to be_video
      expect(item).not_to be_image
    end
  end

  describe PSN::CompatibilityNotices do
    it "flattens per-platform maps into entry hashes, skipping nulls and __typename" do
      notices = described_class.from_api(fixture("compatibility_concept"))
      expect(notices.compatibility).to eq([{ platform: "Common", type: "NO_OF_PLAYERS", value: "1" }])
      expect(notices.accessibility).to eq([{ platform: "Common", type: "SUBTITLES", value: "Available" }])
    end

    it "returns empty arrays when both maps are missing" do
      notices = described_class.from_api({})
      expect(notices.compatibility).to eq([])
      expect(notices.accessibility).to eq([])
      expect(notices.raw).to eq({})
    end
  end

  describe PSN::LegalText do
    it "keeps only LEGAL description entries with their subtypes" do
      legal = described_class.from_api(fixture("legal_product"))
      expect(legal.notices).to eq(
        [{ sub_type: "SCEE_TOS",
           text: "<br><br>Download of this product is subject to the PlayStation Network Terms of Service." },
         { sub_type: "SCEE_HEALTH_TEXT",
           text: "<br>See health warnings for important health information." }]
      )
      expect(legal.privacy_policy).to be_nil
      expect(legal.publisher).to eq("Microsoft Corporation")
    end

    it "tolerates a product without descriptions" do
      legal = described_class.from_api({ "privacyPolicy" => "https://example.com/privacy" })
      expect(legal.notices).to eq([])
      expect(legal.privacy_policy).to eq("https://example.com/privacy")
    end
  end

  describe PSN::Edition do
    it "maps the product with its first CTA's type and price" do
      edition = described_class.from_api(fixture("edition_product"))
      expect(edition.name).to eq("Fable Standard Edition")
      expect(edition.id).to eq("UP6312-PPSA31381_00-0202050640964065")
      expect(edition.np_title_id).to eq("PPSA31381_00")
      expect(edition.cta_type).to eq("PREORDER")
      expect(edition.price).to be_a(PSN::Price)
      expect(edition.price.base_price).to eq("£59.99")
    end

    it "has nil cta_type and price when there are no CTAs" do
      edition = described_class.from_api({ "name" => "Demo" })
      expect(edition.cta_type).to be_nil
      expect(edition.price).to be_nil
    end
  end

  describe PSN::PlusOffer do
    it "maps plan, sku and price members" do
      offer = described_class.from_api(fixture("plus_offer"))
      expect(offer.title).to eq("1 Month Subscription")
      expect(offer.duration).to eq("1-Month Plan")
      expect(offer.sku_id).to eq("IP9102-PPSA06902_00-PLUS1T01M0000000-E004")
      expect(offer.base_price_value).to eq(799)
      expect(offer.discounted_price).to eq("£7.99")
      expect(offer.currency_code).to eq("GBP")
      expect(offer).not_to be_trial
      expect(offer).not_to be_active_subscription
    end

    it "flags trials and tolerates a missing price" do
      offer = described_class.from_api({ "title" => "Trial", "isTrial" => true })
      expect(offer).to be_trial
      expect(offer.base_price).to be_nil
    end
  end
end
