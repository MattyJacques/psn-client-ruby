# frozen_string_literal: true

module PSN
  module Resources
    # Message groups and DMs for the AUTHENTICATED account — read-only.
    # Undocumented mobile-app endpoints (/api/gamingLoungeGroups/v1) that can
    # change without notice; verify changes with bin/smoke.
    #
    # Quirks confirmed by live probe 2026-07-10:
    # - every call needs an Accept-Language header, or Sony 400s with
    #   {"error"=>{"code"=>2285569,"message"=>"Bad Request (header: Accept-Language)"}}
    #   (same quirk resources/devices.rb documents for the storage endpoint).
    # - a group's detail lives at .../members/me/groups/%s, nested the same as
    #   the list endpoint — .../groups/%s (no members/me) returns HTTP 405.
    # - a group's main thread id equals the group id.
    class Groups
      HEADERS = { "Accept-Language" => "en-us" }.freeze
      GROUPS_PATH = "/api/gamingLoungeGroups/v1/members/me/groups"
      GROUP_PATH = "/api/gamingLoungeGroups/v1/members/me/groups/%s"
      MESSAGES_PATH = "/api/gamingLoungeGroups/v1/members/me/groups/%s/threads/%s/messages"
      GROUP_FIELDS = "groupName,groupIcon,members,mainThread"
      PAGE_SIZE = 100
      MESSAGES_PAGE_SIZE = 20
      # Conversation continuation param confirmed live 2026-07-10: passing the
      # previous page's "next" value back as "before" advanced to the
      # next-older page; passing it back as "next" or "cursor" both returned
      # the same first page unchanged.
      CURSOR_PARAM = "before"

      def initialize(connection)
        @connection = connection
      end

      # All groups the account participates in. The response carries no total
      # count (no totalResults/total field); paging stops on the first empty
      # page. List-level members only carry accountId/onlineId — role is nil
      # here (see #find for the full member/thread detail).
      def all
        paginator = Paginator.offset(page_size: PAGE_SIZE) do |limit, offset|
          response = @connection.get(:mobile, GROUPS_PATH,
                                     { "includeFields" => "members", "limit" => limit, "offset" => offset },
                                     headers: HEADERS)
          [response["groups"] || [], nil]
        end
        paginator.map { |g| Group.from_api(g) }
      end

      # One group with name, members (with role) and its latest message.
      def find(group_id)
        response = @connection.get(:mobile, format(GROUP_PATH, group_id),
                                   { "includeFields" => GROUP_FIELDS }, headers: HEADERS)
        Group.from_api(response)
      end

      # Message history, newest first, walking back through history until
      # reachedEndOfPage.
      def messages(group_id)
        path = format(MESSAGES_PATH, group_id, group_id)
        paginator = Paginator.cursor do |cursor|
          params = { "limit" => MESSAGES_PAGE_SIZE }
          params[CURSOR_PARAM] = cursor if cursor
          response = @connection.get(:mobile, path, params, headers: HEADERS)
          [response["messages"] || [], response["reachedEndOfPage"] ? nil : response["next"]]
        end
        paginator.map { |m| GroupMessage.from_api(m) }
      end
    end
  end
end
