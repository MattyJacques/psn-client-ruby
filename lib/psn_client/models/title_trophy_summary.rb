# frozen_string_literal: true

module PSN
  TitleTrophySummary = Data.define(:np_title_id, :trophy_titles, :raw) do
    def self.from_api(hash)
      new(np_title_id: hash["npTitleId"],
          trophy_titles: (hash["trophyTitles"] || []).map { |t| TrophyTitle.from_api(t) },
          raw: hash)
    end
  end
end
