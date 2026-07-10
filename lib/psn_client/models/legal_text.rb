# frozen_string_literal: true

module PSN
  # Legal text for a concept's default product (wcaConceptRetrieveForLegalText):
  # the LEGAL description entries (subtypes seen live: SCEE_TOS,
  # SCEE_HEALTH_TEXT, SCEE_LIBRARY_TEXT, null) plus the publisher's privacy
  # policy when present.
  LegalText = Data.define(:notices, :privacy_policy, :publisher, :raw) do
    def self.from_api(hash)
      notices = (hash["descriptions"] || []).select { |d| d["type"] == "LEGAL" }
                                            .map { |d| { sub_type: d["subType"], text: d["value"] } }
      new(notices: notices, privacy_policy: hash["privacyPolicy"],
          publisher: hash["publisherName"], raw: hash)
    end
  end
end
