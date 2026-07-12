# frozen_string_literal: true

RSpec.describe PSN::Connection do
  subject(:connection) { described_class.new(auth, retry_options: { max: 0 }) }

  let(:auth) { instance_double(PSN::Auth, access_token: "tok-1", refresh!: nil) }
  let(:url) { "https://m.np.playstation.com/api/test" }

  def json_response(body, status: 200)
    { status: status, body: body.to_json, headers: { "Content-Type" => "application/json" } }
  end

  it "performs an authorized GET against the mobile host and parses JSON" do
    stub_request(:get, url)
      .with(query: { "limit" => "10" }, headers: { "Authorization" => "Bearer tok-1" })
      .to_return(json_response({ "ok" => true }))

    expect(connection.get(:mobile, "/api/test", { "limit" => 10 })).to eq("ok" => true)
  end

  it "passes extra headers through on GET" do
    stub_request(:get, url)
      .with(headers: { "Authorization" => "Bearer tok-1", "Accept-Language" => "en-us" })
      .to_return(json_response({ "ok" => true }))

    expect(connection.get(:mobile, "/api/test", {}, headers: { "Accept-Language" => "en-us" }))
      .to eq("ok" => true)
  end

  it "performs a JSON POST against the web host" do
    stub_request(:post, "https://web.np.playstation.com/api/test")
      .with(body: { "a" => 1 }.to_json, headers: { "Authorization" => "Bearer tok-1" })
      .to_return(json_response({ "ok" => true }))

    expect(connection.post(:web, "/api/test", { "a" => 1 })).to eq("ok" => true)
  end

  it "refreshes and retries exactly once on 401" do
    stub_request(:get, url).to_return({ status: 401 }, json_response({ "ok" => true }))

    expect(connection.get(:mobile, "/api/test")).to eq("ok" => true)
    expect(auth).to have_received(:refresh!).once
  end

  it "raises AuthenticationError when 401 persists after refresh" do
    stub_request(:get, url).to_return(status: 401)
    expect { connection.get(:mobile, "/api/test") }.to raise_error(PSN::AuthenticationError)
    expect(auth).to have_received(:refresh!).once
  end

  # A 403 has two very different causes: a real PSN API refusal (JSON body) or
  # an Akamai/WAF edge block that never reached the API (HTML body). They must
  # not share an error class or message.
  it "maps a JSON access-control 403 to PrivacyError carrying the server message" do
    stub_request(:get, url)
      .to_return(json_response({ "error" => { "message" => "Not permitted by access control" } }, status: 403))
    expect { connection.get(:mobile, "/api/test") }
      .to raise_error(PSN::PrivacyError, /access control/i)
  end

  it "maps a JSON non-privacy 403 (e.g. missing scope) to APIError with the real message" do
    stub_request(:get, url)
      .to_return(json_response({ "error" => { "message" => "access token does not contain the required scope(s)" } },
                               status: 403))
    expect { connection.get(:mobile, "/api/test") }
      .to raise_error(PSN::APIError, /required scope/i)
  end

  it "maps a non-JSON 403 edge/WAF block to AccessDeniedError, never PrivacyError" do
    stub_request(:get, url)
      .to_return(status: 403, body: "<HTML><HEAD><TITLE>Access Denied</TITLE></HEAD><BODY>Access Denied</BODY></HTML>",
                 headers: { "Content-Type" => "text/html" })
    expect { connection.get(:mobile, "/api/test") }
      .to raise_error(PSN::AccessDeniedError) { |e|
        expect(e).not_to be_a(PSN::PrivacyError)
        expect(e.message).not_to match(/privacy/i)
        expect(e.response[:status]).to eq(403)
      }
  end

  it "maps 404 to NotFoundError" do
    stub_request(:get, url).to_return(status: 404)
    expect { connection.get(:mobile, "/api/test") }.to raise_error(PSN::NotFoundError)
  end

  it "maps 429 to RateLimitError with retry_after" do
    stub_request(:get, url).to_return(status: 429, headers: { "Retry-After" => "30" })
    expect { connection.get(:mobile, "/api/test") }
      .to raise_error(PSN::RateLimitError) { |e| expect(e.retry_after).to eq(30) }
  end

  it "maps other failures to APIError with the response attached" do
    stub_request(:get, url).to_return(json_response({ "error" => "boom" }, status: 500))
    expect { connection.get(:mobile, "/api/test") }
      .to raise_error(PSN::APIError) { |e| expect(e.response[:status]).to eq(500) }
  end

  it "sends Accept-Language with the default language on every request" do
    stub_request(:get, url)
      .with(headers: { "Authorization" => "Bearer tok-1", "Accept-Language" => "en-US" })
      .to_return(json_response({ "ok" => true }))

    expect(connection.get(:mobile, "/api/test")).to eq("ok" => true)
  end

  it "sends and exposes a custom language" do
    custom = described_class.new(auth, retry_options: { max: 0 }, language: "en-GB")
    stub_request(:get, url)
      .with(headers: { "Accept-Language" => "en-GB" })
      .to_return(json_response({ "ok" => true }))

    expect(custom.get(:mobile, "/api/test")).to eq("ok" => true)
    expect(custom.language).to eq("en-GB")
  end

  it "lets a per-request header override the global language" do
    stub_request(:get, url)
      .with(headers: { "Accept-Language" => "de-DE" })
      .to_return(json_response({ "ok" => true }))

    expect(connection.get(:mobile, "/api/test", {}, headers: { "Accept-Language" => "de-DE" }))
      .to eq("ok" => true)
  end

  describe "#graphql" do
    let(:gql_url) { "https://m.np.playstation.com/api/graphql/v1/op" }

    it "performs a persisted-query GET with the Apollo preflight header" do
      stub_request(:get, gql_url)
        .with(query: {
                "operationName" => "getThing",
                "variables" => '{"limit":5}',
                "extensions" => '{"persistedQuery":{"version":1,"sha256Hash":"abc123"}}'
              },
              headers: { "Authorization" => "Bearer tok-1", "Apollo-Require-Preflight" => "true" })
        .to_return(json_response({ "data" => { "ok" => true } }))

      expect(connection.graphql("getThing", { "limit" => 5 }, "abc123")).to eq("data" => { "ok" => true })
    end

    it "raises APIError when the 200 body carries GraphQL errors" do
      stub_request(:get, gql_url)
        .with(query: hash_including("operationName" => "getThing"))
        .to_return(json_response({ "errors" => [{ "message" => "PersistedQueryNotFound" }] }))

      expect { connection.graphql("getThing", {}, "abc123") }
        .to raise_error(PSN::APIError, /PersistedQueryNotFound/)
    end

    it "refreshes and retries once on 401" do
      stub_request(:get, gql_url)
        .with(query: hash_including("operationName" => "getThing"))
        .to_return({ status: 401 }, json_response({ "data" => { "ok" => true } }))

      expect(connection.graphql("getThing", {}, "abc123")).to eq("data" => { "ok" => true })
      expect(auth).to have_received(:refresh!).once
    end

    it "targets another host and merges extra headers when asked" do
      stub_request(:get, "https://web.np.playstation.com/api/graphql/v1/op")
        .with(query: hash_including("operationName" => "getThing"),
              headers: { "Apollo-Require-Preflight" => "true", "X-Extra" => "1" })
        .to_return(json_response({ "data" => { "ok" => true } }))

      body = connection.graphql("getThing", {}, "abc123", host: :web, headers: { "X-Extra" => "1" })
      expect(body).to eq("data" => { "ok" => true })
    end
  end
end
