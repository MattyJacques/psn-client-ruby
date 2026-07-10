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
end
