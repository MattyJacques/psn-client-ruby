# frozen_string_literal: true

module PSN
  # A title installed on a console (from the console storage endpoint).
  # name comes from Sony's "comment" field, which holds the display name.
  InstalledTitle = Data.define(:name, :title_id, :np_title_id, :concept_id,
                               :platform, :size_bytes, :last_played_at,
                               :version, :raw) do
    def self.from_api(hash)
      new(name: hash["comment"], title_id: hash["titleId"],
          np_title_id: hash["npTitleId"], concept_id: hash["conceptId"],
          platform: hash["psPlatform"], size_bytes: hash["size"],
          last_played_at: Mapping.time(hash["lastAccessDateTime"]),
          version: hash["version"], raw: hash)
    end
  end
end
