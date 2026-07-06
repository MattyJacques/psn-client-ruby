# frozen_string_literal: true

module PSN
  TrophyGroup = Data.define(:group_id, :name, :icon_url, :defined_counts,
                            :earned_counts, :progress, :raw) do
    def self.from_api(hash)
      new(group_id: hash["trophyGroupId"], name: hash["trophyGroupName"],
          icon_url: hash["trophyGroupIconUrl"],
          defined_counts: Mapping.grade_counts(hash["definedTrophies"]),
          earned_counts: Mapping.grade_counts(hash["earnedTrophies"]),
          progress: hash["progress"], raw: hash)
    end
  end
end
