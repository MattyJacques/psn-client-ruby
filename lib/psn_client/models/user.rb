# frozen_string_literal: true

module PSN
  # A PSN player as seen by social/graph endpoints. account_id is nil when
  # the source payload does not carry it (friends-who-play profiles don't).
  User = Data.define(:online_id, :account_id, :display_name, :avatar_url,
                     :ps_plus, :verified, :raw) do
    def self.from_api(hash)
      new(online_id: hash["onlineId"], account_id: hash["accountId"],
          display_name: hash["name"],
          avatar_url: hash.dig("profilePicture", "url") || hash.dig("avatar", "url"),
          ps_plus: hash["isPsPlusMember"] == true,
          verified: hash["isOfficiallyVerified"] == true, raw: hash)
    end

    def ps_plus? = ps_plus
    def verified? = verified
  end
end
