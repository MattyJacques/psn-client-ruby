# frozen_string_literal: true

module PSN
  # Lazily enumerates paged PSN API responses. Nothing is fetched until the
  # returned Enumerator::Lazy is consumed; .first(n) stops fetching as soon
  # as n items have been yielded.
  module Paginator
    module_function

    # Sony offset paging: response carries totalItemCount.
    def offset(page_size:)
      Enumerator.new do |yielder|
        position = 0
        loop do
          items, total = yield(page_size, position)
          items.each { |item| yielder << item }
          position += items.size
          break if items.empty? || position >= total.to_i
        end
      end.lazy
    end

    # Sony cursor paging: response carries the next cursor (nil/empty = done).
    def cursor
      Enumerator.new do |yielder|
        next_cursor = nil
        loop do
          items, next_cursor = yield(next_cursor)
          items.each { |item| yielder << item }
          break if items.empty? || next_cursor.nil? || next_cursor.to_s.empty?
        end
      end.lazy
    end
  end
end
