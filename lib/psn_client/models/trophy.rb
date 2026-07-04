# frozen_string_literal: true

module PSN
  Trophy = Data.define(:id, :name, :detail, :grade, :hidden, :rarity, :earned, :earned_at, :raw) do
    def self.from_api(hash)
      new(id: hash["trophyId"], name: hash["trophyName"], detail: hash["trophyDetail"],
          grade: hash["trophyType"]&.to_sym, hidden: hash["trophyHidden"],
          rarity: hash["trophyEarnedRate"]&.to_f,
          earned: hash.fetch("earned", false),
          earned_at: Mapping.time(hash["earnedDateTime"]),
          raw: hash)
    end

    def earned? = earned
  end
end
