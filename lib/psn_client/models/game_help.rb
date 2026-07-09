# frozen_string_literal: true

module PSN
  # One trophy that has Game Help available (metGetHintAvailability).
  # Pass these straight to Trophies#game_help to fetch the actual tips.
  TrophyHelpInfo = Data.define(:trophy_id, :uds_object_id, :help_type, :raw) do
    def self.from_api(hash)
      new(trophy_id: hash["trophyId"], uds_object_id: hash["udsObjectId"],
          help_type: hash["helpType"], raw: hash)
    end
  end

  # metGetTips result. access? is false when the authenticated account has
  # no PS+ subscription — Sony still answers, but with the content gated.
  GameHelp = Data.define(:access, :tips, :raw) do
    def self.from_api(hash)
      new(access: hash["hasAccess"] == true,
          tips: (hash["trophies"] || []).map { |t| TrophyTip.from_api(t) }, raw: hash)
    end

    def access? = access
  end

  # Game Help for one trophy; contents flattens the group nesting.
  TrophyTip = Data.define(:trophy_id, :contents, :raw) do
    def self.from_api(hash)
      contents = (hash["groups"] || []).flat_map { |g| g["tipContents"] || [] }
      new(trophy_id: hash["trophyId"],
          contents: contents.map { |c| TipContent.from_api(c) }, raw: hash)
    end
  end

  # A single hint: text plus an optional (PS+-tokenized) video stream URL.
  TipContent = Data.define(:description, :display_name, :media_type, :media_url, :tip_id, :raw) do
    def self.from_api(hash)
      new(description: hash["description"], display_name: hash["displayName"],
          media_type: hash["mediaType"], media_url: hash["mediaUrl"],
          tip_id: hash["tipId"], raw: hash)
    end
  end
end
