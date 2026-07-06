# frozen_string_literal: true

module PSN
  LibraryTitle = Data.define(:name, :title_id, :platform, :concept_id, :entitlement_id,
                             :product_id, :image_url, :last_played_at, :active,
                             :subscription_service, :raw) do
    def self.from_api(hash)
      new(name: hash["name"], title_id: hash["titleId"], platform: hash["platform"],
          concept_id: hash["conceptId"], entitlement_id: hash["entitlementId"],
          product_id: hash["productId"], image_url: hash.dig("image", "url"),
          last_played_at: Mapping.time(hash["lastPlayedDateTime"]),
          active: hash["isActive"] == true,
          subscription_service: Mapping.subscription(hash["subscriptionService"]),
          raw: hash)
    end

    def active? = active
  end
end
