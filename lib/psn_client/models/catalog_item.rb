# frozen_string_literal: true

module PSN
  # A store catalog card: either a released Product or an unreleased Concept
  # (concept? true, price nil). Returned by search results, category grids
  # and add-on lists, which all share this Product/Concept shape.
  CatalogItem = Data.define(:name, :id, :np_title_id, :concept, :platforms,
                            :classification, :localized_classification,
                            :image_url, :price, :raw) do
    def self.from_api(hash)
      price = hash["price"]
      new(name: hash["name"], id: hash["id"], np_title_id: hash["npTitleId"],
          concept: hash["__typename"] == "Concept", platforms: hash["platforms"] || [],
          classification: hash["storeDisplayClassification"],
          localized_classification: hash["localizedStoreDisplayClassification"],
          image_url: cover_url(hash["media"] || []),
          price: price && Price.from_api(price), raw: hash)
    end

    # The store's box-art equivalent; falls back to any image.
    def self.cover_url(media)
      images = media.select { |m| m["type"] == "IMAGE" }
      cover = images.find { |m| m["role"] == "GAMEHUB_COVER_ART" } || images.first
      cover && cover["url"]
    end

    def concept? = concept
  end
end
