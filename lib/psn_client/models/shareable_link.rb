# frozen_string_literal: true

module PSN
  # A shareable public-profile link: the share URL, its QR-code image and
  # the page the QR code resolves to.
  ShareableLink = Data.define(:url, :image_url, :destination, :raw) do
    def self.from_api(hash)
      new(url: hash["shareUrl"], image_url: hash["shareImageUrl"],
          destination: hash["shareImageUrlDestination"], raw: hash)
    end
  end
end
