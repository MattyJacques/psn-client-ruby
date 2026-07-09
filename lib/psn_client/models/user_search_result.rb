# frozen_string_literal: true

module PSN
  # One player from a user search. account_id is the Sony numeric ID usable
  # with games/trophies lookups; relationship_state is nil for strangers.
  UserSearchResult = Data.define(:online_id, :account_id, :display_name,
                                 :avatar_url, :ps_plus, :relationship_state, :raw) do
    def self.from_api(hash)
      new(online_id: hash["onlineId"], account_id: hash["accountId"],
          display_name: hash["displayName"], avatar_url: hash["avatarUrl"],
          ps_plus: hash["isPsPlus"] == true,
          relationship_state: hash["relationshipState"], raw: hash)
    end

    def ps_plus? = ps_plus
  end
end
