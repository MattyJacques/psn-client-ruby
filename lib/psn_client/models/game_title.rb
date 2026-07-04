# frozen_string_literal: true

module PSN
  GameTitle = Data.define(:name, :title_id, :platform, :play_count,
                          :first_played_at, :last_played_at, :play_duration, :raw) do
    def self.from_api(hash)
      new(name: hash["name"], title_id: hash["titleId"],
          platform: Mapping.platform(hash["category"]),
          play_count: hash["playCount"],
          first_played_at: Mapping.time(hash["firstPlayedDateTime"]),
          last_played_at: Mapping.time(hash["lastPlayedDateTime"]),
          play_duration: Mapping.duration_seconds(hash["playDuration"]),
          raw: hash)
    end
  end
end
