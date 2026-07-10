# frozen_string_literal: true

module PSN
  # One entry of a Sony media array (conceptRetrieveForMedia): a screenshot,
  # video or art asset, identified by its role (SCREENSHOT, PREVIEW, LOGO...).
  MediaItem = Data.define(:role, :type, :url, :raw) do
    def self.from_api(hash)
      new(role: hash["role"], type: hash["type"], url: hash["url"], raw: hash)
    end

    def image? = type == "IMAGE"
    def video? = type == "VIDEO"
  end
end
