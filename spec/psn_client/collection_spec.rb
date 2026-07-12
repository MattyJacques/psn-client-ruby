# frozen_string_literal: true

RSpec.describe PSN::Collection do
  def paged(calls)
    PSN::Paginator.offset(page_size: 2) do |_limit, offset|
      calls << offset
      { 0 => [[1, 2], 5], 2 => [[3, 4], 5], 4 => [[5], 5] }.fetch(offset)
    end
  end

  describe "#total" do
    it "costs at most one page fetch when asked before enumeration" do
      calls = []
      expect(paged(calls).total).to eq(5)
      expect(calls).to eq([0])
    end

    it "is free once pages have been fetched" do
      calls = []
      collection = paged(calls)
      expect(collection.to_a).to eq([1, 2, 3, 4, 5])
      expect(collection.total).to eq(5)
      expect(calls).to eq([0, 2, 4])
    end

    it "returns nil when the endpoint reports no count" do
      collection = PSN::Paginator.offset(page_size: 2) { |_l, _o| [[], nil] }
      expect(collection.total).to be_nil
    end

    it "is nil for cursor-paged endpoints, which offer no count" do
      collection = PSN::Paginator.cursor { |_cursor, _position| [[1], nil] }
      expect(collection.total).to be_nil
      expect(collection.to_a).to eq([1])
    end
  end

  describe "#map" do
    it "keeps the Collection type and shares the total" do
      calls = []
      mapped = paged(calls).map { |n| n * 10 }
      expect(mapped).to be_a(described_class)
      expect(mapped.first(2)).to eq([10, 20])
      expect(mapped.total).to eq(5)
      expect(calls).to eq([0])
    end
  end

  describe "lazy delegation" do
    it "keeps chained adapters lazy so first(n) stops paging early" do
      calls = 0
      collection = PSN::Paginator.offset(page_size: 2) do |_limit, offset|
        calls += 1
        [[offset, offset + 1], 100]
      end
      expect(collection.select(&:even?).first(2)).to eq([0, 2])
      expect(calls).to eq(2)
    end
  end
end
