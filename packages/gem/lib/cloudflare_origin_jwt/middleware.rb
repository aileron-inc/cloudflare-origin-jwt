# frozen_string_literal: true

require "jwt"
require "jwt/eddsa"

module CloudflareOriginJwt
  # Rejects any request that does not carry a JWT signed by the gateway.
  #
  # The gateway runs at the Cloudflare edge and signs a short-lived token per
  # request. The origin only ever holds public keys, so a compromised origin
  # cannot mint tokens. Anything without a valid token never reaches the app.
  class Middleware
    ENV_KEY = "cloudflare_origin_jwt.claims"

    def initialize(app, configuration: CloudflareOriginJwt.configuration)
      @app = app
      @configuration = configuration
    end

    def call(env)
      config = @configuration
      return @app.call(env) unless config.enabled?
      return @app.call(env) if config.exempt?(env["PATH_INFO"].to_s)

      payload = verify(env[config.header].to_s, config)
      return reject(config) if payload.nil?

      env[ENV_KEY] = payload
      @app.call(env)
    end

    private

    # More than one key is allowed so keys can be rotated. The token's "kid"
    # narrows the search when the host registered keys by kid; otherwise every
    # key is tried, which is cheap with a handful of keys.
    def verify(token, config)
      return nil if token.empty?

      error = nil
      candidates(token, config).each do |key|
        begin
          payload, = JWT.decode(token, key, true, decode_options(config))
          return payload
        rescue JWT::DecodeError => cause
          error = cause
        end
      end
      config.logger&.warn("cloudflare_origin_jwt: #{error&.class}: #{error&.message}")
      nil
    end

    def candidates(token, config)
      keys = config.verify_keys
      named = config.key_for_kid(kid_of(token))
      named ? [named] + (keys - [named]) : keys
    end

    def kid_of(token)
      header, = JWT.decode(token, nil, false)
      header["kid"]
    rescue JWT::DecodeError
      nil
    end

    def decode_options(config)
      {
        algorithm: "EdDSA",
        iss: config.issuer,
        verify_iss: !config.issuer.to_s.empty?,
        aud: config.audience,
        verify_aud: !config.audience.to_s.empty?,
        leeway: config.leeway
      }
    end

    # The body stays empty on purpose: an unauthenticated caller learns only
    # that the path is not theirs to see.
    def reject(config)
      [config.status, { "content-type" => "text/plain; charset=utf-8", "content-length" => "0" }, []]
    end
  end
end
