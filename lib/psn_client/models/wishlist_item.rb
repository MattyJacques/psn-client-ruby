# frozen_string_literal: true

module PSN
  # One PlayStation Store wishlist entry: either a released Product (has a
  # price) or an unreleased Concept (price is nil, platforms may be empty).
  # Prices are Sony's locale-formatted strings ("£64.99", "Included") — the
  # API returns no numeric amount.
  WishlistItem = Data.define(:name, :id, :concept, :platforms, :image_url,
                             :classification, :localized_classification,
                             :base_price, :discounted_price, :discount_text,
                             :free, :tied_to_subscription, :exclusive,
                             :service_branding, :upsell_service_branding,
                             :upsell_text, :sku_id, :raw) do
    def self.from_api(hash)
      price = hash["price"] || {}
      new(name: hash["name"], id: hash["id"], concept: hash["__typename"] == "Concept",
          platforms: hash["platforms"] || [], image_url: hash.dig("boxArt", "url"),
          classification: hash["storeDisplayClassification"],
          localized_classification: hash["localizedStoreDisplayClassification"],
          base_price: price["basePrice"], discounted_price: price["discountedPrice"],
          discount_text: price["discountText"], free: price["isFree"] == true,
          tied_to_subscription: price["isTiedToSubscription"] == true,
          exclusive: price["isExclusive"] == true,
          service_branding: price["serviceBranding"],
          upsell_service_branding: price["upsellServiceBranding"],
          upsell_text: price["upsellText"], sku_id: price["skuId"], raw: hash)
    end

    def concept? = concept
    def free? = free
    def tied_to_subscription? = tied_to_subscription
    def exclusive? = exclusive
  end
end
