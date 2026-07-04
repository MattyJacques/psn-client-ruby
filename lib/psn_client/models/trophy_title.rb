# frozen_string_literal: true

module PSN
  TrophyTitle = Data.define(:name, :np_communication_id, :np_service_name, :platform,
                            :progress, :earned_counts, :defined_counts, :raw) do
    def self.from_api(hash)
      new(name: hash["trophyTitleName"], np_communication_id: hash["npCommunicationId"],
          np_service_name: hash["npServiceName"], platform: hash["trophyTitlePlatform"],
          progress: hash["progress"],
          earned_counts: Mapping.grade_counts(hash["earnedTrophies"]),
          defined_counts: Mapping.grade_counts(hash["definedTrophies"]),
          raw: hash)
    end
  end
end
