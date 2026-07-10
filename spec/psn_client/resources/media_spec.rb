# frozen_string_literal: true

RSpec.describe PSN::Resources::Media do
  subject(:media) { described_class.new(connection) }

  let(:connection) { instance_double(PSN::Connection) }
  let(:list_path) { "/api/gameMediaService/v2/c2s/category/cloudMediaGallery/ugcType/all" }

  describe "#captures" do
    it "fetches one page of raw capture hashes lazily" do
      allow(connection).to receive(:get)
        .with(:mobile, list_path, { "limit" => 20, "includeTokenizedUrls" => "true" })
        .and_return({ "ugcDocument" => [{ "ugcId" => "abc" }], "nextCursorMark" => "c1" })

      result = media.captures.to_a
      expect(result).to eq([{ "ugcId" => "abc" }])
      expect(connection).to have_received(:get).once
    end

    it "returns a lazy enumerator and defaults to empty when the key is missing" do
      allow(connection).to receive(:get).and_return({})
      expect(media.captures).to be_a(Enumerator::Lazy)
      expect(media.captures.to_a).to eq([])
    end
  end

  describe "#download_url" do
    it "fetches the raw tokenized-URL hash for one capture" do
      allow(connection).to receive(:get)
        .with(:mobile, "/api/gameMediaService/v2/c2s/ugc/abc/url", {})
        .and_return({ "screenshotUrl" => "https://example.com/shot.png" })

      expect(media.download_url("abc")).to eq({ "screenshotUrl" => "https://example.com/shot.png" })
    end
  end
end
