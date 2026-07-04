# frozen_string_literal: true

require "faraday"
require "json"
require "uri"

module PSN
  # Exchanges an NPSSO token (or a saved refresh token) for PSN OAuth tokens
  # and transparently refreshes the ~1h access token. Tokens are never
  # persisted; read #refresh_token and store it yourself for the next session.
  class Auth
    AUTH_BASE = "https://ca.account.sony.com/api/authz/v3/oauth"
    CLIENT_ID = "09515159-7237-4370-9b40-3806e67c0891"
    CLIENT_SECRET = "ucPjka5tntB2KqsP"
    REDIRECT_URI = "com.scee.psxandroid.scecompcall://redirect"
    SCOPE = "psn:mobile.v2.core psn:clientapp"
    EXPIRY_BUFFER = 60 # seconds; refresh slightly early to absorb clock skew

    attr_reader :refresh_token

    def initialize(npsso: nil, refresh_token: nil)
      unless [npsso, refresh_token].compact.size == 1
        raise ArgumentError, "provide exactly one of npsso: or refresh_token:"
      end

      @npsso = npsso
      @refresh_token = refresh_token
      @access_token = nil
      @expires_at = nil
      @mutex = Mutex.new
    end

    def access_token
      @mutex.synchronize do
        if @access_token.nil?
          authenticate
        elsif expired?
          refresh
        end
        @access_token
      end
    end

    def refresh!
      @mutex.synchronize { refresh }
    end

    private

    def expired?
      @expires_at && Time.now >= @expires_at
    end

    def authenticate
      if @refresh_token
        refresh
      else
        request_token("grant_type" => "authorization_code", "code" => authorization_code,
                      "redirect_uri" => REDIRECT_URI, "token_format" => "jwt")
      end
    end

    def refresh
      raise AuthenticationError, "no refresh token available" unless @refresh_token

      request_token("grant_type" => "refresh_token", "refresh_token" => @refresh_token,
                    "scope" => SCOPE, "token_format" => "jwt")
    end

    def authorization_code
      resp = http.get("#{AUTH_BASE}/authorize") do |req|
        req.params.update("access_type" => "offline", "client_id" => CLIENT_ID,
                          "response_type" => "code", "scope" => SCOPE, "redirect_uri" => REDIRECT_URI)
        req.headers["Cookie"] = "npsso=#{@npsso}"
      end
      extract_code(resp) or raise AuthenticationError.new(
        "NPSSO token rejected — NPSSO tokens expire after ~2 months; fetch a fresh one",
        response: { status: resp.status, body: resp.body }
      )
    end

    def extract_code(resp)
      location = resp.headers["location"].to_s
      return nil unless location.include?("code=")

      URI.decode_www_form(URI(location).query.to_s).to_h["code"]
    end

    def request_token(params)
      resp = http.post("#{AUTH_BASE}/token") do |req|
        req.headers["Authorization"] = "Basic #{["#{CLIENT_ID}:#{CLIENT_SECRET}"].pack('m0')}"
        req.headers["Content-Type"] = "application/x-www-form-urlencoded"
        req.body = URI.encode_www_form(params)
      end
      unless resp.status == 200
        raise AuthenticationError.new("token request failed (HTTP #{resp.status})",
                                      response: { status: resp.status, body: resp.body })
      end
      apply_tokens(JSON.parse(resp.body))
    end

    def apply_tokens(data)
      @access_token = data["access_token"]
      @refresh_token = data["refresh_token"] || @refresh_token
      @expires_at = Time.now + data["expires_in"].to_i - EXPIRY_BUFFER
      @access_token
    end

    def http
      @http ||= Faraday.new # no redirect-following middleware: 302s are returned as-is
    end
  end
end
