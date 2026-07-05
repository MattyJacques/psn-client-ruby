# frozen_string_literal: true

RSpec.describe PSN::Paginator do
  describe ".offset" do
    it "walks pages until totalItemCount is reached" do
      pages = { 0 => [[1, 2], 5], 2 => [[3, 4], 5], 4 => [[5], 5] }
      enum = described_class.offset(page_size: 2) { |_limit, offset| pages.fetch(offset) }
      expect(enum.to_a).to eq([1, 2, 3, 4, 5])
    end

    it "is lazy: .first(n) fetches only the pages it needs" do
      calls = 0
      enum = described_class.offset(page_size: 2) do |_limit, offset|
        calls += 1
        [[offset, offset + 1], 6]
      end
      expect(enum.first(2)).to eq([0, 1])
      expect(calls).to eq(1)
    end

    it "returns a lazy enumerator and stops on an empty page" do
      enum = described_class.offset(page_size: 2) { |_l, _o| [[], 10] }
      expect(enum).to be_a(Enumerator::Lazy)
      expect(enum.to_a).to eq([])
    end

    it "falls back to paging until an empty page when total is missing" do
      pages = { 0 => [[1, 2], nil], 2 => [[3], nil], 3 => [[], nil] }
      enum = described_class.offset(page_size: 2) { |_limit, offset| pages.fetch(offset) }
      expect(enum.to_a).to eq([1, 2, 3])
    end
  end

  describe ".cursor" do
    it "follows next cursors until exhausted, starting from nil" do
      pages = { nil => [[1, 2], "c1"], "c1" => [[3], "c2"], "c2" => [[4], nil] }
      seen = []
      enum = described_class.cursor do |cursor|
        seen << cursor
        pages.fetch(cursor)
      end
      expect(enum.to_a).to eq([1, 2, 3, 4])
      expect(seen).to eq([nil, "c1", "c2"])
    end

    it "is lazy across cursor pages" do
      calls = 0
      enum = described_class.cursor do |_cursor|
        calls += 1
        [[calls], "next-#{calls}"]
      end
      expect(enum.first(1)).to eq([1])
      expect(calls).to eq(1)
    end

    it "stops when the next cursor is an empty string" do
      pages = { nil => [[1], "c1"], "c1" => [[2], ""] }
      enum = described_class.cursor { |cursor| pages.fetch(cursor) }
      expect(enum.to_a).to eq([1, 2])
    end

    it "stops when the API repeats the same cursor instead of looping forever" do
      calls = 0
      enum = described_class.cursor do |_cursor|
        calls += 1
        [[calls], "stuck"]
      end
      expect(enum.to_a).to eq([1, 2])
      expect(calls).to eq(2)
    end
  end
end
