# psn-client-ruby Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A Ruby gem (`psn-client-ruby`) that authenticates against PlayStation Network with an NPSSO or refresh token and retrieves games played, trophies earned, transaction history, and entitlements.

**Architecture:** Resource-namespaced client (`client.games` / `client.trophies` / `client.store`) over a shared `PSN::Connection` (Faraday, two PSN hosts, error mapping) and `PSN::Auth` (OAuth exchange + auto-refresh). List calls return `Enumerator::Lazy` via `PSN::Paginator`; items are immutable `Data` models with a `#raw` escape hatch.

**Tech Stack:** Ruby >= 3.2, Faraday 2 + faraday-retry (only runtime deps), RSpec + WebMock, RuboCop.

**Spec:** `docs/superpowers/specs/2026-07-04-psn-client-ruby-design.md`

## Global Constraints

- Working directory for ALL commands: `C:\Development\psn-client-ruby` (git repo already initialized, spec committed).
- Shell: PowerShell. Ruby 4.0.5 is installed via scoop but NOT on spawned-shell PATH. **Prefix every ruby/bundle command** with:
  `$env:PATH = "C:\Users\matth\scoop\apps\ruby\current\bin;C:\Users\matth\scoop\apps\ruby\current\gems\bin;$env:PATH"; `
- For `bundle install` only (native extensions), ALSO set:
  `$env:MSYSTEM = "UCRT64"; $env:PATH = "C:\Users\matth\scoop\apps\msys2\current\ucrt64\bin;C:\Users\matth\scoop\apps\msys2\current\usr\bin;" + $env:PATH`
- `required_ruby_version >= 3.2` (uses `Data.define`).
- Runtime dependencies: `faraday ~> 2.9`, `faraday-retry ~> 2.2`. Nothing else.
- Gem name `psn-client-ruby`; required as `psn_client`; top-level module `PSN`. Model classes live directly under `PSN` (e.g. `PSN::GameTitle`), files under `lib/psn_client/models/`.
- Money is integer minor units + currency string. Never floats for money.
- The gem never persists tokens to disk.
- TDD: in every task, write the failing test first, see it fail, implement, see it pass.
- Before every commit run RuboCop: `bundle exec rubocop` — expect `no offenses detected`. Fix offenses (prefer code fixes; only adjust `.rubocop.yml` for rules that fight the design, e.g. `Data.define` block length).
- The `store` endpoints (transactions/entitlements) are undocumented; their hosts/paths/response-keys live ONLY in `lib/psn_client/resources/store.rb` constants and `Transaction`/`Entitlement` mapping, so post-smoke corrections touch two files max.

---

### Task 1: Gem scaffold

**Files:**
- Create: `psn-client-ruby.gemspec`, `Gemfile`, `Rakefile`, `.rspec`, `.rubocop.yml`, `.gitignore`, `LICENSE.txt`, `lib/psn_client.rb`, `lib/psn_client/version.rb`, `spec/spec_helper.rb`, `spec/psn_client_spec.rb`

**Interfaces:**
- Produces: `PSN` module, `PSN::VERSION`, working `bundle exec rspec` / `bundle exec rubocop`, `fixture(name)` spec helper (loads `spec/fixtures/<name>.json`).

- [ ] **Step 1: Write scaffold files**

`psn-client-ruby.gemspec`:

```ruby
# frozen_string_literal: true

require_relative "lib/psn_client/version"

Gem::Specification.new do |spec|
  spec.name = "psn-client-ruby"
  spec.version = PSN::VERSION
  spec.authors = ["Matthew"]
  spec.email = ["iftw@live.co.uk"]
  spec.summary = "Unofficial PlayStation Network API client"
  spec.description = "Retrieve games played, trophies earned, transaction history and " \
                     "entitlements for a PlayStation Network account."
  spec.license = "MIT"
  spec.required_ruby_version = ">= 3.2"
  spec.files = Dir["lib/**/*.rb", "README.md", "LICENSE.txt"]
  spec.require_paths = ["lib"]
  spec.metadata["rubygems_mfa_required"] = "true"

  spec.add_dependency "faraday", "~> 2.9"
  spec.add_dependency "faraday-retry", "~> 2.2"
end
```

`Gemfile`:

```ruby
# frozen_string_literal: true

source "https://rubygems.org"

gemspec

group :development, :test do
  gem "rake", "~> 13.0"
  gem "rspec", "~> 3.13"
  gem "rubocop", "~> 1.65"
  gem "rubocop-rake", "~> 0.6"
  gem "rubocop-rspec", "~> 3.0"
  gem "webmock", "~> 3.23"
end
```

`Rakefile`:

```ruby
# frozen_string_literal: true

require "rspec/core/rake_task"
require "rubocop/rake_task"

RSpec::Core::RakeTask.new(:spec)
RuboCop::RakeTask.new(:rubocop)

task default: %i[spec rubocop]
```

`.rspec`:

```
--require spec_helper
--color
```

`.rubocop.yml`:

```yaml
plugins:
  - rubocop-rake
  - rubocop-rspec

AllCops:
  TargetRubyVersion: 3.2
  NewCops: enable

Style/Documentation:
  Enabled: false

Layout/LineLength:
  Max: 120

Metrics/MethodLength:
  Max: 25

Metrics/AbcSize:
  Max: 25

Metrics/BlockLength:
  Exclude:
    - "spec/**/*"
    - "lib/psn_client/models/*.rb" # Data.define blocks

RSpec/ExampleLength:
  Max: 15

RSpec/MultipleExpectations:
  Max: 5

RSpec/DescribeClass:
  Exclude:
    - "spec/psn_client/models/trophy_models_spec.rb"
    - "spec/psn_client/models/store_models_spec.rb"
```

`.gitignore`:

```
/.bundle/
/coverage/
/pkg/
/tmp/
*.gem
Gemfile.lock
.rspec_status
```

`LICENSE.txt`: standard MIT license text, `Copyright (c) 2026 Matthew`.

`lib/psn_client/version.rb`:

```ruby
# frozen_string_literal: true

module PSN
  VERSION = "0.1.0"
end
```

`lib/psn_client.rb`:

```ruby
# frozen_string_literal: true

require_relative "psn_client/version"

# Unofficial PlayStation Network API client.
module PSN
end
```

`spec/spec_helper.rb`:

```ruby
# frozen_string_literal: true

require "psn_client"
require "webmock/rspec"
require "json"

module FixtureHelper
  def fixture(name)
    JSON.parse(File.read(File.expand_path("fixtures/#{name}.json", __dir__)))
  end
end

RSpec.configure do |config|
  config.include FixtureHelper
  config.disable_monkey_patching!
  config.order = :random
  config.expect_with(:rspec) { |c| c.syntax = :expect }
end
```

`spec/psn_client_spec.rb`:

```ruby
# frozen_string_literal: true

RSpec.describe PSN do
  it "has a version number" do
    expect(PSN::VERSION).to eq("0.1.0")
  end
end
```

- [ ] **Step 2: Install dependencies**

Run (note the MSYS2 env for potential native builds):

```powershell
$env:PATH = "C:\Users\matth\scoop\apps\ruby\current\bin;C:\Users\matth\scoop\apps\ruby\current\gems\bin;$env:PATH"; $env:MSYSTEM = "UCRT64"; $env:PATH = "C:\Users\matth\scoop\apps\msys2\current\ucrt64\bin;C:\Users\matth\scoop\apps\msys2\current\usr\bin;" + $env:PATH; bundle install
```

Expected: `Bundle complete!`

- [ ] **Step 3: Run tests and lint**

```powershell
$env:PATH = "C:\Users\matth\scoop\apps\ruby\current\bin;C:\Users\matth\scoop\apps\ruby\current\gems\bin;$env:PATH"; bundle exec rspec; bundle exec rubocop
```

Expected: `1 example, 0 failures` and `no offenses detected`.

- [ ] **Step 4: Commit**

```powershell
git add -A; git commit -m "chore: gem scaffold with RSpec, WebMock and RuboCop"
```

---

### Task 2: Error hierarchy

**Files:**
- Create: `lib/psn_client/errors.rb`, `spec/psn_client/errors_spec.rb`
- Modify: `lib/psn_client.rb` (add require)

**Interfaces:**
- Produces: `PSN::Error` (`#response` → `{ status: Integer, body: Object }` or nil), subclasses `PSN::AuthenticationError`, `PSN::PrivacyError`, `PSN::NotFoundError`, `PSN::APIError`, and `PSN::RateLimitError` (`#retry_after` → Integer or nil). Constructors: `Error.new(message, response: nil)`, `RateLimitError.new(message, response: nil, retry_after: nil)`.

- [ ] **Step 1: Write the failing test**

`spec/psn_client/errors_spec.rb`:

```ruby
# frozen_string_literal: true

RSpec.describe PSN::Error do
  it "exposes the response and defines the hierarchy" do
    error = PSN::PrivacyError.new("blocked", response: { status: 403, body: "x" })
    expect(error).to be_a(described_class)
    expect(error.message).to eq("blocked")
    expect(error.response).to eq(status: 403, body: "x")
    expect(PSN::AuthenticationError.ancestors).to include(described_class)
    expect(PSN::NotFoundError.ancestors).to include(described_class)
    expect(PSN::APIError.ancestors).to include(described_class)
  end

  it "carries retry_after on RateLimitError" do
    error = PSN::RateLimitError.new("slow down", retry_after: 30)
    expect(error.retry_after).to eq(30)
    expect(error.response).to be_nil
  end
end
```

- [ ] **Step 2: Run test to verify it fails**

```powershell
$env:PATH = "C:\Users\matth\scoop\apps\ruby\current\bin;C:\Users\matth\scoop\apps\ruby\current\gems\bin;$env:PATH"; bundle exec rspec spec/psn_client/errors_spec.rb
```

