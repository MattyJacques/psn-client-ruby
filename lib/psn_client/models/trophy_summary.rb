# frozen_string_literal: true

module PSN
  TrophySummary = Data.define(:level, :progress, :tier, :earned_counts, :raw) do
    def self.from_api(hash)
      new(level: hash["trophyLevel"], progress: hash["progress"], tier: hash["tier"],
          earned_counts: Mapping.grade_counts(hash["earnedTrophies"]),
          raw: hash)
    end
  end
end
