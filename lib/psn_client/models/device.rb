# frozen_string_literal: true

module PSN
  # A console or device registered to the account (DMS device ledger).
  Device = Data.define(:device_id, :device_type, :activation_type, :activated_at, :raw) do
    def self.from_api(hash)
      new(device_id: hash["deviceId"], device_type: hash["deviceType"],
          activation_type: hash["activationType"],
          activated_at: Mapping.time(hash["activationDate"]), raw: hash)
    end
  end
end
