# frozen_string_literal: true

require_relative "psn_client/version"
require_relative "psn_client/errors"
require_relative "psn_client/auth"
require_relative "psn_client/connection"
require_relative "psn_client/paginator"
require_relative "psn_client/models/mapping"
require_relative "psn_client/models/game_title"
require_relative "psn_client/models/library_title"
require_relative "psn_client/models/trophy_title"
require_relative "psn_client/models/trophy"
require_relative "psn_client/models/trophy_summary"
require_relative "psn_client/models/transaction"
require_relative "psn_client/models/entitlement"
require_relative "psn_client/resources/users"
require_relative "psn_client/resources/games"
require_relative "psn_client/resources/trophies"
require_relative "psn_client/resources/store"
require_relative "psn_client/client"

# Unofficial PlayStation Network API client.
module PSN
end
