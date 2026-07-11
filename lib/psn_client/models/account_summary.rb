# frozen_string_literal: true

module PSN
  # One Sony-tracked subscription state (PSPLUS, EAACCESS, UBISOFT_PLUS,
  # GTA_PLUS, PSNOW, LOYALTY...). status is SUBSCRIBED / ENROLLED / LAPSED /
  # NEVER; tier/duration are only set while subscribed (PS+ tiers are
  # TIER_10/20/30 = Essential/Extra/Premium, mirroring Catalog::PLUS_TIERS).
  Subscription = Data.define(:type, :status, :tier, :duration, :loyalty_tier, :raw) do
    def self.from_api(hash)
      new(type: hash["subscriptionType"], status: hash["subscriptionStatus"],
          tier: hash["subscriptionTier"], duration: hash["subscriptionDuration"],
          loyalty_tier: hash["loyaltyTier"], raw: hash)
    end

    def active? = %w[SUBSCRIBED ENROLLED].include?(status)
  end

  # The authenticated account's web-toolbar summary
  # (oracleUserProfileRetrieve): identity basics plus every subscription
  # state Sony tracks.
  AccountSummary = Data.define(:account_id, :online_id, :name, :age,
                               :avatar_url, :ps_plus, :officially_verified,
                               :locale, :subscriptions, :raw) do
    def self.from_api(hash)
      subscriptions = (hash["userSubscription"] || []).map { |sub| Subscription.from_api(sub) }
      new(account_id: hash["accountId"], online_id: hash["onlineId"],
          name: hash["name"], age: hash["age"],
          avatar_url: hash.dig("avatar", "url"), ps_plus: hash["isPsPlusMember"],
          officially_verified: hash["isOfficiallyVerified"],
          locale: hash["locale"], subscriptions: subscriptions, raw: hash)
    end

    def ps_plus? = ps_plus
    def officially_verified? = officially_verified
  end
end
