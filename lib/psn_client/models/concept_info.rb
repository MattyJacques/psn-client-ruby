# frozen_string_literal: true

module PSN
  # The store product page's "game info" slice (conceptRetrieveForGameInfo):
  # descriptions, genres, publisher and release date for a concept. Sony
  # wraps releaseDate in an object here ({"type", "value"}), unlike most
  # other endpoints.
  ConceptInfo = Data.define(:short_description, :long_description, :genres,
                            :publisher_name, :release_date, :raw) do
    def self.from_api(hash)
      new(short_description: Mapping.description(hash, "SHORT"),
          long_description: Mapping.description(hash, "LONG"),
          genres: (hash["localizedGenres"] || []).map { |genre| genre["value"] },
          publisher_name: hash["publisherName"],
          release_date: Mapping.time(hash.dig("releaseDate", "value")),
          raw: hash)
    end
  end
end
