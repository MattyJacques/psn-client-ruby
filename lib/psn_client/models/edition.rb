# frozen_string_literal: true

module PSN
  # One purchasable edition of a concept (conceptRetrieveForCtasWithPrice):
  # the product plus the type and price of its first web store call-to-action
  # (PREORDER, BUY_NOW, ...). The CTA price hash matches Sony's SkuPrice shape,
  # so it reuses Price (fields absent from CTA prices, like skuId, map to nil).
  Edition = Data.define(:name, :id, :np_title_id, :invariant_name, :cta_type, :price, :raw) do
    def self.from_api(hash)
      cta = (hash["webctas"] || []).first
      price = cta && cta["price"]
      new(name: hash["name"], id: hash["id"], np_title_id: hash["npTitleId"],
          invariant_name: hash["invariantName"], cta_type: cta && cta["type"],
          price: price && Price.from_api(price), raw: hash)
    end
  end
end
