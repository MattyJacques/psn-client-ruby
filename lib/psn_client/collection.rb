# frozen_string_literal: true

require "delegate"

module PSN
  # Lazy paged result set. Delegates to the Enumerator::Lazy it wraps, so
  # nothing is fetched until consumed, chained adapters (select, take_while,
  # ...) stay lazy, and re-enumerating re-fetches — exactly the wrapped
  # enumerator's behavior. Adds #total, the server-reported item count where
  # the endpoint provides one.
  class Collection < SimpleDelegator
    # Mutable holder shared with the paginator's fetch loop: the count is
    # recorded as soon as any page is fetched, so #total after enumeration
    # costs nothing.
    TotalState = Struct.new(:known, :value)

    def initialize(enum, total_state: TotalState.new(false, nil), total_fetcher: nil)
      super(enum)
      @total_state = total_state
      @total_fetcher = total_fetcher
    end

    # Server-reported item count, or nil where the endpoint gives none
    # (cursor-paged endpoints). Fetches a single page if nothing has been
    # fetched yet; free afterwards.
    def total
      unless @total_state.known
        @total_state.value = @total_fetcher&.call
        @total_state.known = true
      end
      @total_state.value
    end

    # Keeps the Collection type (and #total) through the model-mapping step.
    def map(...)
      self.class.new(__getobj__.map(...), total_state: @total_state, total_fetcher: @total_fetcher)
    end
  end
end