Expected: FAIL — `uninitialized constant PSN::Error`.

- [ ] **Step 3: Implement**

`lib/psn_client/errors.rb`:

```ruby
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
```

In `lib/psn_client.rb`, after the version require, add:

```ruby
require_relative "psn_client/errors"
```

- [ ] **Step 4: Run tests, lint, commit**

```powershell
$env:PATH = "C:\Users\matth\scoop\apps\ruby\current\bin;C:\Users\matth\scoop\apps\ruby\current\gems\bin;$env:PATH"; bundle exec rspec; bundle exec rubocop
```

Expected: all pass, no offenses.

```powershell
git add -A; git commit -m "feat: error hierarchy under PSN::Error"
```

---

### Task 3: Auth (NPSSO / refresh-token OAuth)

**Files:**
- Create: `lib/psn_client/auth.rb`, `spec/psn_client/auth_spec.rb`
- Modify: `lib/psn_client.rb` (add require)

**Interfaces:**
- Produces: `PSN::Auth.new(npsso: nil, refresh_token: nil)` (exactly one required, else `ArgumentError`); `#access_token` → String (lazily authenticates, auto-refreshes when expired); `#refresh_token` → String or nil; `#refresh!` → forces a refresh grant. Raises `PSN::AuthenticationError` on bad NPSSO or failed token requests.
- Consumes: `PSN::AuthenticationError` from Task 2.

Background — Sony's mobile-app OAuth flow (same one `psn-api` uses):
1. `GET https://ca.account.sony.com/api/authz/v3/oauth/authorize?access_type=offline&client_id=09515159-7237-4370-9b40-3806e67c0891&response_type=code&scope=psn:mobile.v2.core psn:clientapp&redirect_uri=com.scee.psxandroid.scecompcall://redirect` with header `Cookie: npsso=<token>`, redirects NOT followed. Success = 302 whose `Location` contains `?code=v3.XXXX`. A 200 (login page) means the NPSSO is invalid/expired.
2. `POST .../oauth/token` form-encoded with `grant_type=authorization_code`, `code`, `redirect_uri`, `token_format=jwt`; `Authorization: Basic base64(client_id:client_secret)` where client_secret is `ucPjka5tntB2KqsP` (public knowledge for this client).
3. Refresh: same token endpoint with `grant_type=refresh_token`, `refresh_token`, `scope`, `token_format=jwt`.

- [ ] **Step 1: Write the failing test**

`spec/psn_client/auth_spec.rb`:

```ruby
# frozen_string_literal: true

RSpec.describe PSN::Auth do
  let(:authorize_url) { "https://ca.account.sony.com/api/authz/v3/oauth/authorize" }
  let(:token_url) { "https://ca.account.sony.com/api/authz/v3/oauth/token" }

  def stub_authorize(npsso: "NPSSO123", code: "v3.ABC")
    stub_request(:get, authorize_url)
      .with(query: hash_including("client_id" => "09515159-7237-4370-9b40-3806e67c0891"),
            headers: { "Cookie" => "npsso=#{npsso}" })
      .to_return(status: 302,
                 headers: { "Location" => "com.scee.psxandroid.scecompcall://redirect?code=#{code}&cid=x" })
  end

  def token_body(access: "AT-1", refresh: "RT-1", expires_in: 3600)
    { access_token: access, refresh_token: refresh, expires_in: expires_in }.to_json
  end

  it "requires exactly one of npsso or refresh_token" do
    expect { described_class.new }.to raise_error(ArgumentError)
    expect { described_class.new(npsso: "a", refresh_token: "b") }.to raise_error(ArgumentError)
  end

  it "exchanges an NPSSO for tokens on first access" do
    stub_authorize
    token_stub = stub_request(:post, token_url)
      .with(body: hash_including("grant_type" => "authorization_code", "code" => "v3.ABC"))
      .to_return(status: 200, body: token_body, headers: { "Content-Type" => "application/json" })

    auth = described_class.new(npsso: "NPSSO123")
    expect(auth.access_token).to eq("AT-1")
    expect(auth.refresh_token).to eq("RT-1")
    expect(token_stub).to have_been_requested.once
  end

  it "reuses a cached unexpired token" do
    stub_authorize
    stub_request(:post, token_url)
      .to_return(status: 200, body: token_body, headers: { "Content-Type" => "application/json" })
    auth = described_class.new(npsso: "NPSSO123")
    2.times { auth.access_token }
    expect(WebMock).to have_requested(:post, token_url).once
  end

  it "raises AuthenticationError when the NPSSO is rejected" do
    stub_request(:get, authorize_url)
      .with(query: hash_including("client_id"))
      .to_return(status: 200, body: "<html>sign in</html>")

    auth = described_class.new(npsso: "expired")
    expect { auth.access_token }.to raise_error(PSN::AuthenticationError, /NPSSO/)
  end

  it "starts from a refresh token without touching the authorize endpoint" do
    stub_request(:post, token_url)
      .with(body: hash_including("grant_type" => "refresh_token", "refresh_token" => "RT-0"))
      .to_return(status: 200, body: token_body(access: "AT-9", refresh: "RT-9"),
                 headers: { "Content-Type" => "application/json" })

    auth = described_class.new(refresh_token: "RT-0")
    expect(auth.access_token).to eq("AT-9")
    expect(auth.refresh_token).to eq("RT-9")
    expect(WebMock).not_to have_requested(:get, authorize_url)
  end

  it "auto-refreshes an expired access token" do
    stub_request(:post, token_url).to_return(
      { status: 200, body: token_body(access: "AT-old", refresh: "RT-1", expires_in: 0),
        headers: { "Content-Type" => "application/json" } },
      { status: 200, body: token_body(access: "AT-new", refresh: "RT-2"),
        headers: { "Content-Type" => "application/json" } }
    )

    auth = described_class.new(refresh_token: "RT-0")
    expect(auth.access_token).to eq("AT-old")
    expect(auth.access_token).to eq("AT-new")
    expect(auth.refresh_token).to eq("RT-2")
  end

  it "raises AuthenticationError when the token endpoint fails" do
    stub_request(:post, token_url).to_return(status: 400, body: '{"error":"invalid_grant"}')
    auth = described_class.new(refresh_token: "bad")
    expect { auth.access_token }.to raise_error(PSN::AuthenticationError) { |e| expect(e.response[:status]).to eq(400) }
  end
end
```

- [ ] **Step 2: Run test to verify it fails**

```powershell
$env:PATH = "C:\Users\matth\scoop\apps\ruby\current\bin;C:\Users\matth\scoop\apps\ruby\current\gems\bin;$env:PATH"; bundle exec rspec spec/psn_client/auth_spec.rb
```

Expected: FAIL — `uninitialized constant PSN::Auth`.

- [ ] **Step 3: Implement**

`lib/psn_client/auth.rb`:

```ruby
# frozen_string_literal: true

require "faraday"
require "json"
require "uri"

module PSN
  # Exchanges an NPSSO token (or a saved refresh token) for PSN OAuth tokens
  # and transparently refreshes the ~1h access token. Tokens are never
  # persisted; read #refresh_token and store it yourself for the next session.
  class Auth
    AUTH_BASE = "https://ca.account.sony.com/api/authz/v3/oauth"
    CLIENT_ID = "09515159-7237-4370-9b40-3806e67c0891"
    CLIENT_SECRET = "ucPjka5tntB2KqsP"
    REDIRECT_URI = "com.scee.psxandroid.scecompcall://redirect"
    SCOPE = "psn:mobile.v2.core psn:clientapp"
    EXPIRY_BUFFER = 60 # seconds; refresh slightly early to absorb clock skew

    attr_reader :refresh_token

    def initialize(npsso: nil, refresh_token: nil)
      unless [npsso, refresh_token].compact.size == 1
        raise ArgumentError, "provide exactly one of npsso: or refresh_token:"
      end

      @npsso = npsso
      @refresh_token = refresh_token
      @access_token = nil
      @expires_at = nil
      @mutex = Mutex.new
    end

    def access_token
      @mutex.synchronize do
        if @access_token.nil?
          authenticate
        elsif expired?
          refresh
        end
        @access_token
      end
    end

    def refresh!
      @mutex.synchronize { refresh }
    end

    private

    def expired?
      @expires_at && Time.now >= @expires_at
    end

    def authenticate
      if @refresh_token
        refresh
      else
        request_token("grant_type" => "authorization_code", "code" => authorization_code,
                      "redirect_uri" => REDIRECT_URI, "token_format" => "jwt")
      end
    end

    def refresh
      raise AuthenticationError, "no refresh token available" unless @refresh_token

      request_token("grant_type" => "refresh_token", "refresh_token" => @refresh_token,
                    "scope" => SCOPE, "token_format" => "jwt")
    end

    def authorization_code
      resp = http.get("#{AUTH_BASE}/authorize") do |req|
        req.params.update("access_type" => "offline", "client_id" => CLIENT_ID,
                          "response_type" => "code", "scope" => SCOPE, "redirect_uri" => REDIRECT_URI)
        req.headers["Cookie"] = "npsso=#{@npsso}"
      end
      extract_code(resp) or raise AuthenticationError.new(
        "NPSSO token rejected — NPSSO tokens expire after ~2 months; fetch a fresh one",
        response: { status: resp.status, body: resp.body }
      )
    end

    def extract_code(resp)
      location = resp.headers["location"].to_s
      return nil unless location.include?("code=")

      URI.decode_www_form(URI(location).query.to_s).to_h["code"]
    end

    def request_token(params)
      resp = http.post("#{AUTH_BASE}/token") do |req|
        req.headers["Authorization"] = "Basic #{["#{CLIENT_ID}:#{CLIENT_SECRET}"].pack("m0")}"
        req.headers["Content-Type"] = "application/x-www-form-urlencoded"
        req.body = URI.encode_www_form(params)
      end
      unless resp.status == 200
        raise AuthenticationError.new("token request failed (HTTP #{resp.status})",
                                      response: { status: resp.status, body: resp.body })
      end
      apply_tokens(JSON.parse(resp.body))
    end

    def apply_tokens(data)
      @access_token = data["access_token"]
      @refresh_token = data["refresh_token"] || @refresh_token
      @expires_at = Time.now + data["expires_in"].to_i - EXPIRY_BUFFER
      @access_token
    end

    def http
      @http ||= Faraday.new # no redirect-following middleware: 302s are returned as-is
    end
  end
end
```

