# frozen_string_literal: true

require "faraday"
require "faraday/retry"

module PSN
  # Shared HTTP layer: one Faraday connection per PSN host, Bearer auth
  # injected per-request, transient-failure retries, and error mapping.
  class Connection
    HOSTS = {
      mobile: "https://m.np.playstation.com",
      web: "https://web.np.playstation.com"
    }.freeze

    DEFAULT_RETRY_OPTIONS = {
      max: 3,
      interval: 0.5,
      backoff_factor: 2,
      retry_statuses: [500, 502, 503, 504],
      methods: %i[get post]
    }.freeze

    def initialize(auth, retry_options: nil)
      @auth = auth
      @retry_options = DEFAULT_RETRY_OPTIONS.merge(retry_options || {})
      @conns = {}
    end

    def get(host, path, params = {})
      request(host, :get, path, params)
    end

    def post(host, path, body)
      request(host, :post, path, body)
    end

    private

    def request(host, verb, path, payload, retried: false)
      resp = perform(host, verb, path, payload)
      if resp.status == 401 && !retried
        @auth.refresh!
        return request(host, verb, path, payload, retried: true)
      end
      handle_errors(resp)
      resp.body
    end

    def perform(host, verb, path, payload)
      connection(host).public_send(verb, path) do |req|
        req.headers["Authorization"] = "Bearer #{@auth.access_token}"
        verb == :get ? req.params.update(payload) : req.body = payload
      end
    end

    def handle_errors(resp)
      return if resp.status < 400

      response = { status: resp.status, body: resp.body }
      case resp.status
      when 401 then raise AuthenticationError.new("unauthorized", response: response)
      when 403 then raise PrivacyError.new("blocked by the account's privacy settings", response: response)
      when 404 then raise NotFoundError.new("not found", response: response)
      when 429 then raise RateLimitError.new("rate limited", response: response,
                                                             retry_after: resp.headers["retry-after"]&.to_i)
      else raise APIError.new("PSN API error (HTTP #{resp.status})", response: response)
      end
    end

    def connection(host)
      @conns[host] ||= Faraday.new(url: HOSTS.fetch(host)) do |f|
        f.request :json
        f.request :retry, @retry_options
        f.response :json, content_type: /\bjson/
      end
    end
  end
end
