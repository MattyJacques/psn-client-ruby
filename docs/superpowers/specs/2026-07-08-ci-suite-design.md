# Full GitHub CI suite — design

Date: 2026-07-08
Branch: `ci/full-suite`
Status: approved (scope and design confirmed by Matthew)

## Goal

Expand the existing minimal CI (rspec + rubocop on Ruby 3.2/3.4/head) into a full
suite: hardened test/lint workflow, dependency-update automation, security audit,
and a coverage gate. No release/publish workflow (explicitly out of scope).

## Components

### 1. `.github/workflows/ci.yml` (rewrite)

- Triggers: `push` to `master`/`main`, all `pull_request`s.
- `concurrency` group keyed on workflow + ref with `cancel-in-progress: true`.
- Top-level `permissions: contents: read`.
- Every job: `runs-on: ubuntu-latest`, `timeout-minutes: 10`.
- **test** job: matrix over Ruby `"3.2"`, `"3.3"`, `"3.4"`, `"head"`;
  `fail-fast: false`; `ruby/setup-ruby@v1` with `bundler-cache: true`;
  runs `bundle exec rspec` (coverage gate included — see §3).
  The `head` entry has `continue-on-error: true` so unreleased-Ruby breakage
  warns without blocking merges.
- **lint** job: single Ruby 3.4 run of `bundle exec rubocop`. Not in the matrix
  because rubocop output does not vary by Ruby version.
- **audit** job: single Ruby 3.4 run of `bundle exec bundler-audit check --update`,
  failing on known CVEs. Runs after `bundle install`, so a `Gemfile.lock` exists
  in the workspace even though it is not committed (conventional for a gem).

### 2. `.github/dependabot.yml`

Weekly update PRs for two ecosystems: `bundler` (root directory) and
`github-actions`.

### 3. Coverage gate

- `simplecov ~> 0.22` added to the `:development, :test` Gemfile group
  (`require: false`).
- `bundler-audit` added to the same group so the audit job runs a pinned,
  Bundler-managed version.
- `spec_helper.rb` starts SimpleCov before `require "psn_client"`, filters
  `/spec/`, enables branch coverage, and sets
  `minimum_coverage line: 99, branch: 85`.
- Measured baseline on 2026-07-08: line 99.77% (434/435), branch 87.34% (69/79).
  The gate sits just under baseline so real regressions fail while small
  refactors don't flap.
- `/coverage/` is already gitignored.

### 4. Documentation

Update CLAUDE.md's CI paragraph: matrix is now 3.2–3.4 + head, plus audit job
and the coverage gate.

## Error handling / failure modes

- `head` failures are visible but non-blocking (`continue-on-error`).
- 429s/network flakes don't apply: specs use WebMock, no real HTTP.
- `bundler-audit --update` needs network to refresh the advisory DB; if GitHub's
  runners can't fetch it the job fails loudly rather than passing silently.

## Testing / verification

- `bundle exec rake` locally (rspec with the coverage gate + rubocop).
- `actionlint` on the workflow if available locally.
- CI itself validates end-to-end on the PR for this branch.
