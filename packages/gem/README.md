# cloudflare-origin-jwt

拒否する。**Cloudflare の前段（gateway）が署名した JWT を持たないリクエストは、アプリに届かない。**

Rails / Rack アプリの origin を「うちの gateway 経由だけ」に閉じるための middleware。Cloudflare Access のように利用者へログインを求めないので、**公開ページ**にも使える。

- 検証は EdDSA（Ed25519）。origin は**公開鍵だけ**を持つ。origin が漏れてもトークンは偽造できない
- 署名は短命（既定の例は 60 秒）。リプレイの窓を小さくする
- 失敗は **404**。本文は返さない（存在を隠す）
- 検証済みの claims に、gateway が詰めたデータ（サロンのフラグなど）を載せられる
- 実行時依存は `jwt` と `jwt-eddsa`（公式拡張）だけ。Rails / ActiveSupport に依存しない

## インストール

```ruby
gem "cloudflare-origin-jwt"
```

Rails なら initializer を1つ置くだけで、middleware が先頭に入る（Railtie）。

```ruby
# config/initializers/cloudflare_origin_jwt.rb
CloudflareOriginJwt.configure do |config|
  config.public_key = ENV["CF_ORIGIN_JWT_PUBLIC_KEY"] # PEM
  config.issuer     = "hairbook-gateway"
  config.audience   = "salonpage"
end
```

`public_key` が空なら**何もしない**（ローカル開発・テストは gateway 無しで動く）。

Rails 以外（Rack）:

```ruby
use CloudflareOriginJwt::Middleware
```

## gateway 側（Cloudflare Worker）

リクエストごとに Ed25519 で署名した JWT を作り、ヘッダに載せる。

```js
// 秘密鍵は Worker の secret に置く（PKCS#8 PEM など）
const key = await crypto.subtle.importKey(
  "pkcs8", pemToArrayBuffer(env.CF_ORIGIN_JWT_PRIVATE_KEY),
  { name: "Ed25519" }, false, ["sign"],
);
const b64 = (obj) => btoa(JSON.stringify(obj)).replace(/=+$/, "").replace(/\+/g, "-").replace(/\//g, "_");
const now = Math.floor(Date.now() / 1000);
const payload = b64({ iss: "hairbook-gateway", aud: "salonpage", iat: now, exp: now + 60,
                      flags: { page_published: 1, noroshi_reserve: 0 } });
const input = b64({ alg: "EdDSA", typ: "JWT" }) + "." + payload;
const sig = new Uint8Array(await crypto.subtle.sign({ name: "Ed25519" }, key, new TextEncoder().encode(input)));
const jwt = input + "." + base64url(sig);
headers.set("X-Cf-Origin-Jwt", jwt);
```

## claims の読み方

```ruby
CloudflareOriginJwt.claims(env) # => { "iss" => ..., "aud" => ..., "flags" => { ... } }
CloudflareOriginJwt.flags(env)  # => { "page_published" => 1, ... }（無ければ {}）
```

ビューやコントローラでは `request.env` を渡す。

## 設定

| 設定 | 既定 | 説明 |
|---|---|---|
| `public_key` | `nil` | Ed25519 の公開鍵（PEM か `Ed25519::VerifyKey`）。空なら middleware は素通し |
| `issuer` | `nil` | 検証する `iss`。空なら検証しない |
| `audience` | `nil` | 検証する `aud`。空なら検証しない |
| `header` | `HTTP_X_CF_ORIGIN_JWT` | Rack の env キー |
| `exempt_paths` | `["/up", "/healthz"]` | トークン無しで通すパス（完全一致） |
| `leeway` | `30` | `exp`/`iat` の時計ずれ許容（秒） |
| `status` | `404` | 拒否時のステータス |
| `logger` | `nil` | 検証失敗の理由を残す（`warn`） |

## 注意

- **短命にする**。60 秒程度。長くするとリプレイの窓が広がる
- **鍵は分ける**。gateway ごと・用途ごとに鍵ペアを分けると、片方の漏洩が他へ広がらない
- **Cloudflare Access の代わりではない**。ログインして使う社内画面を Access で守るなら [`cloudflare_access_gate`](https://rubygems.org/gems/cloudflare_access_gate) など別の仕組みを使う。この gem は「gateway を通ったか」だけを見る

## 開発

```sh
bundle install
bundle exec rake test
```

## License

MIT
