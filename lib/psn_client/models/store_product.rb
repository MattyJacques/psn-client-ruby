# frozen_string_literal: true

module PSN
  # Full store product detail (metGetProductById). Unlike CatalogItem this
  # carries no price — use Catalog#pricing with concept_id for that.
  StoreProduct = Data.define(:name, :id, :np_title_id, :invariant_name, :concept_id,
                             :platforms, :publisher, :release_date, :genres,
                             :classification, :localized_classification, :edition,
                             :short_description, :description, :content_rating,
                             :image_url, :raw) do
    def self.from_api(hash)
      new(name: hash["name"], id: hash["id"], np_title_id: hash["npTitleId"],
          invariant_name: hash["invariantName"], concept_id: hash.dig("concept", "id"),
          platforms: hash["platforms"] || [], publisher: hash["publisherName"],
          release_date: Mapping.time(hash["releaseDate"]),
          genres: (hash["combinedLocalizedGenres"] || []).map { |g| g["value"] },
          classification: hash["storeDisplayClassification"],
          localized_classification: hash["localizedStoreDisplayClassification"],
          edition: hash.dig("edition", "name"),
          short_description: description_of(hash, "SHORT"),
          description: description_of(hash, "LONG"),
          content_rating: hash.dig("contentRating", "description"),
          image_url: CatalogItem.cover_url(hash["media"] || []), raw: hash)
    end

    def self.description_of(hash, type)
      entry = (hash["descriptions"] || []).find { |d| d["type"] == type }
      entry && entry["value"]
    end
  end
end
