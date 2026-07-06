# frozen_string_literal: true

module PSN
  AVATAR_SIZE_ORDER = %w[xl l m s].freeze
  private_constant :AVATAR_SIZE_ORDER

  Profile = Data.define(:online_id, :account_id, :avatar_url, :plus, :about_me, :languages,
                        :verified, :trophy_summary, :online, :platform, :last_online_at, :raw) do
    def self.from_api(hash)
      presence = hash.dig("presences", 0) || {}
      new(online_id: hash["onlineId"], account_id: hash["accountId"],
          avatar_url: largest_avatar(hash["avatarUrls"]),
          plus: hash["plus"].to_i.positive?, about_me: hash["aboutMe"],
          languages: hash["languagesUsed"], verified: hash["isOfficiallyVerified"] == true,
          trophy_summary: summary(hash["trophySummary"]),
          online: presence["onlineStatus"] == "online", platform: presence["platform"],
          last_online_at: Mapping.time(presence["lastOnlineDate"]), raw: hash)
    end

    # profile2 nests the summary under different keys than the trophy API
    # ("level" instead of "trophyLevel", no tier), so map it by hand.
    def self.summary(hash)
      return nil unless hash

      TrophySummary.new(level: hash["level"], progress: hash["progress"], tier: nil,
                        earned_counts: Mapping.grade_counts(hash["earnedTrophies"]), raw: hash)
    end

    def self.largest_avatar(urls)
      return nil if urls.nil? || urls.empty?

      by_size = urls.to_h { |u| [u["size"], u["avatarUrl"]] }
      AVATAR_SIZE_ORDER.filter_map { |size| by_size[size] }.first || urls.first["avatarUrl"]
    end

    def plus? = plus
    def verified? = verified
    def online? = online
  end
end
