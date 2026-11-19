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
    attr_reader :public_keys

    def initialize
      @header = DEFAULT_HEADER
      @exempt_paths = DEFAULT_EXEMPT_PATHS.dup
      @leeway = DEFAULT_LEEWAY
      @status = DEFAULT_STATUS
      @public_keys = []
    end

    # Several keys at once, so a key can be rotated without a flag day: publish
    # the new one next to the old, switch the gateway, then drop the old.
    #
    # Accepts an Array of PEM strings (or Ed25519::VerifyKey) or a Hash of
    # { "kid" => key }, which lets the token name its key in the JWT header.
    def public_keys=(values)
      @public_keys = values.nil? ? [] : values
      @verify_keys = nil
    end

    # Single-key shorthand, kept for the common case.
    def public_key=(value)
      self.public_keys = value.nil? ? [] : [value]
    end

    def public_key
      list = verify_keys
      list.length == 1 ? list.first : nil
    end

    def verify_keys
      @verify_keys ||= key_list.map { |value| VerifyKey.build(value) }.compact
    end

    def verify_key
      list = verify_keys
      list.length == 1 ? list.first : nil
    end

    # The key the token names in its "kid" header, when the host registered a
    # hash. nil means "try every key".
    def key_for_kid(kid)
      return nil unless public_keys.is_a?(Hash) && !kid.to_s.empty?

      VerifyKey.build(public_keys[kid.to_s])
    end

    # A missing key means the middleware stays out of the way: local
    # development and test runs do not need a gateway in front of them.
    def enabled?
      !verify_keys.empty?
    end

    def exempt?(path)
      exempt_paths.any? { |candidate| candidate == path }
    end

    private

    def key_list
      public_keys.is_a?(Hash) ? public_keys.values : Array(public_keys)
    end
  end
end
