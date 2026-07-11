# frozen_string_literal: true

module PSN
  # An EMS component's link ("go to this category/product/view").
  StoreLink = Data.define(:target, :type, :localized_name, :raw) do
    def self.from_api(hash)
      new(target: hash["target"], type: hash["type"],
          localized_name: hash["localizedName"], raw: hash)
    end
  end

  # One EMS view component. Components are heterogeneous (IMAGE, SIMPLE_TEXT,
  # GRID, ...) so this is a single flexible shape — members that don't apply
  # to a component type are nil. GRID components carry category_id,
  # facet_list and sort_order_list; localized_name values on links double as
  # localizedKeyId inputs for Browse#default_view.
  StoreComponent = Data.define(:id, :component_type, :name, :text, :image_url,
                               :ordinal, :category_id, :facet_list,
                               :sort_order_list, :link, :raw) do
    def self.from_api(hash)
      link = hash["link"]
      new(id: hash["id"], component_type: hash["componentType"],
          name: hash["name"], text: hash["text"], image_url: hash["imageUrl"],
          ordinal: hash["ordinal"], category_id: hash["categoryId"],
          facet_list: hash["facetList"], sort_order_list: hash["sortOrderList"],
          link: link && StoreLink.from_api(link), raw: hash)
    end
  end

  # One EMS store view (a screenful of components).
  StoreView = Data.define(:id, :type, :purpose, :components, :raw) do
    def self.from_api(hash)
      new(id: hash["id"], type: hash["type"], purpose: hash["purpose"],
          components: (hash["components"] || []).map { |c| StoreComponent.from_api(c) },
          raw: hash)
    end
  end
end
