# frozen_string_literal: true

module PSN
  # A Sony SkuPrice: locale-formatted display strings ("$69.99") plus the
  # numeric minor-unit values ("basePriceValue" 6999 = $69.99).
  Price = Data.define(:base_price, :base_price_value, :discounted_price,
                      :discounted_value, :discount_text, :currency_code,
                      :end_time, :free, :tied_to_subscription, :exclusive,
                      :service_branding, :sku_id, :raw) do
    def self.from_api(hash)
      new(base_price: hash["basePrice"], base_price_value: hash["basePriceValue"],
          discounted_price: hash["discountedPrice"], discounted_value: hash["discountedValue"],
          discount_text: hash["discountText"], currency_code: hash["currencyCode"],
          end_time: Mapping.time(hash["endTime"]), free: hash["isFree"] == true,
          tied_to_subscription: hash["isTiedToSubscription"] == true,
          exclusive: hash["isExclusive"] == true,
          service_branding: hash["serviceBranding"], sku_id: hash["skuId"], raw: hash)
    end

    def free? = free
    def tied_to_subscription? = tied_to_subscription
    def exclusive? = exclusive

    def discounted?
      !!(base_price_value && discounted_value && discounted_value < base_price_value)
    end
  end
end
