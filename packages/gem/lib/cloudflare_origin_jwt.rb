# frozen_string_literal: true

require "cloudflare_origin_jwt/version"
require "cloudflare_origin_jwt/verify_key"
require "cloudflare_origin_jwt/configuration"
require "cloudflare_origin_jwt/middleware"

# Verifies the JWT a Cloudflare Worker puts on origin requests, so a Rails app
# can refuse anything that did not come through the gateway.
#
#   CloudflareOriginJwt.configure do |config|
#     config.public_key = ENV["CF_ORIGIN_JWT_PUBLIC_KEY"]
#     config.issuer     = "hairbook-gateway"
#     config.audience   = "salonpage"
#   end
#
# The gateway may carry data the origin needs (salon flags, for example) in the
# claims; read it with CloudflareOriginJwt.claims(env).
module CloudflareOriginJwt
  class << self
    def configuration
      @configuration ||= Configuration.new
    end

    def configure
      yield configuration
      configuration
    end

    def reset!
      @configuration = nil
    end

    # Claims of the verified request, or nil when no token was verified.
    def claims(env)
      env[Middleware::ENV_KEY]
    end

    # Data the gateway put in the token, as a Hash with string keys.
    def flags(env)
      (claims(env) || {})["flags"] || {}
    end
  end
end

require "cloudflare_origin_jwt/railtie" if defined?(Rails::Railtie)
