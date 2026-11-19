# frozen_string_literal: true

module CloudflareOriginJwt
  # Everything the middleware needs. Nothing is read from ENV unless the host
  # app puts it there, so a Rails app stays in charge of its own secrets.
  class Configuration
    DEFAULT_HEADER = "HTTP_X_CF_ORIGIN_JWT"
    DEFAULT_EXEMPT_PATHS = ["/up", "/healthz"].freeze
    DEFAULT_LEEWAY = 30
    DEFAULT_STATUS = 404

    attr_accessor :issuer, :audience, :header, :exempt_paths, :leeway, :status, :logger
    attr_reader :public_key

    def initialize
      @header = DEFAULT_HEADER
      @exempt_paths = DEFAULT_EXEMPT_PATHS.dup
      @leeway = DEFAULT_LEEWAY
      @status = DEFAULT_STATUS
    end

    # Accepts an Ed25519::VerifyKey or a PEM string. The parsed key is memoized
    # because decoding happens on every request.
    def public_key=(value)
      @public_key = value
      @verify_key = nil
    end

    def verify_key
      @verify_key ||= VerifyKey.build(public_key)
    end

    # A missing key means the middleware stays out of the way: local
    # development and test runs do not need a gateway in front of them.
    def enabled?
      !verify_key.nil?
    end

    def exempt?(path)
      exempt_paths.any? { |candidate| candidate == path }
    end
  end
end
