# frozen_string_literal: true

require "openssl"
require "ed25519"

module CloudflareOriginJwt
  # jwt-eddsa only accepts an Ed25519::VerifyKey, never a PEM string. Hosts
  # keep the key in their environment as PEM, so translate once and memoize.
  module VerifyKey
    module_function

    def build(value)
      return value if value.is_a?(::Ed25519::VerifyKey)
      return nil if value.nil?

      text = value.to_s.strip
      return nil if text.empty?

      raw = text.include?("BEGIN") ? raw_from_pem(text) : text
      ::Ed25519::VerifyKey.new(raw.b)
    end

    # OpenSSL 3 parses an Ed25519 SubjectPublicKeyInfo and hands back the 32
    # raw key bytes that the ed25519 gem wants.
    def raw_from_pem(pem)
      OpenSSL::PKey.read(pem).raw_public_key
    end
  end
end
