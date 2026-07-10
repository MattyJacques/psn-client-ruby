# frozen_string_literal: true

module PSN
  # A title from a presence's now-playing list. The icon lives under either
  # npTitleIconUrl or conceptIconUrl depending on the title's generation.
  PresenceTitle = Data.define(:np_title_id, :name, :format, :launch_platform, :icon_url, :raw) do
    def self.from_api(hash)
      new(np_title_id: hash["npTitleId"], name: hash["titleName"],
          format: hash["format"], launch_platform: hash["launchPlatform"],
          icon_url: hash["npTitleIconUrl"] || hash["conceptIconUrl"], raw: hash)
    end
  end

  # A user's basic presence: availability, online status, platform and the
  # titles they are playing right now.
  Presence = Data.define(:availability, :online, :platform, :last_online_at, :now_playing, :raw) do
    def self.from_api(hash)
      info = hash["primaryPlatformInfo"] || {}
      new(availability: hash["availability"],
          online: info["onlineStatus"] == "online",
          platform: info["platform"],
          last_online_at: Mapping.time(info["lastOnlineDate"]),
          now_playing: (hash["gameTitleInfoList"] || []).map { |t| PresenceTitle.from_api(t) },
          raw: hash)
    end

    def online? = online
    def available? = availability == "availableToPlay"
  end
end
