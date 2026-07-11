# frozen_string_literal: true

module PSN
  # Accessibility notices for a concept, keyed by platform
  # (conceptRetrieveForAccessibilityFeatures). notices_by_platform is nil
  # when the publisher has not filled the section in.
  AccessibilityInfo = Data.define(:notices_by_platform, :platforms, :raw) do
    def self.from_api(hash)
      new(notices_by_platform: hash["accessibilityNoticesByPlatform"],
          platforms: hash["platforms"] || [], raw: hash)
    end
  end
end
