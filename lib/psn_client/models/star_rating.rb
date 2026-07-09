# frozen_string_literal: true

module PSN
  # Store user ratings for a product. distribution maps star count (5..1)
  # to the percentage of ratings with that score.
  StarRating = Data.define(:average, :average_display, :total, :distribution, :raw) do
    def self.from_api(hash)
      distribution = (hash["ratingsDistribution"] || []).to_h do |entry|
        [entry["rating"], entry["percentageRaw"]]
      end
      new(average: hash["averageRating"], average_display: hash["averageRatingForDisplay"],
          total: hash["totalRatingsCount"], distribution: distribution, raw: hash)
    end
  end
end
