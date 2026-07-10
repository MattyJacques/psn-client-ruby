# frozen_string_literal: true

module PSN
  # A concept as returned by the mobile catalog's titles/%s/concepts lookup.
  # Shape differs from the GraphQL StoreConcept (no publisher/media mapping);
  # localized names and descriptions stay available in raw.
  TitleConcept = Data.define(:id, :name, :title_ids, :type, :raw) do
    def self.from_api(hash)
      localized = hash["localizedName"] || {}
      new(id: hash["id"],
          name: hash["nameEn"] || (localized["metadata"] || {})[localized["defaultLanguage"]],
          title_ids: hash["titleIds"] || [], type: hash["type"], raw: hash)
    end
  end
end
