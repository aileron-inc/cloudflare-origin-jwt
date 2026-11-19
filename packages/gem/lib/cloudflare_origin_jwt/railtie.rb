# frozen_string_literal: true

module CloudflareOriginJwt
  # Inserts the middleware in front of everything once the app has configured
  # it, so hosts only add the gem and an initializer.
  class Railtie < Rails::Railtie
    initializer "cloudflare_origin_jwt.middleware" do |app|
      app.config.middleware.insert_before(0, CloudflareOriginJwt::Middleware)
    end
  end
end
