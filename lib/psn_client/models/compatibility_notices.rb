# frozen_string_literal: true

module PSN
  # Play-compatibility and accessibility notices for a concept
  # (conceptRetrieveForCompatibilityNotices). Sony keys each notice list by
  # platform ("Common", "PS4", "PS5", "PSPC") with null for absent platforms;
  # both maps are flattened here into {platform:, type:, value:} entries.
  # Compatibility lives at concept level; accessibility only appears on the
  # default product (the concept-level key was null in live testing).
  CompatibilityNotices = Data.define(:compatibility, :accessibility, :raw) do
    def self.from_api(hash)
      new(compatibility: flatten(hash["compatibilityNoticesByPlatform"]),
          accessibility: flatten(hash.dig("defaultProduct", "accessibilityNoticesByPlatform")),
          raw: hash)
    end

    def self.flatten(by_platform)
      (by_platform || {}).flat_map do |platform, notices|
        next [] if platform == "__typename" || notices.nil?

        notices.map { |n| { platform: platform, type: n["type"], value: n["value"] } }
      end
    end
    private_class_method :flatten
  end
end
