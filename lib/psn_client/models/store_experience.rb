# frozen_string_literal: true

module PSN
  # One entry of the EMS store nav tree. Sony encodes the target as
  # "EMS_VIEW:<uuid>"; view_collection_id is that uuid (nil for other link
  # kinds), ready to pass to Browse#views.
  NavItem = Data.define(:id, :name, :type, :view_collection_id, :raw) do
    def self.from_api(hash)
      link = hash["link"].to_s
      new(id: hash["id"], name: hash["name"], type: hash["type"],
          view_collection_id: link.start_with?("EMS_VIEW:") ? link.delete_prefix("EMS_VIEW:") : nil,
          raw: hash)
    end
  end

  # The EMS store navigation root (emsExperienceRetrieve): the store's
  # top-level tabs ("Latest", "Collections", "Browse", ...).
  StoreExperience = Data.define(:id, :nav_items, :raw) do
    def self.from_api(hash)
      items = (hash.dig("navTree", "items") || []).map { |item| NavItem.from_api(item) }
      new(id: hash["id"], nav_items: items, raw: hash)
    end
  end
end
