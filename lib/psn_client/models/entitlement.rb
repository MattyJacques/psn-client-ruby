# frozen_string_literal: true

module PSN
  # NOTE: the entitlements endpoint is undocumented; mapping is deliberately
  # defensive and everything unmapped stays available in #raw.
  Entitlement = Data.define(:id, :name, :type, :platform, :acquired_at, :raw) do
    def self.from_api(hash)
      meta_type = hash.dig("game_meta", "type")
      new(id: hash["id"],
          name: hash.dig("game_meta", "name") || hash["product_name"],
          type: meta_type || hash["entitlement_type"]&.to_s,
          platform: platform_from(meta_type),
          acquired_at: Mapping.time(hash["active_date"] || hash["activation_date"]),
          raw: hash)
    end

    def self.platform_from(type)
      type&.[](/\A(?:PS[345P]|PSP|VITA)/)
    end
  end
end
