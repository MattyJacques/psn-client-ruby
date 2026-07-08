# frozen_string_literal: true

module PSN
  class Error < StandardError
    attr_reader :response

    def initialize(message = nil, response: nil)
      @response = response
      super(message)
    end
  end

  class AuthenticationError < Error; end
  class PrivacyError < Error; end
  class NotFoundError < Error; end
  class APIError < Error; end

  # A 403 whose body is not a PSN API response — i.e. an Akamai/WAF edge block
  # that never reached the API. Distinct from PrivacyError (a real API refusal),
  # because the causes and fixes are unrelated: an edge block means the endpoint
  # needs a browser web session, not different account privacy settings.
  class AccessDeniedError < Error; end

  class RateLimitError < Error
    attr_reader :retry_after

    def initialize(message = nil, response: nil, retry_after: nil)
      @retry_after = retry_after
      super(message, response: response)
    end
  end
end