In `lib/psn_client.rb` add after errors require:

```ruby
require_relative "psn_client/auth"
```

- [ ] **Step 4: Run tests, lint, commit**

```powershell
$env:PATH = "C:\Users\matth\scoop\apps\ruby\current\bin;C:\Users\matth\scoop\apps\ruby\current\gems\bin;$env:PATH"; bundle exec rspec; bundle exec rubocop
```

Expected: all pass, no offenses.

```powershell
git add -A; git commit -m "feat: NPSSO/refresh-token OAuth with auto-refresh"
```

---

### Task 4: Connection (Faraday, error mapping, 401 retry)

**Files:**
- Create: `lib/psn_client/connection.rb`, `spec/psn_client/connection_spec.rb`
- Modify: `lib/psn_client.rb` (add require)

**Interfaces:**
- Produces: `PSN::Connection.new(auth, retry_options: nil)`; `#get(host, path, params = {})` and `#post(host, path, body)` → parsed JSON (string keys). `host` is `:mobile` (`m.np.playstation.com`) or `:web` (`web.np.playstation.com`). On 401: calls `auth.refresh!` and retries the request once, then raises. Maps 403→`PrivacyError`, 404→`NotFoundError`, 429→`RateLimitError` (with `retry_after`), other 4xx/5xx→`APIError`.
- Consumes: `PSN::Auth#access_token` / `#refresh!` (Task 3), errors (Task 2).

- [ ] **Step 1: Write the failing test**

`spec/psn_client/connection_spec.rb`:

```ruby
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

  it "maps 403 to PrivacyError" do
    stub_request(:get, url).to_return(status: 403)
    expect { connection.get(:mobile, "/api/test") }.to raise_error(PSN::PrivacyError)
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
end
```

- [ ] **Step 2: Run test to verify it fails**

```powershell
$env:PATH = "C:\Users\matth\scoop\apps\ruby\current\bin;C:\Users\matth\scoop\apps\ruby\current\gems\bin;$env:PATH"; bundle exec rspec spec/psn_client/connection_spec.rb
```

Expected: FAIL — `uninitialized constant PSN::Connection`.

- [ ] **Step 3: Implement**

`lib/psn_client/connection.rb`:

```ruby
# frozen_string_literal: true

require "faraday"
require "faraday/retry"

module PSN
  # Shared HTTP layer: one Faraday connection per PSN host, Bearer auth
  # injected per-request, transient-failure retries, and error mapping.
  class Connection
    HOSTS = {
      mobile: "https://m.np.playstation.com",
      web: "https://web.np.playstation.com"
    }.freeze

    DEFAULT_RETRY_OPTIONS = {
      max: 3,
      interval: 0.5,
      backoff_factor: 2,
      retry_statuses: [500, 502, 503, 504],
      methods: %i[get post]
    }.freeze

    def initialize(auth, retry_options: nil)
      @auth = auth
      @retry_options = DEFAULT_RETRY_OPTIONS.merge(retry_options || {})
      @conns = {}
    end

    def get(host, path, params = {})
      request(host, :get, path, params)
    end

    def post(host, path, body)
      request(host, :post, path, body)
    end

    private

    def request(host, verb, path, payload, retried: false)
      resp = perform(host, verb, path, payload)
      if resp.status == 401 && !retried
        @auth.refresh!
        return request(host, verb, path, payload, retried: true)
      end
      handle_errors(resp)
      resp.body
    end

    def perform(host, verb, path, payload)
      connection(host).public_send(verb, path) do |req|
        req.headers["Authorization"] = "Bearer #{@auth.access_token}"
        verb == :get ? req.params.update(payload) : req.body = payload
      end
    end

    def handle_errors(resp)
      return if resp.status < 400

      response = { status: resp.status, body: resp.body }
      case resp.status
      when 401 then raise AuthenticationError.new("unauthorized", response: response)
      when 403 then raise PrivacyError.new("blocked by the account's privacy settings", response: response)
      when 404 then raise NotFoundError.new("not found", response: response)
      when 429 then raise RateLimitError.new("rate limited", response: response,
                                             retry_after: resp.headers["retry-after"]&.to_i)
      else raise APIError.new("PSN API error (HTTP #{resp.status})", response: response)
      end
    end

    def connection(host)
      @conns[host] ||= Faraday.new(url: HOSTS.fetch(host)) do |f|
        f.request :json
        f.request :retry, @retry_options
        f.response :json, content_type: /\bjson/
      end
    end
  end
end
```

Note: 429 is intentionally NOT in `retry_statuses` — WebMock tests would otherwise sleep through backoff; real-world 429s surface as `RateLimitError` with `retry_after` so the caller decides. In `lib/psn_client.rb` add:

```ruby
require_relative "psn_client/connection"
```

- [ ] **Step 4: Run tests, lint, commit**

```powershell
$env:PATH = "C:\Users\matth\scoop\apps\ruby\current\bin;C:\Users\matth\scoop\apps\ruby\current\gems\bin;$env:PATH"; bundle exec rspec; bundle exec rubocop
```

Expected: all pass, no offenses.

```powershell
git add -A; git commit -m "feat: shared Faraday connection with error mapping and 401 retry"
```

---

### Task 5: Paginator (lazy offset + cursor paging)

**Files:**
- Create: `lib/psn_client/paginator.rb`, `spec/psn_client/paginator_spec.rb`
- Modify: `lib/psn_client.rb` (add require)

**Interfaces:**
- Produces: `PSN::Paginator.offset(page_size:) { |limit, offset| [items, total_item_count] }` and `PSN::Paginator.cursor { |cursor| [items, next_cursor] }` — both return `Enumerator::Lazy` over the raw items; the block is called once per page, only as items are consumed. The first `cursor` call receives `nil`.

- [ ] **Step 1: Write the failing test**

`spec/psn_client/paginator_spec.rb`:

```ruby
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
  end
end
```

- [ ] **Step 2: Run test to verify it fails**

```powershell
$env:PATH = "C:\Users\matth\scoop\apps\ruby\current\bin;C:\Users\matth\scoop\apps\ruby\current\gems\bin;$env:PATH"; bundle exec rspec spec/psn_client/paginator_spec.rb
```

Expected: FAIL — `uninitialized constant PSN::Paginator`.

- [ ] **Step 3: Implement**

`lib/psn_client/paginator.rb`:

```ruby
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
```

In `lib/psn_client.rb` add:

```ruby
require_relative "psn_client/paginator"
```

- [ ] **Step 4: Run tests, lint, commit**

```powershell
$env:PATH = "C:\Users\matth\scoop\apps\ruby\current\bin;C:\Users\matth\scoop\apps\ruby\current\gems\bin;$env:PATH"; bundle exec rspec; bundle exec rubocop
```

Expected: all pass, no offenses.

```powershell
git add -A; git commit -m "feat: lazy offset and cursor paginator"
```

---

### Task 6: Game & trophy models

**Files:**
- Create: `lib/psn_client/models/mapping.rb`, `lib/psn_client/models/game_title.rb`, `lib/psn_client/models/trophy_title.rb`, `lib/psn_client/models/trophy.rb`, `lib/psn_client/models/trophy_summary.rb`
- Create: `spec/psn_client/models/game_title_spec.rb`, `spec/psn_client/models/trophy_models_spec.rb`
- Create: `spec/fixtures/game_title.json`, `spec/fixtures/trophy_title.json`, `spec/fixtures/trophy_merged.json`, `spec/fixtures/trophy_summary.json`
- Modify: `lib/psn_client.rb` (add requires)

**Interfaces:**
- Produces:
  - `PSN::Mapping.time(str)` → `Time`/nil; `PSN::Mapping.duration_seconds("PT2H3M4S")` → Integer/nil; `PSN::Mapping.grade_counts(hash)` → `{bronze:, silver:, gold:, platinum:}`/nil; `PSN::Mapping.platform("ps4_game")` → `"PS4"` (unknown categories pass through).
  - `PSN::GameTitle.from_api(hash)` → Data(name, title_id, platform, play_count, first_played_at, last_played_at, play_duration, raw)
  - `PSN::TrophyTitle.from_api(hash)` → Data(name, np_communication_id, np_service_name, platform, progress, earned_counts, defined_counts, raw)
  - `PSN::Trophy.from_api(hash)` → Data(id, name, detail, grade, hidden, rarity, earned, earned_at, raw), plus `#earned?`
  - `PSN::TrophySummary.from_api(hash)` → Data(level, progress, tier, earned_counts, raw)
- All models keep the untouched input hash as `#raw`; unmapped fields never raise.

- [ ] **Step 1: Write fixtures**

`spec/fixtures/game_title.json` (shape of one entry from `gamelist/v2 .. /titles`):

