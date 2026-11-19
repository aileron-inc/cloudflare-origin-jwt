# frozen_string_literal: true

require_relative "lib/cloudflare_origin_jwt/version"

Gem::Specification.new do |spec|
  spec.name = "cloudflare-origin-jwt"
  spec.version = CloudflareOriginJwt::VERSION
  spec.authors = ["aileron"]
  spec.summary = "Reject origin requests that did not come through your Cloudflare gateway"
  spec.description = <<~TEXT
    Rack middleware that verifies a short-lived EdDSA JWT minted by a Cloudflare
    Worker in front of your app. Requests without a valid token get a 404 and
    never reach the application. Claims can carry data the origin needs, such as
    feature flags. No Rails or ActiveSupport dependency at runtime.
  TEXT
  spec.homepage = "https://github.com/aileron-inc/cloudflare-origin-jwt"
  spec.license = "MIT"
  spec.required_ruby_version = ">= 3.1"

  spec.files = Dir.glob("lib/**/*.rb") + %w[README.md LICENSE.txt]
  spec.require_paths = ["lib"]

  spec.add_dependency "jwt", "~> 3.3"
  spec.add_dependency "jwt-eddsa", "~> 1.1"

  spec.metadata = {
    "homepage_uri" => spec.homepage,
    "source_code_uri" => spec.homepage,
    "rubygems_mfa_required" => "true"
  }
end
