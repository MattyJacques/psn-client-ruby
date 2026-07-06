# frozen_string_literal: true

module PSN
  module Resources
    # Rich user profiles via the legacy community profile2 endpoint (the
    # newer mobile profile API returns far fewer fields). For the
    # authenticated account the own online ID is resolved first, so every
    # caller gets the same rich shape back.
    class Profiles
      PROFILE2_PATH = "/userProfile/v1/users/%s/profile2"
      PROFILE2_FIELDS = "npId,onlineId,accountId,avatarUrls,plus,aboutMe,languagesUsed," \
                        "trophySummary(@default,level,progress,earnedTrophies)," \
                        "isOfficiallyVerified,primaryOnlineStatus," \
                        "presences(@default,@titleInfo,platform,lastOnlineDate)"
      ME_PATH = "/api/userProfile/v1/internal/users/me/profiles"

      def initialize(connection)
        @connection = connection
      end

      def find(online_id = nil)
        online_id ||= own_online_id
        response = @connection.get(:community, format(PROFILE2_PATH, online_id),
                                   { "fields" => PROFILE2_FIELDS })
        Profile.from_api(response["profile"])
      end

      private

      def own_online_id
        @own_online_id ||= @connection.get(:mobile, ME_PATH, {})["onlineId"]
      end
    end
  end
end
