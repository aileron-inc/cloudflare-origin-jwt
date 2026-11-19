# frozen_string_literal: true

require "minitest/autorun"
require "jwt"
require "jwt/eddsa"
require "ed25519"
require "cloudflare_origin_jwt"

class CloudflareOriginJwtTest < Minitest::Test
  ISS = "hairbook-gateway"
  AUD = "salonpage"

  def setup
    @signing_key = Ed25519::SigningKey.generate
    @verify_key = @signing_key.verify_key
    CloudflareOriginJwt.reset!
    CloudflareOriginJwt.configure do |config|
      config.public_key = @verify_key
      config.issuer = ISS
      config.audience = AUD
    end
    @app = ->(env) { [200, { "content-type" => "text/plain" }, ["ok #{env["PATH_INFO"]}"]] }
    @middleware = CloudflareOriginJwt::Middleware.new(@app)
  end

  def token(overrides = {})
    payload = { iss: ISS, aud: AUD, exp: Time.now.to_i + 60 }.merge(overrides)
    JWT.encode(payload, @signing_key, "EdDSA")
  end

  def env_for(path, token: nil)
    env = { "PATH_INFO" => path, "REQUEST_METHOD" => "GET" }
    env["HTTP_X_CF_ORIGIN_JWT"] = token if token
    env
  end

  def test_passes_a_signed_request_and_exposes_the_claims
    env = env_for("/salons/H1", token: token("flags" => { "page_published" => 1 }))
    status, _headers, body = @middleware.call(env)

    assert_equal 200, status
    assert_equal ["ok /salons/H1"], body
    assert_equal({ "page_published" => 1 }, CloudflareOriginJwt.flags(env))
  end

  def test_rejects_a_request_without_a_token
    status, headers, body = @middleware.call(env_for("/salons/H1"))

    assert_equal 404, status
    assert_equal [], body
    assert_equal "0", headers["content-length"]
  end

  def test_rejects_a_token_signed_by_another_key
    other = Ed25519::SigningKey.generate
    forged = JWT.encode({ iss: ISS, aud: AUD, exp: Time.now.to_i + 60 }, other, "EdDSA")

    assert_equal 404, @middleware.call(env_for("/salons/H1", token: forged)).first
  end

  def test_rejects_the_wrong_issuer_and_audience
    assert_equal 404, @middleware.call(env_for("/x", token: token(iss: "other"))).first
    assert_equal 404, @middleware.call(env_for("/x", token: token(aud: "other"))).first
  end

  def test_rejects_an_expired_token
    assert_equal 404, @middleware.call(env_for("/x", token: token(exp: Time.now.to_i - 120))).first
  end

  def test_lets_the_health_check_through_without_a_token
    assert_equal 200, @middleware.call(env_for("/up")).first
    assert_equal 200, @middleware.call(env_for("/healthz")).first
  end

  def test_does_nothing_when_no_public_key_is_configured
    CloudflareOriginJwt.reset!
    plain = CloudflareOriginJwt::Middleware.new(@app)

    assert_equal 200, plain.call(env_for("/salons/H1")).first
  end

  def test_claims_are_nil_for_a_request_that_was_not_verified
    assert_nil CloudflareOriginJwt.claims(env_for("/up"))
    assert_equal({}, CloudflareOriginJwt.flags(env_for("/up")))
  end

  # --- key rotation -------------------------------------------------------

  def test_accepts_a_token_signed_by_any_configured_key
    next_key = Ed25519::SigningKey.generate
    CloudflareOriginJwt.configure do |config|
      config.public_keys = [@verify_key, next_key.verify_key]
    end
    new_token = JWT.encode({ iss: ISS, aud: AUD, exp: Time.now.to_i + 60 }, next_key, "EdDSA")

    assert_equal 200, @middleware.call(env_for("/x", token: token)).first
    assert_equal 200, @middleware.call(env_for("/x", token: new_token)).first
  end

  def test_rejects_a_token_from_a_key_that_was_removed
    removed = Ed25519::SigningKey.generate
    kept = Ed25519::SigningKey.generate
    CloudflareOriginJwt.configure { |config| config.public_keys = [kept.verify_key] }
    stale = JWT.encode({ iss: ISS, aud: AUD, exp: Time.now.to_i + 60 }, removed, "EdDSA")

    assert_equal 404, @middleware.call(env_for("/x", token: stale)).first
  end

  def test_uses_the_key_named_by_kid
    first = Ed25519::SigningKey.generate
    second = Ed25519::SigningKey.generate
    CloudflareOriginJwt.configure do |config|
      config.public_keys = { "2026-11" => first.verify_key, "2027-05" => second.verify_key }
    end
    signed = JWT.encode({ iss: ISS, aud: AUD, exp: Time.now.to_i + 60 }, second, "EdDSA", { kid: "2027-05" })

    assert_equal 200, @middleware.call(env_for("/x", token: signed)).first
  end

  def test_falls_back_to_every_key_when_the_kid_is_unknown
    first = Ed25519::SigningKey.generate
    CloudflareOriginJwt.configure { |config| config.public_keys = { "2026-11" => first.verify_key } }
    signed = JWT.encode({ iss: ISS, aud: AUD, exp: Time.now.to_i + 60 }, first, "EdDSA", { kid: "unknown" })

    assert_equal 200, @middleware.call(env_for("/x", token: signed)).first
  end
end
