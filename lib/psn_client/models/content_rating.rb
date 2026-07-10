# frozen_string_literal: true

module PSN
  # A store age rating (conceptRetrieveForContentRating): the rating
  # authority (PEGI, ESRB, ...), the rating itself with its icon URL, and
  # the content descriptor entries ({name:, description:, url:} hashes).
  ContentRating = Data.define(:authority, :name, :description, :url, :descriptors, :raw) do
    def self.from_api(hash)
      descriptors = (hash["descriptors"] || []).map do |d|
        { name: d["name"], description: d["description"], url: d["url"] }
      end
      new(authority: hash["authority"], name: hash["name"], description: hash["description"],
          url: hash["url"], descriptors: descriptors, raw: hash)
    end
  end
end
