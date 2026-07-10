# frozen_string_literal: true

module PSN
  # One console from the storage endpoint: embedded-storage byte counts plus
  # the titles installed on it.
  ConsoleStorage = Data.define(:name, :platform, :duid, :free_bytes, :total_bytes,
                               :updated_at, :installed_titles, :raw) do
    def self.from_api(hash)
      embedded = hash.dig("systemData", "storage", "embedded") || {}
      titles = hash.dig("systemData", "installedTitles", "titles") || []
      new(name: hash.dig("device", "name"), platform: hash["platform"],
          duid: hash["duid"], free_bytes: embedded["freeSize"],
          total_bytes: embedded["totalSize"],
          updated_at: Mapping.time(hash["updatedDateTime"]),
          installed_titles: titles.map { |title| InstalledTitle.from_api(title) },
          raw: hash)
    end
  end
end
