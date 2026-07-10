# frozen_string_literal: true

module PSN
  # Entry point. Authenticates with an NPSSO token or a saved refresh token
  # and exposes the PSN API as namespaced resources.
  #
  #   client = PSN::Client.new(npsso: "...")
  #   client.games.played.first(10)
  #   client.trophies.summary("a_friend")
  #   client.store.entitlements.to_a
  class Client
    def initialize(npsso: nil, refresh_token: nil)
      @auth = Auth.new(npsso: npsso, refresh_token: refresh_token)
      @connection = Connection.new(@auth)
    end

    def games = @games ||= Resources::Games.new(@connection, users)
    def trophies = @trophies ||= Resources::Trophies.new(@connection, users)
    def store = @store ||= Resources::Store.new(@connection)
    def profiles = @profiles ||= Resources::Profiles.new(@connection, users)
    def search = @search ||= Resources::Search.new(@connection)
    def catalog = @catalog ||= Resources::Catalog.new(@connection)
    def social = @social ||= Resources::Social.new(@connection, users)
    def devices = @devices ||= Resources::Devices.new(@connection)
    def media = @media ||= Resources::Media.new(@connection)

    # Triggers authentication if it has not happened yet.
    def access_token = @auth.access_token

    # Persist this (it rotates) to reconstruct the client without a fresh NPSSO.
    def refresh_token = @auth.refresh_token

    private

    def users = @users ||= Resources::Users.new(@connection)
  end
end
