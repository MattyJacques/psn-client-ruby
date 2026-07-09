# frozen_string_literal: true

module PSN
  # Full store concept detail (metGetConceptById): the franchise-level entry
  # a product belongs to; exists even before release. Note releaseDate is an
  # object here ({"type", "value"}), unlike StoreProduct's plain string. The
  # releaseDate "type" field records Sony's precision (DAY_MONTH_YEAR,
  # MONTH_YEAR, YEAR) — release_date is parsed as a full timestamp regardless,
  # so check raw["releaseDate"]["type"] before trusting day-level precision.
  StoreConcept = Data.define(:name, :id, :invariant_name, :publisher, :release_date,
                             :genres, :description, :image_url, :default_product, :raw) do
    def self.from_api(hash)
      default_product = hash["defaultProduct"]
      new(name: hash["name"], id: hash["id"], invariant_name: hash["invariantName"],
          publisher: hash["publisherName"],
          release_date: Mapping.time(hash.dig("releaseDate", "value")),
          genres: (hash["combinedLocalizedGenres"] || []).map { |g| g["value"] },
          description: Mapping.description(hash, "LONG"),
          image_url: Mapping.cover_url(hash["media"] || []),
          default_product: default_product && CatalogItem.from_api(default_product), raw: hash)
    end
  end
end
