# frozen_string_literal: true

module PSN
  module Resources
    # Social graph and presence: friends, received friend requests, blocked
    # accounts and basic presence. Internal mobile-app endpoints under
    # /api/userProfile/v1/internal/users — undocumented Sony APIs that can
    # change without notice; verify changes with bin/smoke.
    class Social
      PRESENCE_PATH = "/api/userProfile/v1/internal/users/%s/basicPresences"
      FRIENDS_PATH = "/api/userProfile/v1/internal/users/%s/friends"
      REQUESTS_PATH = "/api/userProfile/v1/internal/users/me/friends/receivedRequests"
      BLOCKS_PATH = "/api/userProfile/v1/internal/users/me/blocks"
      FRIENDSHIP_PATH = "/api/userProfile/v1/internal/users/me/friends/%s/summary"
      AVAILABLE_PATH = "/api/userProfile/v1/internal/users/me/friends/subscribing/availableToPlay"
      # No server-side cap has been verified live for these list endpoints;
      # 100 is a conservative page size, not a known limit.
      PAGE_SIZE = 100

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

      # Account IDs on the user's friends list, as bare strings — the payload
      # carries no profile data. A public account-ID→profile lookup is a possible
      # follow-up. 403 on a privacy-restricted account surfaces as PSN::PrivacyError.
      def friends(online_id = nil)
        id_pages(format(FRIENDS_PATH, @users.account_id(online_id)), "friends")
      end

      # Account IDs with pending friend requests to the authenticated account.
      def friend_requests
        id_pages(REQUESTS_PATH, "receivedRequests")
      end

      # Account IDs the authenticated account has blocked. The response
      # carries no totalItemCount, so paging stops on the first empty page.
      def blocked
        id_pages(BLOCKS_PATH, "blockList")
      end

      # PROVISIONAL: friendship summary between the authenticated account and
      # another user. Returns the raw response body until the payload shape is
      # confirmed via bin/smoke; the model mapping lands once that is known.
      def friendship(online_id)
        @connection.get(:mobile, format(FRIENDSHIP_PATH, @users.account_id(online_id)), {})
      end

      # PROVISIONAL: friends currently available to play. Raw body until the
      # payload shape is confirmed via bin/smoke.
      def available_to_play
        @connection.get(:mobile, AVAILABLE_PATH, {})
      end

      private

      def id_pages(path, key)
        Paginator.offset(page_size: PAGE_SIZE) do |limit, offset|
          response = @connection.get(:mobile, path, { "limit" => limit, "offset" => offset })
          [response[key] || [], response["totalItemCount"]]
        end
      end
    end
  end
end
