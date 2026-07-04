# frozen_string_literal: true

require "time"

module PSN
  # Shared helpers for converting Sony API values to Ruby types.
  module Mapping
    module_function

    def time(value)
      value && Time.iso8601(value)
    end

    # "PT15H2M32S" -> 54152 (seconds)
    def duration_seconds(value)
      return nil unless value

      match = value.match(/PT(?:(\d+)H)?(?:(\d+)M)?(?:(\d+(?:\.\d+)?)S)?/)
      return nil unless match

      (match[1].to_i * 3600) + (match[2].to_i * 60) + match[3].to_f.round
    end

    def grade_counts(hash)
      return nil unless hash

      { bronze: hash["bronze"].to_i, silver: hash["silver"].to_i,
        gold: hash["gold"].to_i, platinum: hash["platinum"].to_i }
    end

    GAME_PLATFORMS = {
      "ps5_native_game" => "PS5", "ps4_game" => "PS4", "ps3_game" => "PS3",
      "psvita_game" => "PS Vita", "pspc_game" => "PC"
    }.freeze

    # "ps5_native_game" -> "PS5"; unknown categories pass through unchanged.
    def platform(category)
      GAME_PLATFORMS.fetch(category, category)
    end
  end
end
