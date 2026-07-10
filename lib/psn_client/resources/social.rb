# frozen_string_literal: true

module PSN
  module Resources
    # Social graph and presence: friends, received friend requests, blocked
    # accounts and basic presence. Internal mobile-app endpoints under
    # /api/userProfile/v1/internal/users — undocumented Sony APIs that can
    # change without notice; verify changes with bin/smoke.
    class Social
      PRESENCE_PATH = "/api/userProfile/v1/internal/users/%s/basicPresences"

      def initialize(connection, users)
        @connection = connection
        @users = users
      end

      # Availability, online status, platform and now-playing titles. 403 on
      # a privacy-restricted account surfaces as PSN::PrivacyError.
      def presence(online_id = nil)
        path = format(PRESENCE_PATH, @users.account_id(online_id))
        response = @connection.get(:mobile, path, { "type" => "primary" })
        Presence.from_api(response["basicPresence"] || {})
      end
    end
  end
end
