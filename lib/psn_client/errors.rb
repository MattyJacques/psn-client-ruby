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

  class RateLimitError < Error
    attr_reader :retry_after

    def initialize(message = nil, response: nil, retry_after: nil)
      @retry_after = retry_after
      super(message, response: response)
    end
  end
end
