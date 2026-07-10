# frozen_string_literal: true

module PSN
  # Community-known messageType values (PSNAWP); unknown types map to nil.
  GROUP_MESSAGE_TYPE_NAMES = { 1 => :text, 3 => :image, 210 => :video, 1011 => :audio, 1013 => :sticker }.freeze
  private_constant :GROUP_MESSAGE_TYPE_NAMES

  # One message in a group thread. NOTE: undocumented endpoint; mapping is
  # deliberately defensive and everything unmapped stays available in #raw.
  GroupMessage = Data.define(:uid, :type, :type_name, :body, :created_at,
                             :sender_account_id, :sender_online_id, :raw) do
    def self.from_api(hash)
      new(uid: hash["messageUid"],
          type: hash["messageType"],
          type_name: GROUP_MESSAGE_TYPE_NAMES[hash["messageType"]],
          body: hash["body"],
          created_at: Mapping.epoch_ms(hash["createdTimestamp"]),
          sender_account_id: hash.dig("sender", "accountId"),
          sender_online_id: hash.dig("sender", "onlineId"),
          raw: hash)
    end
  end
end
