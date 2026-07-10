# frozen_string_literal: true

module PSN
  # Relationship between the authenticated account and another user.
  # friend_relation is e.g. "friend" or "no-relationship".
  FriendshipSummary = Data.define(:friend_relation, :personal_detail_sharing,
                                  :friends_count, :mutual_friends_count, :raw) do
    def self.from_api(hash)
      new(friend_relation: hash["friendRelation"],
          personal_detail_sharing: hash["personalDetailSharing"],
          friends_count: hash["friendsCount"],
          mutual_friends_count: hash["mutualFriendsCount"], raw: hash)
    end

    def friend? = friend_relation == "friend"
  end
end
