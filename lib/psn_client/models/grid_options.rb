# frozen_string_literal: true

module PSN
  # One selectable facet value ("Full Game", 7146 items).
  FacetValue = Data.define(:key, :display_name, :count, :raw) do
    def self.from_api(hash)
      new(key: hash["key"], display_name: hash["displayName"],
          count: hash["count"], raw: hash)
    end
  end

  # One grid facet ("Type", "Price") with its selectable values.
  Facet = Data.define(:name, :display_name, :values, :raw) do
    def self.from_api(hash)
      new(name: hash["name"], display_name: hash["displayName"],
          values: (hash["values"] || []).map { |value| FacetValue.from_api(value) },
          raw: hash)
    end
  end

  # One grid sort order ("Best Selling", descending).
  SortOption = Data.define(:name, :display_name, :ascending, :raw) do
    def self.from_api(hash)
      new(name: hash["name"], display_name: hash["displayName"],
          ascending: hash["isAscending"], raw: hash)
    end
  end

  # A category grid's browse controls (categoryGridRetrieve minus products):
  # available facets with per-value counts, sort orders, and the total
  # product count.
  GridOptions = Data.define(:facets, :sorting_options, :total_count, :raw) do
    def self.from_api(hash)
      new(facets: (hash["facetOptions"] || []).map { |facet| Facet.from_api(facet) },
          sorting_options: (hash["sortingOptions"] || []).map { |sort| SortOption.from_api(sort) },
          total_count: hash.dig("pageInfo", "totalCount"), raw: hash)
    end
  end
end
