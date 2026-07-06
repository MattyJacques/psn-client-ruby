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
      # The internal profiles endpoint rejects "me" as a path account ID
      # (HTTP 400), so the own account ID comes from the DMS device API first.
      ACCOUNT_ME_PATH = "/api/v1/devices/accounts/me"
      PROFILE_BY_ACCOUNT_PATH = "/api/userProfile/v1/internal/users/%s/profiles"
      ONLINE_ID_PATTERN = /\A[a-zA-Z0-9_-]{3,16}\z/

      def initialize(connection)
        @connection = connection
      end

      def find(online_id = nil)
        online_id = validate_online_id!(online_id || own_online_id)
        response = @connection.get(:community, format(PROFILE2_PATH, online_id),
                                   { "fields" => PROFILE2_FIELDS })
        Profile.from_api(response["profile"])
      end

      private

      def own_online_id
        @own_online_id ||= begin
          account_id = @connection.get(:dms, ACCOUNT_ME_PATH, {})["accountId"]
          @connection.get(:mobile, format(PROFILE_BY_ACCOUNT_PATH, account_id), {})["onlineId"]
        end
      end

      def validate_online_id!(online_id)
        return online_id if online_id.match?(ONLINE_ID_PATTERN)

        raise ArgumentError, "invalid PSN online ID: #{online_id.inspect}"
      end
    end
  end
end
