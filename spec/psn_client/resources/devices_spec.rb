# frozen_string_literal: true

RSpec.describe PSN::Resources::Devices do
  subject(:devices) { described_class.new(connection) }

  let(:connection) { instance_double(PSN::Connection) }

  describe "#all" do
    it "lists registered devices from the DMS host" do
      allow(connection).to receive(:get)
        .with(:dms, "/api/v1/devices/accounts/me",
              { "includeFields" => "device,systemData", "platform" => "PS5,PS4,PS3,PSVita" })
        .and_return({ "accountId" => "1", "accountDevices" => [fixture("device")] })

      result = devices.all
      expect(result.size).to eq(1)
      expect(result.first).to be_a(PSN::Device)
      expect(result.first.device_type).to eq("PS5")
      expect(result.first.activation_type).to eq("PRIMARY_PS5")
      expect(result.first.activated_at).to eq(Time.utc(2023, 11, 15, 18, 30, 0))
    end

    it "maps identity fields and keeps the raw response" do
      allow(connection).to receive(:get)
        .with(:dms, "/api/v1/devices/accounts/me",
              { "includeFields" => "device,systemData", "platform" => "PS5,PS4,PS3,PSVita" })
        .and_return({ "accountId" => "1", "accountDevices" => [fixture("device")] })

      result = devices.all
      expect(result.first.device_id).to eq("0123456789ABCDEF0123456789ABCDEF")
      expect(result.first.raw).to eq(fixture("device"))
    end

    it "returns an empty array when the ledger is empty" do
      allow(connection).to receive(:get).and_return({ "accountId" => "1" })

      expect(devices.all).to eq([])
    end
  end

  describe "#storage" do
    it "returns raw storage data (provisional mapping) with the language header" do
      body = { "clients" => [] }
      allow(connection).to receive(:get)
        .with(:mobile, "/api/cloudAssistedNavigation/v2/users/me/clients",
              { "includeFields" => "device,systemData", "platform" => "PS5" },
              headers: { "Accept-Language" => "en-us" })
        .and_return(body)

      expect(devices.storage).to eq(body)
    end

    it "passes a custom platform through" do
      allow(connection).to receive(:get)
        .with(:mobile, "/api/cloudAssistedNavigation/v2/users/me/clients",
              { "includeFields" => "device,systemData", "platform" => "PS4" },
              headers: { "Accept-Language" => "en-us" })
        .and_return({})

      expect(devices.storage(platform: "PS4")).to eq({})
    end
  end
end
