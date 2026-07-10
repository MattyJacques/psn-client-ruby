# frozen_string_literal: true

module PSN
  # One PS Plus subscription offer for a tier (featuresRetrieve): the plan
  # title/duration and its price. Sony's SubscriptionPrice is a different
  # shape from SkuPrice, so price fields are flattened into members here
  # rather than reusing Price.
  PlusOffer = Data.define(:title, :duration, :description, :sku_id, :cta_label,
                          :trial, :active_subscription, :base_price, :base_price_value,
                          :discounted_price, :discounted_value, :currency_code, :raw) do
    def self.from_api(hash)
      price = hash["price"] || {}
      new(title: hash["title"], duration: hash["subscriptionDuration"],
          description: hash["description"], sku_id: hash["skuId"],
          cta_label: hash["ctaLabel"], trial: hash["isTrial"] == true,
          active_subscription: hash["isActiveSubscription"] == true,
          base_price: price["basePrice"], base_price_value: price["basePriceValue"],
          discounted_price: price["discountedPrice"], discounted_value: price["discountedValue"],
          currency_code: price["currencyCode"], raw: hash)
    end

    def trial? = trial
    def active_subscription? = active_subscription
  end
end