```json
{
  "titleId": "PPSA01325_00",
  "name": "ASTRO's PLAYROOM",
  "localizedName": "ASTRO's PLAYROOM",
  "imageUrl": "https://image.api.playstation.com/x.png",
  "category": "ps5_native_game",
  "playCount": 12,
  "firstPlayedDateTime": "2024-12-25T10:00:00Z",
  "lastPlayedDateTime": "2025-06-01T18:30:00Z",
  "playDuration": "PT15H2M32S"
}
```

`spec/fixtures/trophy_title.json` (one entry from `trophyTitles`):

```json
{
  "npCommunicationId": "NPWR20188_00",
  "npServiceName": "trophy2",
  "trophyTitleName": "ASTRO's PLAYROOM",
  "trophyTitlePlatform": "PS5",
  "progress": 71,
  "definedTrophies": { "bronze": 24, "silver": 12, "gold": 6, "platinum": 1 },
  "earnedTrophies": { "bronze": 20, "silver": 8, "gold": 2, "platinum": 0 }
}
```

`spec/fixtures/trophy_merged.json` (a title-trophy definition merged with the user's earned record — what `Trophies#earned` feeds to `Trophy.from_api`):

```json
{
  "trophyId": 1,
  "trophyHidden": false,
  "trophyType": "gold",
  "trophyName": "One Small Step",
  "trophyDetail": "Take your first step.",
  "trophyIconUrl": "https://image.api.playstation.com/t.png",
  "earned": true,
  "earnedDateTime": "2025-01-02T20:15:00Z",
  "trophyEarnedRate": "42.1",
  "trophyRare": 1
}
```

`spec/fixtures/trophy_summary.json`:

```json
{
  "accountId": "1234567890",
  "trophyLevel": 401,
  "progress": 60,
  "tier": 3,
  "earnedTrophies": { "bronze": 800, "silver": 400, "gold": 100, "platinum": 10 }
}
```

- [ ] **Step 2: Write the failing tests**

`spec/psn_client/models/game_title_spec.rb`:

```ruby
# frozen_string_literal: true

RSpec.describe PSN::GameTitle do
  subject(:title) { described_class.from_api(fixture("game_title")) }

  it "maps Sony's fields to Ruby types" do
    expect(title.name).to eq("ASTRO's PLAYROOM")
    expect(title.title_id).to eq("PPSA01325_00")
    expect(title.platform).to eq("PS5")
    expect(title.play_count).to eq(12)
    expect(title.first_played_at).to eq(Time.utc(2024, 12, 25, 10, 0, 0))
    expect(title.last_played_at).to eq(Time.utc(2025, 6, 1, 18, 30, 0))
  end

  it "parses ISO-8601 play duration into seconds" do
    expect(title.play_duration).to eq((15 * 3600) + (2 * 60) + 32)
  end

  it "keeps the raw hash and tolerates missing fields" do
    expect(title.raw["imageUrl"]).to match(/playstation/)
    sparse = described_class.from_api({ "titleId" => "X" })
    expect(sparse.name).to be_nil
    expect(sparse.play_duration).to be_nil
  end

  it "passes unknown categories through as-is" do
    weird = described_class.from_api({ "category" => "unknown_thing" })
    expect(weird.platform).to eq("unknown_thing")
  end
end
```

`spec/psn_client/models/trophy_models_spec.rb`:

```ruby
# frozen_string_literal: true

RSpec.describe "trophy models" do
  describe PSN::TrophyTitle do
    subject(:title) { described_class.from_api(fixture("trophy_title")) }

    it "maps title fields and grade counts" do
      expect(title.name).to eq("ASTRO's PLAYROOM")
      expect(title.np_communication_id).to eq("NPWR20188_00")
      expect(title.np_service_name).to eq("trophy2")
      expect(title.platform).to eq("PS5")
      expect(title.progress).to eq(71)
      expect(title.earned_counts).to eq(bronze: 20, silver: 8, gold: 2, platinum: 0)
      expect(title.defined_counts).to eq(bronze: 24, silver: 12, gold: 6, platinum: 1)
    end
  end

  describe PSN::Trophy do
    subject(:trophy) { described_class.from_api(fixture("trophy_merged")) }

    it "maps trophy fields including grade symbol and earned time" do
      expect(trophy.id).to eq(1)
      expect(trophy.name).to eq("One Small Step")
      expect(trophy.detail).to eq("Take your first step.")
      expect(trophy.grade).to eq(:gold)
      expect(trophy.hidden).to be(false)
      expect(trophy.rarity).to eq(42.1)
      expect(trophy).to be_earned
      expect(trophy.earned_at).to eq(Time.utc(2025, 1, 2, 20, 15, 0))
    end

    it "defaults to unearned when earned data is absent" do
      unearned = described_class.from_api(fixture("trophy_merged").except("earned", "earnedDateTime"))
      expect(unearned.earned).to be(false)
      expect(unearned.earned_at).to be_nil
    end
  end

  describe PSN::TrophySummary do
    subject(:summary) { described_class.from_api(fixture("trophy_summary")) }

    it "maps level, tier and counts" do
      expect(summary.level).to eq(401)
      expect(summary.progress).to eq(60)
      expect(summary.tier).to eq(3)
      expect(summary.earned_counts).to eq(bronze: 800, silver: 400, gold: 100, platinum: 10)
    end
  end
end
```

- [ ] **Step 3: Run tests to verify they fail**

```powershell
$env:PATH = "C:\Users\matth\scoop\apps\ruby\current\bin;C:\Users\matth\scoop\apps\ruby\current\gems\bin;$env:PATH"; bundle exec rspec spec/psn_client/models
```

Expected: FAIL — `uninitialized constant PSN::GameTitle`.

- [ ] **Step 4: Implement**

`lib/psn_client/models/mapping.rb`:

```ruby
# frozen_string_literal: true

require "time"

module PSN
  # Shared helpers for converting Sony API values to Ruby types.
  module Mapping
    module_function

    def time(value)
      value && Time.iso8601(value)
    end

    # "PT15H2M32S" -> 54152 (seconds)
    def duration_seconds(value)
      return nil unless value

      match = value.match(/PT(?:(\d+)H)?(?:(\d+)M)?(?:(\d+(?:\.\d+)?)S)?/)
      return nil unless match

      (match[1].to_i * 3600) + (match[2].to_i * 60) + match[3].to_f.round
    end

    def grade_counts(hash)
      return nil unless hash

      { bronze: hash["bronze"].to_i, silver: hash["silver"].to_i,
        gold: hash["gold"].to_i, platinum: hash["platinum"].to_i }
    end

    GAME_PLATFORMS = {
      "ps5_native_game" => "PS5", "ps4_game" => "PS4", "ps3_game" => "PS3",
      "psvita_game" => "PS Vita", "pspc_game" => "PC"
    }.freeze

    # "ps5_native_game" -> "PS5"; unknown categories pass through unchanged.
    def platform(category)
      GAME_PLATFORMS.fetch(category, category)
    end
  end
end
```

`lib/psn_client/models/game_title.rb`:

```ruby
# frozen_string_literal: true

module PSN
  GameTitle = Data.define(:name, :title_id, :platform, :play_count,
                          :first_played_at, :last_played_at, :play_duration, :raw) do
    def self.from_api(hash)
      new(name: hash["name"], title_id: hash["titleId"],
          platform: Mapping.platform(hash["category"]),
          play_count: hash["playCount"],
          first_played_at: Mapping.time(hash["firstPlayedDateTime"]),
          last_played_at: Mapping.time(hash["lastPlayedDateTime"]),
          play_duration: Mapping.duration_seconds(hash["playDuration"]),
          raw: hash)
    end
  end
end
```

`lib/psn_client/models/trophy_title.rb`:

```ruby
# frozen_string_literal: true

module PSN
  TrophyTitle = Data.define(:name, :np_communication_id, :np_service_name, :platform,
                            :progress, :earned_counts, :defined_counts, :raw) do
    def self.from_api(hash)
      new(name: hash["trophyTitleName"], np_communication_id: hash["npCommunicationId"],
          np_service_name: hash["npServiceName"], platform: hash["trophyTitlePlatform"],
          progress: hash["progress"],
          earned_counts: Mapping.grade_counts(hash["earnedTrophies"]),
          defined_counts: Mapping.grade_counts(hash["definedTrophies"]),
          raw: hash)
    end
  end
end
```

`lib/psn_client/models/trophy.rb`:

```ruby
# frozen_string_literal: true

module PSN
  Trophy = Data.define(:id, :name, :detail, :grade, :hidden, :rarity, :earned, :earned_at, :raw) do
    def self.from_api(hash)
      new(id: hash["trophyId"], name: hash["trophyName"], detail: hash["trophyDetail"],
          grade: hash["trophyType"]&.to_sym, hidden: hash["trophyHidden"],
          rarity: hash["trophyEarnedRate"]&.to_f,
          earned: hash.fetch("earned", false),
          earned_at: Mapping.time(hash["earnedDateTime"]),
          raw: hash)
    end

    def earned? = earned
  end
end
```

`lib/psn_client/models/trophy_summary.rb`:

```ruby
# frozen_string_literal: true

module PSN
  TrophySummary = Data.define(:level, :progress, :tier, :earned_counts, :raw) do
    def self.from_api(hash)
      new(level: hash["trophyLevel"], progress: hash["progress"], tier: hash["tier"],
          earned_counts: Mapping.grade_counts(hash["earnedTrophies"]),
          raw: hash)
    end
  end
end
```

In `lib/psn_client.rb` add (after paginator require):

```ruby
require_relative "psn_client/models/mapping"
require_relative "psn_client/models/game_title"
require_relative "psn_client/models/trophy_title"
require_relative "psn_client/models/trophy"
require_relative "psn_client/models/trophy_summary"
```

- [ ] **Step 5: Run tests, lint, commit**

```powershell
$env:PATH = "C:\Users\matth\scoop\apps\ruby\current\bin;C:\Users\matth\scoop\apps\ruby\current\gems\bin;$env:PATH"; bundle exec rspec; bundle exec rubocop
```

Expected: all pass, no offenses.

```powershell
git add -A; git commit -m "feat: game and trophy Data models with raw escape hatch"
```

---

### Task 7: Transaction & Entitlement models

**Files:**
- Create: `lib/psn_client/models/transaction.rb`, `lib/psn_client/models/entitlement.rb`
- Create: `spec/psn_client/models/store_models_spec.rb`, `spec/fixtures/transaction.json`, `spec/fixtures/entitlement.json`
- Modify: `lib/psn_client.rb` (add requires)

**Interfaces:**
- Produces: `PSN::Transaction.from_api(hash)` → Data(transaction_id, date, description, amount, currency, payment_method, type, raw); `PSN::Entitlement.from_api(hash)` → Data(id, name, type, platform, acquired_at, raw). `amount` is Integer minor units (1999 = £19.99), never a float.
- ⚠️ These map the community-known shapes of undocumented endpoints. Mapping is defensive (`dig`, `||` fallbacks); if `bin/smoke` (Task 13) shows different real-world shapes, only these two files and their fixtures change.

- [ ] **Step 1: Write fixtures**

`spec/fixtures/transaction.json`:

```json
{
  "transactionId": "1234567890123456789",
  "transactionDate": "2025-05-20T14:03:00Z",
  "transactionType": "PURCHASE",
  "transactionItems": [
    { "itemName": "Stellar Blade", "skuId": "UP9000-PPSA07030_00" }
  ],
  "totalPrice": { "value": 6999, "currencyCode": "GBP" },
  "paymentMethodInfo": { "displayName": "Visa **** 1234" }
}
```

`spec/fixtures/entitlement.json`:

```json
{
  "id": "UP9000-PPSA01325_00-GAME000000000000",
  "active_date": "2024-12-25T09:58:00Z",
  "entitlement_type": 5,
  "game_meta": {
    "name": "ASTRO's PLAYROOM",
    "type": "PS5GD",
    "icon_url": "https://image.api.playstation.com/e.png"
  }
}
```

- [ ] **Step 2: Write the failing test**

`spec/psn_client/models/store_models_spec.rb`:

```ruby
# frozen_string_literal: true

RSpec.describe "store models" do
  describe PSN::Transaction do
    subject(:transaction) { described_class.from_api(fixture("transaction")) }

    it "maps id, date, type and payment method" do
      expect(transaction.transaction_id).to eq("1234567890123456789")
      expect(transaction.date).to eq(Time.utc(2025, 5, 20, 14, 3, 0))
      expect(transaction.type).to eq("PURCHASE")
      expect(transaction.payment_method).to eq("Visa **** 1234")
    end

    it "represents money as integer minor units plus currency" do
      expect(transaction.amount).to eq(6999)
      expect(transaction.amount).to be_an(Integer)
      expect(transaction.currency).to eq("GBP")
    end

    it "describes the transaction from its items" do
      expect(transaction.description).to eq("Stellar Blade")
    end

    it "survives a completely different shape via raw" do
      sparse = described_class.from_api({ "orderId" => "X-1" })
      expect(sparse.transaction_id).to eq("X-1")
      expect(sparse.amount).to be_nil
      expect(sparse.raw).to eq("orderId" => "X-1")
    end
  end

  describe PSN::Entitlement do
    subject(:entitlement) { described_class.from_api(fixture("entitlement")) }

    it "maps id, name, type and acquisition time" do
      expect(entitlement.id).to eq("UP9000-PPSA01325_00-GAME000000000000")
      expect(entitlement.name).to eq("ASTRO's PLAYROOM")
      expect(entitlement.type).to eq("PS5GD")
      expect(entitlement.acquired_at).to eq(Time.utc(2024, 12, 25, 9, 58, 0))
    end

    it "derives the platform from the entitlement type" do
      expect(entitlement.platform).to eq("PS5")
      vita = described_class.from_api({ "game_meta" => { "type" => "VITAGD" } })
      expect(vita.platform).to eq("VITA")
      unknown = described_class.from_api({ "game_meta" => { "type" => "SUBSCRIPTION" } })
      expect(unknown.platform).to be_nil
    end
  end
end
```

- [ ] **Step 3: Run test to verify it fails**

```powershell
$env:PATH = "C:\Users\matth\scoop\apps\ruby\current\bin;C:\Users\matth\scoop\apps\ruby\current\gems\bin;$env:PATH"; bundle exec rspec spec/psn_client/models/store_models_spec.rb
```

Expected: FAIL — `uninitialized constant PSN::Transaction`.

- [ ] **Step 4: Implement**

`lib/psn_client/models/transaction.rb`:

```ruby
# frozen_string_literal: true

module PSN
  # NOTE: the transaction-history endpoint is undocumented; mapping is
  # deliberately defensive and everything unmapped stays available in #raw.
  Transaction = Data.define(:transaction_id, :date, :description, :amount,
                            :currency, :payment_method, :type, :raw) do
    def self.from_api(hash)
      total = hash["totalPrice"] || hash.dig("invoice", "totalAmount") || {}
      new(transaction_id: hash["transactionId"] || hash["orderId"],
          date: Mapping.time(hash["transactionDate"] || hash["orderDate"]),
          description: description_from(hash),
          amount: total["value"]&.to_i,
          currency: total["currencyCode"],
          payment_method: hash.dig("paymentMethodInfo", "displayName") || hash["paymentMethod"],
          type: hash["transactionType"] || hash["orderType"],
          raw: hash)
    end

    def self.description_from(hash)
      items = hash["transactionItems"] || hash["orderItems"] || []
      names = items.filter_map { |item| item["itemName"] || item["skuName"] }
      names.empty? ? hash["description"] : names.join(", ")
    end
  end
end
```

`lib/psn_client/models/entitlement.rb`:

```ruby
# frozen_string_literal: true

module PSN
  # NOTE: the entitlements endpoint is undocumented; mapping is deliberately
  # defensive and everything unmapped stays available in #raw.
  Entitlement = Data.define(:id, :name, :type, :platform, :acquired_at, :raw) do
    def self.from_api(hash)
      meta_type = hash.dig("game_meta", "type")
      new(id: hash["id"],
          name: hash.dig("game_meta", "name") || hash["product_name"],
          type: meta_type || hash["entitlement_type"]&.to_s,
          platform: platform_from(meta_type),
          acquired_at: Mapping.time(hash["active_date"] || hash["activation_date"]),
          raw: hash)
    end

    def self.platform_from(type)
      type&.[](/\A(?:PS[345P]|PSP|VITA)/)
    end
  end
end
```

In `lib/psn_client.rb` add after the trophy_summary require:

```ruby
require_relative "psn_client/models/transaction"
require_relative "psn_client/models/entitlement"
```

- [ ] **Step 5: Run tests, lint, commit**

```powershell
$env:PATH = "C:\Users\matth\scoop\apps\ruby\current\bin;C:\Users\matth\scoop\apps\ruby\current\gems\bin;$env:PATH"; bundle exec rspec; bundle exec rubocop
```

Expected: all pass, no offenses.

```powershell
git add -A; git commit -m "feat: transaction and entitlement models with defensive mapping"
```

---

### Task 8: Users resource (online ID → account ID)

**Files:**
- Create: `lib/psn_client/resources/users.rb`, `spec/psn_client/resources/users_spec.rb`
- Modify: `lib/psn_client.rb` (add require)

**Interfaces:**
- Produces: `PSN::Resources::Users.new(connection)`; `#account_id(online_id)` → String — `"me"` when `online_id` is nil, otherwise the numeric account ID resolved via universal search, cached per instance (case-insensitive). Raises `PSN::NotFoundError` when no account matches.
- Consumes: `Connection#post(:mobile, path, body)` (Task 4).

- [ ] **Step 1: Write the failing test**

`spec/psn_client/resources/users_spec.rb`:

```ruby
# frozen_string_literal: true

RSpec.describe PSN::Resources::Users do
  subject(:users) { described_class.new(connection) }

  let(:connection) { instance_double(PSN::Connection) }

  def search_response(results)
    { "domainResponses" => [{ "results" => results }] }
  end

  it "returns 'me' for nil without any request" do
    expect(users.account_id(nil)).to eq("me")
  end

  it "resolves an online ID via universal search and caches it" do
    allow(connection).to receive(:post)
      .with(:mobile, "/api/search/v1/universalSearch",
            { "searchTerm" => "some_player", "domainRequests" => [{ "domain" => "SocialAllAccounts" }] })
      .and_return(search_response([
                                    { "socialMetadata" => { "onlineId" => "some_player_2", "accountId" => "999" } },
                                    { "socialMetadata" => { "onlineId" => "Some_Player", "accountId" => "123456789" } }
                                  ]))

    expect(users.account_id("some_player")).to eq("123456789")
    expect(users.account_id("SOME_PLAYER")).to eq("123456789")
    expect(connection).to have_received(:post).once
  end

  it "raises NotFoundError when no result matches exactly" do
    allow(connection).to receive(:post).and_return(search_response([]))
    expect { users.account_id("ghost_user") }.to raise_error(PSN::NotFoundError, /ghost_user/)
  end
end
```

- [ ] **Step 2: Run test to verify it fails**

```powershell
$env:PATH = "C:\Users\matth\scoop\apps\ruby\current\bin;C:\Users\matth\scoop\apps\ruby\current\gems\bin;$env:PATH"; bundle exec rspec spec/psn_client/resources/users_spec.rb
```

Expected: FAIL — `uninitialized constant PSN::Resources`.

- [ ] **Step 3: Implement**

`lib/psn_client/resources/users.rb`:

```ruby
# frozen_string_literal: true

module PSN
  module Resources
    # Internal: resolves friendly online IDs to Sony's numeric account IDs.
    class Users
      SEARCH_PATH = "/api/search/v1/universalSearch"

      def initialize(connection)
        @connection = connection
        @cache = {}
      end

      def account_id(online_id)
        return "me" if online_id.nil?

        @cache[online_id.downcase] ||= lookup(online_id)
      end

      private

      def lookup(online_id)
        body = { "searchTerm" => online_id, "domainRequests" => [{ "domain" => "SocialAllAccounts" }] }
        results = @connection.post(:mobile, SEARCH_PATH, body).dig("domainResponses", 0, "results") || []
        match = results.find { |r| r.dig("socialMetadata", "onlineId")&.casecmp?(online_id) }
        raise NotFoundError, "no PSN account found with online ID #{online_id.inspect}" unless match

        match.dig("socialMetadata", "accountId")
      end
    end
  end
end
```

In `lib/psn_client.rb` add:

```ruby
require_relative "psn_client/resources/users"
```

- [ ] **Step 4: Run tests, lint, commit**

```powershell
$env:PATH = "C:\Users\matth\scoop\apps\ruby\current\bin;C:\Users\matth\scoop\apps\ruby\current\gems\bin;$env:PATH"; bundle exec rspec; bundle exec rubocop
```

Expected: all pass, no offenses.

```powershell
git add -A; git commit -m "feat: users resource resolving online IDs to account IDs"
```

---

### Task 9: Games resource

**Files:**
- Create: `lib/psn_client/resources/games.rb`, `spec/psn_client/resources/games_spec.rb`
- Modify: `lib/psn_client.rb` (add require)

**Interfaces:**
- Produces: `PSN::Resources::Games.new(connection, users)`; `#played(online_id = nil)` → `Enumerator::Lazy` of `PSN::GameTitle`.
- Consumes: `Connection#get(:mobile, path, params)` (Task 4), `Paginator.offset` (Task 5), `GameTitle.from_api` (Task 6), `Users#account_id` (Task 8).

- [ ] **Step 1: Write the failing test**

`spec/psn_client/resources/games_spec.rb`:

```ruby
# frozen_string_literal: true

RSpec.describe PSN::Resources::Games do
  subject(:games) { described_class.new(connection, users) }

  let(:connection) { instance_double(PSN::Connection) }
  let(:users) { instance_double(PSN::Resources::Users) }

  it "fetches all pages of played titles for the authenticated user" do
    allow(users).to receive(:account_id).with(nil).and_return("me")
    allow(connection).to receive(:get)
      .with(:mobile, "/api/gamelist/v2/users/me/titles", { "limit" => 200, "offset" => 0 })
      .and_return({ "titles" => [fixture("game_title")], "totalItemCount" => 1 })

    result = games.played.to_a
    expect(result.size).to eq(1)
    expect(result.first).to be_a(PSN::GameTitle)
    expect(result.first.name).to eq("ASTRO's PLAYROOM")
  end

  it "resolves another user's online ID and pages lazily" do
    allow(users).to receive(:account_id).with("friend").and_return("42")
    allow(connection).to receive(:get)
      .with(:mobile, "/api/gamelist/v2/users/42/titles", { "limit" => 200, "offset" => 0 })
      .and_return({ "titles" => Array.new(200) { fixture("game_title") }, "totalItemCount" => 400 })

    expect(games.played("friend")).to be_a(Enumerator::Lazy)
    expect(games.played("friend").first(3).size).to eq(3)
    expect(connection).to have_received(:get).once # second page never requested
  end
end
```

- [ ] **Step 2: Run test to verify it fails**

```powershell
$env:PATH = "C:\Users\matth\scoop\apps\ruby\current\bin;C:\Users\matth\scoop\apps\ruby\current\gems\bin;$env:PATH"; bundle exec rspec spec/psn_client/resources/games_spec.rb
```

Expected: FAIL — `uninitialized constant PSN::Resources::Games`.

- [ ] **Step 3: Implement**

`lib/psn_client/resources/games.rb`:

```ruby
# frozen_string_literal: true

module PSN
  module Resources
    class Games
      TITLES_PATH = "/api/gamelist/v2/users/%s/titles"
      PAGE_SIZE = 200

      def initialize(connection, users)
        @connection = connection
        @users = users
      end

      # Every title the account has played, most recent first.
      def played(online_id = nil)
        account_id = @users.account_id(online_id)
        Paginator.offset(page_size: PAGE_SIZE) do |limit, offset|
          response = @connection.get(:mobile, format(TITLES_PATH, account_id),
                                     { "limit" => limit, "offset" => offset })
          [response["titles"] || [], response["totalItemCount"]]
        end.map { |title| GameTitle.from_api(title) }
      end
    end
  end
end
```

In `lib/psn_client.rb` add:

```ruby
require_relative "psn_client/resources/games"
```

- [ ] **Step 4: Run tests, lint, commit**

```powershell
$env:PATH = "C:\Users\matth\scoop\apps\ruby\current\bin;C:\Users\matth\scoop\apps\ruby\current\gems\bin;$env:PATH"; bundle exec rspec; bundle exec rubocop
```

Expected: all pass, no offenses.

```powershell
git add -A; git commit -m "feat: games resource with lazy paged played-titles list"
```

---

### Task 10: Trophies resource

**Files:**
- Create: `lib/psn_client/resources/trophies.rb`, `spec/psn_client/resources/trophies_spec.rb`
- Create: `spec/fixtures/trophy_definition.json`, `spec/fixtures/trophy_earned.json`
- Modify: `lib/psn_client.rb` (add require)

**Interfaces:**
- Produces: `PSN::Resources::Trophies.new(connection, users)`;
  - `#titles(online_id = nil)` → `Enumerator::Lazy` of `TrophyTitle`
  - `#earned(online_id = nil, np_communication_id:, platform: nil)` → `Enumerator::Lazy` of `Trophy` (definitions merged with earned status; `platform:` other than PS5 adds `npServiceName=trophy`)
  - `#summary(online_id = nil)` → `TrophySummary`
- Consumes: `Connection#get` (Task 4), `Paginator.offset` (Task 5), models (Task 6), `Users#account_id` (Task 8).

- [ ] **Step 1: Write fixtures**

`spec/fixtures/trophy_definition.json` (title trophy definition, no user data):

```json
{
  "trophyId": 1,
  "trophyHidden": false,
  "trophyType": "gold",
  "trophyName": "One Small Step",
  "trophyDetail": "Take your first step.",
  "trophyIconUrl": "https://image.api.playstation.com/t.png"
}
```

`spec/fixtures/trophy_earned.json` (user's earned record for the same trophy):

```json
{
  "trophyId": 1,
  "earned": true,
  "earnedDateTime": "2025-01-02T20:15:00Z",
  "trophyEarnedRate": "42.1",
  "trophyRare": 1
}
```

- [ ] **Step 2: Write the failing test**

`spec/psn_client/resources/trophies_spec.rb`:

```ruby
# frozen_string_literal: true

RSpec.describe PSN::Resources::Trophies do
  subject(:trophies) { described_class.new(connection, users) }

  let(:connection) { instance_double(PSN::Connection) }
  let(:users) { instance_double(PSN::Resources::Users, account_id: "me") }

  describe "#titles" do
    it "returns lazy TrophyTitle objects" do
      allow(connection).to receive(:get)
        .with(:mobile, "/api/trophy/v1/users/me/trophyTitles", { "limit" => 100, "offset" => 0 })
        .and_return({ "trophyTitles" => [fixture("trophy_title")], "totalItemCount" => 1 })

      result = trophies.titles.to_a
      expect(result.first).to be_a(PSN::TrophyTitle)
      expect(result.first.np_communication_id).to eq("NPWR20188_00")
    end
  end

  describe "#summary" do
    it "returns a TrophySummary" do
      allow(connection).to receive(:get)
        .with(:mobile, "/api/trophy/v1/users/me/trophySummary", {})
        .and_return(fixture("trophy_summary"))

      expect(trophies.summary.level).to eq(401)
    end
  end

  describe "#earned" do
    def stub_trophy_calls(params)
      allow(connection).to receive(:get)
        .with(:mobile, "/api/trophy/v1/npCommunicationIds/NPWR20188_00/trophyGroups/all/trophies", params)
        .and_return({ "trophies" => [fixture("trophy_definition"),
                                     fixture("trophy_definition").merge("trophyId" => 2, "trophyName" => "Hidden Gem")] })
      allow(connection).to receive(:get)
        .with(:mobile, "/api/trophy/v1/users/me/npCommunicationIds/NPWR20188_00/trophyGroups/all/trophies", params)
        .and_return({ "trophies" => [fixture("trophy_earned")] })
    end

    it "merges definitions with earned status" do
      stub_trophy_calls({})
      result = trophies.earned(np_communication_id: "NPWR20188_00").to_a

      expect(result.size).to eq(2)
      expect(result[0].name).to eq("One Small Step")
      expect(result[0]).to be_earned
      expect(result[0].earned_at).to eq(Time.utc(2025, 1, 2, 20, 15, 0))
      expect(result[1].name).to eq("Hidden Gem")
      expect(result[1]).not_to be_earned
    end

    it "adds npServiceName=trophy for non-PS5 platforms" do
      stub_trophy_calls({ "npServiceName" => "trophy" })
      result = trophies.earned(np_communication_id: "NPWR20188_00", platform: "PS4").to_a
      expect(result.size).to eq(2)
    end

    it "omits npServiceName for PS5 titles" do
      stub_trophy_calls({})
      trophies.earned(np_communication_id: "NPWR20188_00", platform: "PS5").to_a
      expect(connection).to have_received(:get).twice
    end
  end
end
```

- [ ] **Step 3: Run test to verify it fails**

```powershell
$env:PATH = "C:\Users\matth\scoop\apps\ruby\current\bin;C:\Users\matth\scoop\apps\ruby\current\gems\bin;$env:PATH"; bundle exec rspec spec/psn_client/resources/trophies_spec.rb
```

Expected: FAIL — `uninitialized constant PSN::Resources::Trophies`.

- [ ] **Step 4: Implement**

`lib/psn_client/resources/trophies.rb`:

```ruby
# frozen_string_literal: true

module PSN
  module Resources
    class Trophies
      TITLES_PATH = "/api/trophy/v1/users/%s/trophyTitles"
      SUMMARY_PATH = "/api/trophy/v1/users/%s/trophySummary"
      DEFINITIONS_PATH = "/api/trophy/v1/npCommunicationIds/%s/trophyGroups/all/trophies"
      EARNED_PATH = "/api/trophy/v1/users/%s/npCommunicationIds/%s/trophyGroups/all/trophies"
      PAGE_SIZE = 100

      def initialize(connection, users)
        @connection = connection
        @users = users
      end

      def titles(online_id = nil)
        account_id = @users.account_id(online_id)
        Paginator.offset(page_size: PAGE_SIZE) do |limit, offset|
          response = @connection.get(:mobile, format(TITLES_PATH, account_id),
                                     { "limit" => limit, "offset" => offset })
          [response["trophyTitles"] || [], response["totalItemCount"]]
        end.map { |title| TrophyTitle.from_api(title) }
      end

      def summary(online_id = nil)
        account_id = @users.account_id(online_id)
        TrophySummary.from_api(@connection.get(:mobile, format(SUMMARY_PATH, account_id), {}))
      end

      # All trophies for one title, each merged with the user's earned status.
      def earned(online_id = nil, np_communication_id:, platform: nil)
        account_id = @users.account_id(online_id)
        params = service_params(platform)
        definitions = @connection.get(:mobile, format(DEFINITIONS_PATH, np_communication_id), params)
        earned = @connection.get(:mobile, format(EARNED_PATH, account_id, np_communication_id), params)
        merge(definitions["trophies"] || [], earned["trophies"] || []).lazy
      end

      private

      # PS5 titles use the default trophy2 service; everything older needs
      # an explicit npServiceName=trophy.
      def service_params(platform)
        return {} if platform.nil? || platform.to_s.upcase.start_with?("PS5")

        { "npServiceName" => "trophy" }
      end

      def merge(definitions, earned)
        earned_by_id = earned.to_h { |t| [t["trophyId"], t] }
        definitions.map { |d| Trophy.from_api(d.merge(earned_by_id[d["trophyId"]] || {})) }
      end
    end
  end
end
```

In `lib/psn_client.rb` add:

```ruby
require_relative "psn_client/resources/trophies"
```

- [ ] **Step 5: Run tests, lint, commit**

```powershell
$env:PATH = "C:\Users\matth\scoop\apps\ruby\current\bin;C:\Users\matth\scoop\apps\ruby\current\gems\bin;$env:PATH"; bundle exec rspec; bundle exec rubocop
```

Expected: all pass, no offenses.

```powershell
git add -A; git commit -m "feat: trophies resource with titles, merged earned list and summary"
```

---

### Task 11: Store resource

**Files:**
- Create: `lib/psn_client/resources/store.rb`, `spec/psn_client/resources/store_spec.rb`
- Modify: `lib/psn_client.rb` (add require)

**Interfaces:**
- Produces: `PSN::Resources::Store.new(connection)`; `#transactions` → `Enumerator::Lazy` of `Transaction` (cursor-paged); `#entitlements` → `Enumerator::Lazy` of `Entitlement` (offset-paged). Authenticated account only.
- Consumes: `Connection#get` (Task 4), `Paginator` (Task 5), store models (Task 7).
- ⚠️ Endpoint constants below are the community-known paths for these undocumented APIs. They are deliberately kept as constants at the top of this one file; `bin/smoke` (Task 13) verifies them against the real API and any correction lands here.

- [ ] **Step 1: Write the failing test**

`spec/psn_client/resources/store_spec.rb`:

```ruby
# frozen_string_literal: true

RSpec.describe PSN::Resources::Store do
  subject(:store) { described_class.new(connection) }

  let(:connection) { instance_double(PSN::Connection) }

  describe "#transactions" do
    it "walks cursor pages and maps Transaction objects" do
      allow(connection).to receive(:get)
        .with(:web, "/api/transact/v1/purchases/transactions", { "limit" => 50 })
        .and_return({ "transactions" => [fixture("transaction")], "nextCursor" => "c1" })
      allow(connection).to receive(:get)
        .with(:web, "/api/transact/v1/purchases/transactions", { "limit" => 50, "cursor" => "c1" })
        .and_return({ "transactions" => [fixture("transaction").merge("transactionId" => "2")],
                      "nextCursor" => nil })

      result = store.transactions.to_a
      expect(result.size).to eq(2)
      expect(result.first).to be_a(PSN::Transaction)
      expect(result.last.transaction_id).to eq("2")
    end

    it "is lazy" do
      allow(connection).to receive(:get)
        .and_return({ "transactions" => [fixture("transaction")], "nextCursor" => "more" })
      expect(store.transactions.first(1).size).to eq(1)
      expect(connection).to have_received(:get).once
    end
  end

  describe "#entitlements" do
    it "walks offset pages and maps Entitlement objects" do
      allow(connection).to receive(:get)
        .with(:web, "/api/entitlements/v2/users/me/internal_entitlements",
              { "limit" => 50, "offset" => 0 })
        .and_return({ "entitlements" => [fixture("entitlement")], "total_results" => 1 })

      result = store.entitlements.to_a
      expect(result.size).to eq(1)
      expect(result.first).to be_a(PSN::Entitlement)
      expect(result.first.name).to eq("ASTRO's PLAYROOM")
    end
  end
end
```

- [ ] **Step 2: Run test to verify it fails**

```powershell
$env:PATH = "C:\Users\matth\scoop\apps\ruby\current\bin;C:\Users\matth\scoop\apps\ruby\current\gems\bin;$env:PATH"; bundle exec rspec spec/psn_client/resources/store_spec.rb
```

Expected: FAIL — `uninitialized constant PSN::Resources::Store`.

- [ ] **Step 3: Implement**

`lib/psn_client/resources/store.rb`:

```ruby
# frozen_string_literal: true

module PSN
  module Resources
    # Purchases for the AUTHENTICATED account only. Sony does not document
    # these endpoints and has changed them before; all knowledge of their
    # hosts, paths and response keys is confined to this file so a change
    # only lands here (and in the two store models). Verify with bin/smoke.
    class Store
      TRANSACTIONS_HOST = :web
      TRANSACTIONS_PATH = "/api/transact/v1/purchases/transactions"
      ENTITLEMENTS_HOST = :web
      ENTITLEMENTS_PATH = "/api/entitlements/v2/users/me/internal_entitlements"
      PAGE_SIZE = 50

      def initialize(connection)
        @connection = connection
      end

      # Monetary transaction history: orders, refunds, wallet funding.
      def transactions
        Paginator.cursor do |cursor|
          params = { "limit" => PAGE_SIZE }
          params["cursor"] = cursor if cursor
          response = @connection.get(TRANSACTIONS_HOST, TRANSACTIONS_PATH, params)
          [response["transactions"] || [], response["nextCursor"]]
        end.map { |t| Transaction.from_api(t) }
      end

      # Everything the account owns: games, DLC, free claims.
      def entitlements
        Paginator.offset(page_size: PAGE_SIZE) do |limit, offset|
          response = @connection.get(ENTITLEMENTS_HOST, ENTITLEMENTS_PATH,
                                     { "limit" => limit, "offset" => offset })
          [response["entitlements"] || [], response["total_results"]]
        end.map { |e| Entitlement.from_api(e) }
      end
    end
  end
end
```

In `lib/psn_client.rb` add:

```ruby
require_relative "psn_client/resources/store"
```

- [ ] **Step 4: Run tests, lint, commit**

```powershell
$env:PATH = "C:\Users\matth\scoop\apps\ruby\current\bin;C:\Users\matth\scoop\apps\ruby\current\gems\bin;$env:PATH"; bundle exec rspec; bundle exec rubocop
```

Expected: all pass, no offenses.

```powershell
git add -A; git commit -m "feat: store resource for transactions and entitlements"
```

---

### Task 12: Client facade

**Files:**
- Create: `lib/psn_client/client.rb`, `spec/psn_client/client_spec.rb`
- Modify: `lib/psn_client.rb` (add require)

**Interfaces:**
- Produces: `PSN::Client.new(npsso: nil, refresh_token: nil)`; `#games`, `#trophies`, `#store` (memoized resources sharing one connection); `#access_token` (triggers lazy auth), `#refresh_token`.
- Consumes: everything from Tasks 3–11.

- [ ] **Step 1: Write the failing test**

`spec/psn_client/client_spec.rb`:

```ruby
# frozen_string_literal: true

RSpec.describe PSN::Client do
  let(:token_url) { "https://ca.account.sony.com/api/authz/v3/oauth/token" }

  def stub_oauth
    stub_request(:post, token_url).to_return(
      status: 200,
      body: { access_token: "AT-1", refresh_token: "RT-1", expires_in: 3600 }.to_json,
      headers: { "Content-Type" => "application/json" }
    )
  end

  it "exposes memoized resource objects" do
    client = described_class.new(refresh_token: "RT-0")
    expect(client.games).to be_a(PSN::Resources::Games)
    expect(client.trophies).to be_a(PSN::Resources::Trophies)
    expect(client.store).to be_a(PSN::Resources::Store)
    expect(client.games).to equal(client.games)
  end

  it "requires exactly one credential" do
    expect { described_class.new }.to raise_error(ArgumentError)
  end

  it "authenticates lazily and fetches games end-to-end" do
    stub_oauth
    stub_request(:get, "https://m.np.playstation.com/api/gamelist/v2/users/me/titles")
      .with(query: { "limit" => "200", "offset" => "0" },
            headers: { "Authorization" => "Bearer AT-1" })
      .to_return(status: 200,
                 body: { titles: [fixture("game_title")], totalItemCount: 1 }.to_json,
                 headers: { "Content-Type" => "application/json" })

    client = described_class.new(refresh_token: "RT-0")
    expect(WebMock).not_to have_requested(:post, token_url) # nothing yet: lazy

    games = client.games.played.to_a
    expect(games.first.name).to eq("ASTRO's PLAYROOM")
    expect(client.refresh_token).to eq("RT-1")
  end
end
```

- [ ] **Step 2: Run test to verify it fails**

```powershell
$env:PATH = "C:\Users\matth\scoop\apps\ruby\current\bin;C:\Users\matth\scoop\apps\ruby\current\gems\bin;$env:PATH"; bundle exec rspec spec/psn_client/client_spec.rb
```

Expected: FAIL — `uninitialized constant PSN::Client`.

- [ ] **Step 3: Implement**

`lib/psn_client/client.rb`:

```ruby
# frozen_string_literal: true

module PSN
  # Entry point. Authenticates with an NPSSO token or a saved refresh token
  # and exposes the PSN API as namespaced resources.
  #
  #   client = PSN::Client.new(npsso: "...")
  #   client.games.played.first(10)
  #   client.trophies.summary("a_friend")
  #   client.store.transactions.to_a
  class Client
    def initialize(npsso: nil, refresh_token: nil)
      @auth = Auth.new(npsso: npsso, refresh_token: refresh_token)
      @connection = Connection.new(@auth)
    end

    def games = @games ||= Resources::Games.new(@connection, users)
    def trophies = @trophies ||= Resources::Trophies.new(@connection, users)
    def store = @store ||= Resources::Store.new(@connection)

    # Triggers authentication if it has not happened yet.
    def access_token = @auth.access_token

    # Persist this (it rotates) to reconstruct the client without a fresh NPSSO.
    def refresh_token = @auth.refresh_token

    private

    def users = @users ||= Resources::Users.new(@connection)
  end
end
```

In `lib/psn_client.rb` add as the LAST require:

```ruby
require_relative "psn_client/client"
```

- [ ] **Step 4: Run tests, lint, commit**

```powershell
$env:PATH = "C:\Users\matth\scoop\apps\ruby\current\bin;C:\Users\matth\scoop\apps\ruby\current\gems\bin;$env:PATH"; bundle exec rspec; bundle exec rubocop
```

Expected: all pass, no offenses.

```powershell
git add -A; git commit -m "feat: PSN::Client facade"
```

---

### Task 13: Smoke script, README, CI

**Files:**
- Create: `bin/smoke`, `README.md`, `.github/workflows/ci.yml`

**Interfaces:**
- Consumes: the full public API from Task 12.
- Produces: manual live-API verification path (`bin/smoke`), user documentation, CI running rspec + rubocop on Ruby 3.2 and 3.4.

- [ ] **Step 1: Write bin/smoke**

`bin/smoke` (no extension; run with `ruby bin/smoke`):

```ruby
#!/usr/bin/env ruby
# frozen_string_literal: true

# Manual live-API check. NOT part of the test suite. Usage (PowerShell):
#   $env:PSN_NPSSO = "<token>"; ruby bin/smoke
# or with a saved refresh token:
#   $env:PSN_REFRESH_TOKEN = "<token>"; ruby bin/smoke

$LOAD_PATH.unshift File.expand_path("../lib", __dir__)
require "psn_client"

npsso = ENV.fetch("PSN_NPSSO", nil)
refresh = ENV.fetch("PSN_REFRESH_TOKEN", nil)
abort "Set PSN_NPSSO or PSN_REFRESH_TOKEN" unless npsso || refresh

client = npsso ? PSN::Client.new(npsso: npsso) : PSN::Client.new(refresh_token: refresh)

def section(name)
  puts "\n== #{name}"
  yield
rescue PSN::Error => e
  puts "FAILED: #{e.class}: #{e.message}"
  puts "        response: #{e.response.inspect}" if e.response
end

section("Trophy summary") do
  s = client.trophies.summary
  puts "level #{s.level}, counts #{s.earned_counts}"
end

section("5 most recent games") do
  client.games.played.first(5).each { |g| puts "#{g.name} [#{g.platform}] plays=#{g.play_count}" }
end

section("5 trophy titles") do
  client.trophies.titles.first(5).each { |t| puts "#{t.name} (#{t.progress}%)" }
end

section("5 transactions") do
  client.store.transactions.first(5).each { |t| puts "#{t.date} #{t.description} #{t.amount} #{t.currency}" }
end

section("5 entitlements") do
  client.store.entitlements.first(5).each { |e| puts "#{e.name} [#{e.platform}] #{e.acquired_at}" }
end

puts "\nRefresh token (persist for next session):"
puts client.refresh_token
```

- [ ] **Step 2: Write README.md**

````markdown
# psn-client-ruby

Unofficial Ruby client for the PlayStation Network API: games played,
trophies earned, transaction history and entitlements.

## Installation

```ruby
gem "psn-client-ruby"
```

## Authentication

PSN has no public API; this gem uses the same OAuth flow as the official
mobile app. You need an **NPSSO token**: sign in at playstation.com, then
visit <https://ca.account.sony.com/api/v1/ssocookie> (or use a helper
browser extension that fetches it for you). NPSSO tokens last about two
months.

```ruby
require "psn_client"

client = PSN::Client.new(npsso: "your-npsso")

# Persist client.refresh_token (lasts ~2 months, rotates on refresh) and
# skip the NPSSO next time:
client = PSN::Client.new(refresh_token: saved_token)
```

## Usage

All list calls return lazy enumerators — `.first(n)` only fetches the pages
it needs, `.to_a` fetches everything. Every object exposes `#raw` with the
untouched API response.

```ruby
# Games played (any account whose privacy settings allow it)
client.games.played.first(10).each { |g| puts "#{g.name} [#{g.platform}]" }
client.games.played("a_friend").to_a

# Trophies
client.trophies.summary                                  # level, counts
client.trophies.titles.to_a                              # per-game progress
client.trophies.earned(np_communication_id: "NPWR20188_00")
client.trophies.earned("a_friend", np_communication_id: "NPWR00000_00", platform: "PS4")

# Purchases (authenticated account only)
client.store.transactions.first(20)  # orders, refunds, wallet funding
client.store.entitlements.to_a       # everything owned incl. free claims
```

Amounts are integer minor units (`6999` + `"GBP"` = £69.99).

### Errors

All errors subclass `PSN::Error` (`#response` has status and body):
`AuthenticationError`, `PrivacyError` (target account is private),
`NotFoundError`, `RateLimitError` (`#retry_after`), `APIError`.

## Development

```
bundle install
bundle exec rake        # rspec + rubocop
ruby bin/smoke          # live-API check; needs PSN_NPSSO or PSN_REFRESH_TOKEN
```

Note: the transaction/entitlement endpoints are undocumented and may change;
they live in `lib/psn_client/resources/store.rb` if they need updating.

## License

MIT
````

- [ ] **Step 3: Write CI workflow**

`.github/workflows/ci.yml`:

```yaml
name: CI

on:
  push:
    branches: [master, main]
  pull_request:

jobs:
  test:
    runs-on: ubuntu-latest
    strategy:
      matrix:
        ruby: ["3.2", "3.4"]
    steps:
      - uses: actions/checkout@v4
      - uses: ruby/setup-ruby@v1
        with:
          ruby-version: ${{ matrix.ruby }}
          bundler-cache: true
      - run: bundle exec rspec
      - run: bundle exec rubocop
```

- [ ] **Step 4: Full suite, lint, commit**

```powershell
$env:PATH = "C:\Users\matth\scoop\apps\ruby\current\bin;C:\Users\matth\scoop\apps\ruby\current\gems\bin;$env:PATH"; bundle exec rspec; bundle exec rubocop
```

Expected: all pass, no offenses. Also syntax-check the smoke script:

```powershell
$env:PATH = "C:\Users\matth\scoop\apps\ruby\current\bin;C:\Users\matth\scoop\apps\ruby\current\gems\bin;$env:PATH"; ruby -c bin/smoke
```

Expected: `Syntax OK`.

```powershell
git add -A; git commit -m "docs: README, live smoke script and CI workflow"
```

- [ ] **Step 5 (manual, user-assisted): Live smoke verification**

Ask the user to run, with a fresh NPSSO from their psn-npsso-fetcher extension:

```powershell
$env:PATH = "C:\Users\matth\scoop\apps\ruby\current\bin;C:\Users\matth\scoop\apps\ruby\current\gems\bin;$env:PATH"; $env:PSN_NPSSO = "<token>"; ruby bin/smoke
```

Expected: trophy summary, games and trophy titles print real data. If the
transactions or entitlements sections print `FAILED`, capture the error
response, correct the constants in `lib/psn_client/resources/store.rb`
and/or the mapping in `lib/psn_client/models/transaction.rb` /
`entitlement.rb` (and their fixtures) to match reality, re-run tests, and
commit the fix as `fix: align store endpoint/mapping with live API`.
```powershell
git add -A; git commit -m "fix: align store endpoint/mapping with live API"
```
