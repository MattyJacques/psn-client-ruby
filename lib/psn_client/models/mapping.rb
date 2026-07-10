# frozen_string_literal: true

require "time"

module PSN
  # Shared helpers for converting Sony API values to Ruby types.
  module Mapping
    module_function

    def time(value)
      value && Time.iso8601(value)
    end

    # Sony epoch-milliseconds string ("1751980000000") -> UTC Time.
    def epoch_ms(value)
      value && Time.at(Rational(value.to_i, 1000)).utc
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

    # "NONE" means a regular owned title -> nil; real services ("PS_PLUS", ...)
    # pass through unchanged.
    def subscription(value)
      value == "NONE" ? nil : value
    end

    # The store's box-art equivalent from a Sony media array; prefers the
    # GAMEHUB_COVER_ART image role and falls back to any image.
    def cover_url(media)
      images = media.select { |m| m["type"] == "IMAGE" }
      cover = images.find { |m| m["role"] == "GAMEHUB_COVER_ART" } || images.first
      cover && cover["url"]
    end

    # The value of the first description entry of the given type
    # ("SHORT"/"LONG"/"LEGAL") from a Sony descriptions array.
    def description(hash, type)
      entry = (hash["descriptions"] || []).find { |d| d["type"] == type }
      entry && entry["value"]
    end
  end
end
