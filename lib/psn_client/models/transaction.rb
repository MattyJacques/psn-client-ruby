# frozen_string_literal: true

module PSN
  # NOTE: the transaction-history endpoint is undocumented; mapping is
  # deliberately defensive and everything unmapped stays available in #raw.
  Transaction = Data.define(:transaction_id, :date, :description, :amount,
                            :currency, :payment_method, :type, :raw) do
    def self.from_api(hash)
      total = total_price(hash)
      new(transaction_id: hash["transactionId"] || hash["orderId"],
          date: Mapping.time(hash["transactionDate"] || hash["orderDate"]),
          description: description_from(hash),
          amount: total["value"]&.to_i,
          currency: total["currencyCode"],
          payment_method: hash.dig("paymentMethodInfo", "displayName") || hash["paymentMethod"],
          type: hash["transactionType"] || hash["orderType"],
          raw: hash)
    end

    def self.total_price(hash)
      hash["totalPrice"] || hash.dig("invoice", "totalAmount") || {}
    end

    def self.description_from(hash)
      items = hash["transactionItems"] || hash["orderItems"] || []
      names = items.filter_map { |item| item["itemName"] || item["skuName"] }
      names.empty? ? hash["description"] : names.join(", ")
    end
  end
end
