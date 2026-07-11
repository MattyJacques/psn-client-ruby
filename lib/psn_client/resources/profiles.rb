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
      SHARE_PATH = "/api/cpss/v1/share/profile/%s"
      ONLINE_ID_PATTERN = /\A[a-zA-Z0-9_-]{3,16}\z/

      def initialize(connection, users)
        @connection = connection
        @users = users
      end

      def find(online_id = nil)
        online_id = validate_online_id!(online_id || own_online_id)
        response = @connection.get(:community, format(PROFILE2_PATH, online_id),
                                   { "fields" => PROFILE2_FIELDS })
        Profile.from_api(response["profile"])
      end

      # Shareable public-profile URL and its QR code image. The cpss endpoint
      # has not been verified to accept "me" as a path ID (its sibling
      # internal-profiles endpoint rejects it), so the own numeric account ID
      # is resolved via the DMS device API first.
      def shareable_link(online_id = nil)
        account_id = online_id ? @users.account_id(online_id) : own_account_id
        ShareableLink.from_api(@connection.get(:mobile, format(SHARE_PATH, account_id), {}))
      end

      # Profile for a Sony numeric account ID — friends lists and presence
      # responses return bare IDs. Leaner shape than #find (internal mobile
      # endpoint; rejects "me", so pass a real ID).
      def find_by_account_id(account_id)
        BasicProfile.from_api(@connection.get(:mobile, format(PROFILE_BY_ACCOUNT_PATH, account_id), {}))
      end

      private

      def own_account_id
        @own_account_id ||= @connection.get(:dms, ACCOUNT_ME_PATH, {})["accountId"]
      end

      def own_online_id
        @own_online_id ||=
          @connection.get(:mobile, format(PROFILE_BY_ACCOUNT_PATH, own_account_id), {})["onlineId"]
      end

      def validate_online_id!(online_id)
        return online_id if online_id.match?(ONLINE_ID_PATTERN)

        raise ArgumentError, "invalid PSN online ID: #{online_id.inspect}"
      end
    end
  end
end
