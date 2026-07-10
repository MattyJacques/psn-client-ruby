# frozen_string_literal: true

module PSN
  # A member of a message group. NOTE: the list endpoint's members only carry
  # accountId/onlineId (no role); role is only present in the detail response
  # (values observed live: "member", "owner") — nil-safe either way.
  GroupMember = Data.define(:account_id, :online_id, :role) do
    def self.from_api(hash)
      new(account_id: hash["accountId"], online_id: hash["onlineId"], role: hash["role"])
    end
  end

  # A message group or DM. NOTE: undocumented endpoint; mapping is
  # deliberately defensive and everything unmapped stays available in #raw.
  # :members intentionally shadows Data#members — the API concept ("group
  # members") is a better name here than the Data-introspection method, and
  # nothing in this codebase relies on Group#members returning member names.
  # rubocop:disable Lint/DataDefineOverride
  Group = Data.define(:id, :name, :group_type, :favorite, :modified_at,
                      :members, :latest_message, :raw) do
    # rubocop:enable Lint/DataDefineOverride
    def self.from_api(hash)
      latest = hash.dig("mainThread", "latestMessage")
      new(id: hash["groupId"],
          name: presence_of(hash.dig("groupName", "value")),
          group_type: hash["groupType"],
          favorite: hash["isFavorite"] == true,
          # Neither the list nor the detail response has a top-level
          # modifiedTimestamp (confirmed live 2026-07-10); mainThread's is the
          # closest analog (the thread's last-activity time), so use that. The
          # list response omits mainThread entirely, so #all's items map nil
          # here — only #find's full-field fetch populates it.
          modified_at: Mapping.epoch_ms(hash.dig("mainThread", "modifiedTimestamp")),
          members: (hash["members"] || []).map { |m| GroupMember.from_api(m) },
          latest_message: latest && GroupMessage.from_api(latest),
          raw: hash)
    end

    def self.presence_of(value)
      value unless value.nil? || value.empty?
    end

    def favorite? = favorite
  end
end
