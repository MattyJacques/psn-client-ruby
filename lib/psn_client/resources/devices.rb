# frozen_string_literal: true

module PSN
  module Resources
    # Devices registered to the authenticated account: the DMS device ledger
    # and the mobile app's console storage endpoint. Both are undocumented
    # Sony APIs; verify changes with bin/smoke.
    class Devices
      DEVICES_PATH = "/api/v1/devices/accounts/me"
      DEVICES_PARAMS = { "includeFields" => "device,systemData",
                         "platform" => "PS5,PS4,PS3,PSVita" }.freeze
      STORAGE_PATH = "/api/cloudAssistedNavigation/v2/users/me/clients"
      # The storage endpoint documents an Accept-Language header (andshrew's
      # Console.md); the locale only affects display strings.
      STORAGE_HEADERS = { "Accept-Language" => "en-us" }.freeze

      def initialize(connection)
        @connection = connection
      end

      # Consoles and devices registered to the authenticated account.
      def all
        response = @connection.get(:dms, DEVICES_PATH, DEVICES_PARAMS)
        (response["accountDevices"] || []).map { |device| Device.from_api(device) }
      end

      # PROVISIONAL: console storage usage. andshrew's Console.md documents a
      # single platform value (e.g. "PS5"); whether lists work is unverified.
      # Returns the raw response body until the payload shape is confirmed
      # via bin/smoke; the model mapping lands once that is known.
      def storage(platform: "PS5")
        params = { "includeFields" => "device,systemData", "platform" => platform }
        @connection.get(:mobile, STORAGE_PATH, params, headers: STORAGE_HEADERS)
      end
    end
  end
end
