# frozen_string_literal: true

module PSN
  # Lazily enumerates paged PSN API responses, returned as PSN::Collection.
  # Nothing is fetched until the collection is consumed; .first(n) stops
  # fetching as soon as n items have been yielded.
  module Paginator
    module_function

    # Sony offset paging: response carries totalItemCount. The TotalState is
    # shared between the fetch loop and the Collection, so whichever side
    # fetches a page first records the count; the total_fetcher covers
    # Collection#total being read before any enumeration.
    def offset(page_size:, &fetch_page)
      state = Collection::TotalState.new(false, nil)
      enum = Enumerator.new do |yielder|
        position = 0
        loop do
          items, total = fetch_page.call(page_size, position)
          state.known = true
          state.value = total&.to_i
          items.each { |item| yielder << item }
          position += items.size
          break if items.empty? || (total && position >= total.to_i)
        end
      end.lazy
      Collection.new(enum, total_state: state,
                           total_fetcher: -> { fetch_page.call(page_size, 0)[1]&.to_i })
    end

    # Sony cursor paging: response carries the next cursor (nil/empty = done).
    # The block also receives the running position (items yielded so far) for
    # APIs that want an offset alongside the cursor; state lives inside the
    # Enumerator, so re-enumerating restarts from a nil cursor at position 0.
    # A cursor identical to the previous one also ends the walk — guards
    # against a misbehaving API pinning the enumerator in an infinite loop.
    # These endpoints report no item count, so the collection's total is nil.
    def cursor
      enum = Enumerator.new do |yielder|
        next_cursor = nil
        position = 0
        loop do
          previous_cursor = next_cursor
          items, next_cursor = yield(next_cursor, position)
          items.each { |item| yielder << item }
          position += items.size
          break if items.empty? || next_cursor.nil? || next_cursor.to_s.empty? || next_cursor == previous_cursor
        end
      end.lazy
      Collection.new(enum)
    end
  end
end
