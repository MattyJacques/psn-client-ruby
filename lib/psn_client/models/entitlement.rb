# frozen_string_literal: true

module PSN
  # NOTE: the entitlements endpoint is undocumented; mapping is deliberately
  # defensive and everything unmapped stays available in #raw.
  Entitlement = Data.define(:id, :name, :type, :platform, :product_id, :title_id, :acquired_at, :raw) do
    def self.from_api(hash)
      new(id: hash["id"],
          name: hash.dig("titleMeta", "name") || hash.dig("conceptMeta", "name") || hash.dig("gameMeta", "name"),
          type: hash.dig("gameMeta", "type"),
          platform: hash.dig("entitlementAttributes", 0, "platformId")&.upcase,
          product_id: hash["productId"],
          title_id: hash.dig("titleMeta", "titleId"),
          acquired_at: Mapping.time(hash["activeDate"]),
          raw: hash)
    end
  end
end
