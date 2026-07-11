# frozen_string_literal: true

module PSN
  # The mobile API's internal profile shape (userProfile/v1/internal
  # .../profiles) — leaner than the legacy profile2 Profile. personalDetail
  # is only present for the caller's own account.
  BasicProfile = Data.define(:online_id, :first_name, :last_name, :about_me,
                             :avatar_urls, :languages, :plus,
                             :officially_verified, :me, :raw) do
    def self.from_api(hash)
      detail = hash["personalDetail"] || {}
      new(online_id: hash["onlineId"], first_name: detail["firstName"],
          last_name: detail["lastName"], about_me: hash["aboutMe"],
          avatar_urls: (hash["avatars"] || []).to_h { |a| [a["size"], a["url"]] },
          languages: hash["languages"] || [], plus: hash["isPlus"],
          officially_verified: hash["isOfficiallyVerified"], me: hash["isMe"],
          raw: hash)
    end

    def plus? = plus
    def officially_verified? = officially_verified
    def me? = me
  end
end
