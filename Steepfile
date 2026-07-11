# frozen_string_literal: true

D = Steep::Diagnostic

target :lib do
  signature "sig"
  check "lib"

  library "time"
  library "uri"
  library "json"
  library "delegate"

  # Faraday ships no RBS and the models are Data.define — lenient keeps the
  # checker useful at those boundaries without drowning real findings.
  configure_code_diagnostics(D::Ruby.lenient)
end
