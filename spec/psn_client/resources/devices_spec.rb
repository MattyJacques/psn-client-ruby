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
    it "maps consoles to ConsoleStorage models" do
      allow(connection).to receive(:get)
        .with(:mobile, "/api/cloudAssistedNavigation/v2/users/me/clients",
              { "includeFields" => "device,systemData", "platform" => "PS5" })
        .and_return(fixture("console_storage"))

      console = devices.storage.first
      expect(console).to be_a(PSN::ConsoleStorage)
      expect(console.name).to eq("PS5-001")
      expect(console.platform).to eq("PS5")
      expect(console.free_bytes).to eq(1_550_405_074_944)
      expect(console.total_bytes).to eq(1_887_699_992_576)
    end

    it "maps console identity fields and keeps the raw client" do
      allow(connection).to receive(:get).and_return(fixture("console_storage"))

      console = devices.storage.first
      expect(console.duid).to eq("00000007000a00c0000000000000000000000000000000000000000000000000")
      expect(console.updated_at).to eq(Time.utc(2026, 7, 4, 20, 26, 5))
      expect(console.raw).to eq(fixture("console_storage")["clients"].first)
    end

    it "maps installed title identity" do
      allow(connection).to receive(:get).and_return(fixture("console_storage"))

      titles = devices.storage.first.installed_titles
      expect(titles.size).to eq(2)
      expect(titles.first).to be_a(PSN::InstalledTitle)
      expect(titles.first.name).to eq("ASTRO's PLAYROOM")
      expect(titles.first.title_id).to eq("PPSA01325")
      expect(titles.first.np_title_id).to eq("PPSA01325_00")
    end

    it "maps installed title details" do
      allow(connection).to receive(:get).and_return(fixture("console_storage"))

      title = devices.storage.first.installed_titles.first
      expect(title.concept_id).to eq("10000237")
      expect(title.platform).to eq("PS5")
      expect(title.size_bytes).to eq(63_853_625_344)
      expect(title.last_played_at).to eq(Time.utc(2026, 6, 16, 21, 15, 47))
      expect(title.version).to eq("01.000.028")
    end

    it "passes a custom platform through and returns an empty array without clients" do
      allow(connection).to receive(:get)
        .with(:mobile, "/api/cloudAssistedNavigation/v2/users/me/clients",
              { "includeFields" => "device,systemData", "platform" => "PS4" })
        .and_return({})

      expect(devices.storage(platform: "PS4")).to eq([])
    end
  end
end
