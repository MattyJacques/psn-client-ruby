# frozen_string_literal: true

module PSN
  PurchasedGame = Data.define(:name, :title_id, :platform, :concept_id, :entitlement_id,
                              :product_id, :image_url, :active, :downloadable,
                              :pre_order, :membership, :raw) do
    def self.from_api(hash)
      new(name: hash["name"], title_id: hash["titleId"], platform: hash["platform"],
          concept_id: hash["conceptId"], entitlement_id: hash["entitlementId"],
          product_id: hash["productId"], image_url: hash.dig("image", "url"),
          active: hash["isActive"] == true, downloadable: hash["isDownloadable"] == true,
          pre_order: hash["isPreOrder"] == true, membership: hash["membership"],
          raw: hash)
    end

    def active? = active
    def downloadable? = downloadable
    def pre_order? = pre_order
  end
end
