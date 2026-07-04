# frozen_string_literal: true

module PSN
  module Resources
    class Trophies
      TITLES_PATH = "/api/trophy/v1/users/%s/trophyTitles"
      SUMMARY_PATH = "/api/trophy/v1/users/%s/trophySummary"
      DEFINITIONS_PATH = "/api/trophy/v1/npCommunicationIds/%s/trophyGroups/all/trophies"
      EARNED_PATH = "/api/trophy/v1/users/%s/npCommunicationIds/%s/trophyGroups/all/trophies"
      PAGE_SIZE = 100

      def initialize(connection, users)
        @connection = connection
        @users = users
      end

      def titles(online_id = nil)
        account_id = @users.account_id(online_id)
        paginator = Paginator.offset(page_size: PAGE_SIZE) do |limit, offset|
          response = @connection.get(:mobile, format(TITLES_PATH, account_id),
                                     { "limit" => limit, "offset" => offset })
          [response["trophyTitles"] || [], response["totalItemCount"]]
        end
        paginator.map { |title| TrophyTitle.from_api(title) }
      end

      def summary(online_id = nil)
        account_id = @users.account_id(online_id)
        TrophySummary.from_api(@connection.get(:mobile, format(SUMMARY_PATH, account_id), {}))
      end

      # All trophies for one title, each merged with the user's earned status.
      def earned(online_id = nil, np_communication_id:, platform: nil)
        account_id = @users.account_id(online_id)
        params = service_params(platform)
        definitions = @connection.get(:mobile, format(DEFINITIONS_PATH, np_communication_id), params)
        earned = @connection.get(:mobile, format(EARNED_PATH, account_id, np_communication_id), params)
        merge(definitions["trophies"] || [], earned["trophies"] || []).lazy
      end

      private

      # PS5 titles use the default trophy2 service; everything older needs
      # an explicit npServiceName=trophy.
      def service_params(platform)
        return {} if platform.nil? || platform.to_s.upcase.start_with?("PS5")

        { "npServiceName" => "trophy" }
      end

      def merge(definitions, earned)
        earned_by_id = earned.to_h { |t| [t["trophyId"], t] }
        definitions.map { |d| Trophy.from_api(d.merge(earned_by_id[d["trophyId"]] || {})) }
      end
    end
  end
end
