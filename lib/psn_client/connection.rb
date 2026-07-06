# frozen_string_literal: true

require "faraday"
require "faraday/retry"
require "json"

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

    GRAPHQL_PATH = "/api/graphql/v1/op"
    GRAPHQL_HEADERS = { "Apollo-Require-Preflight" => "true" }.freeze

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

    # Persisted-query GraphQL GET. Sony's GraphQL can fail with HTTP 200 and
    # an errors array in the body, so that case is mapped to APIError here.
    def graphql(operation_name, variables, sha256_hash)
      extensions = { "persistedQuery" => { "version" => 1, "sha256Hash" => sha256_hash } }
      params = { "operationName" => operation_name,
                 "variables" => JSON.generate(variables),
                 "extensions" => JSON.generate(extensions) }
      body = request(:mobile, :get, GRAPHQL_PATH, params, headers: GRAPHQL_HEADERS)
      handle_graphql_errors(body)
      body
    end

    private

    def request(host, verb, path, payload, headers: {}, retried: false) # rubocop:disable Metrics/ParameterLists
      resp = perform(host, verb, path, payload, headers)
      if resp.status == 401 && !retried
        @auth.refresh!
        return request(host, verb, path, payload, headers: headers, retried: true)
      end
      handle_errors(resp)
      resp.body
    end

    def perform(host, verb, path, payload, headers)
      connection(host).public_send(verb, path) do |req|
        req.headers["Authorization"] = "Bearer #{@auth.access_token}"
        headers.each { |name, value| req.headers[name] = value }
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

    def handle_graphql_errors(body)
      errors = body.is_a?(Hash) ? body["errors"] : nil
      return if errors.nil? || errors.empty?

      messages = errors.filter_map { |e| e["message"] }.join("; ")
      raise APIError.new("PSN GraphQL error: #{messages}", response: { status: 200, body: body })
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
