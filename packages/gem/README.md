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

**公開鍵はリポジトリに置く**。秘密ではないし、ENV にすると環境ごとに同じ値を揃える運用が増えるだけになる。秘密鍵だけが Worker の secret。

```ruby
# config/initializers/cloudflare_origin_jwt.rb
module OriginKeys
  CURRENT  = <<~PEM
    -----BEGIN PUBLIC KEY-----
    ...
    -----END PUBLIC KEY-----
  PEM

  # ローテーション中だけ残す。古いトークンの寿命が切れたら消す。
  PREVIOUS = <<~PEM
    -----BEGIN PUBLIC KEY-----
    ...
    -----END PUBLIC KEY-----
  PEM
end

CloudflareOriginJwt.configure do |config|
  config.public_keys = [OriginKeys::CURRENT, OriginKeys::PREVIOUS]
  config.issuer     = "hairbook-gateway"
  config.audience   = "salonpage"
end
```

ENV で上書きしたい場合だけ、初期化の前に差し込む。

```ruby
config.public_keys = ENV["CF_ORIGIN_JWT_PUBLIC_KEYS"]&.split(",") || [OriginKeys::CURRENT]
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
| `public_keys` | `[]` | Ed25519 公開鍵の配列。Hash にすると `kid` で選ぶ。空なら middleware は素通し |
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

## デプロイの順序

**gateway を先、origin（Rails）を後**。逆にすると、トークンを付けない古い gateway のリクエストが origin で 404 になる。

```
1. gateway をデプロイ（トークンを付け始める。古い origin は無視するので無害）
2. origin をデプロイ（この時点で全リクエストに有効なトークンが付いている）
```

Workers のデプロイは一括で切り替わるので、「トークン無しの gateway」と「検証する origin」が同時に生きる窓は作らない。Fly 側のロールアウト中も、旧マシンは無視・新マシンは検証で、どちらにもトークンは付いている。

鍵を変えるときは「鍵のローテーション」の順で、origin に新鍵を先に足す。

## 鍵のローテーション

公開鍵は**複数**持てる。切り替えで止まらないように、次の順で回す。

```ruby
# 1. 新しい鍵を「追加」してデプロイ（古い鍵も残す）
config.public_keys = [
  ENV["CF_ORIGIN_JWT_PUBLIC_KEY_2026_11"],
  ENV["CF_ORIGIN_JWT_PUBLIC_KEY_2025_05"],
]

# 2. gateway の署名鍵を新しいものに切り替える（両方の鍵が有効なので即時で安全）

# 3. 古いトークンが寿命で消えたら、古い鍵を外す
config.public_keys = [ENV["CF_ORIGIN_JWT_PUBLIC_KEY_2026_11"]]
```

`kid` をトークンのヘッダに入れると、照合する鍵を1つに絞れる。Hash で登録する。

```ruby
config.public_keys = {
  "2026-11" => ENV["CF_ORIGIN_JWT_PUBLIC_KEY_2026_11"],
  "2025-05" => ENV["CF_ORIGIN_JWT_PUBLIC_KEY_2025_05"],
}
```

`kid` が一致しなければ、登録した全部の鍵を順に試す（鍵が数個なら誤差）。

**署名の寿命（既定 60 秒）より長く古い鍵を残さない**こと。寿命を過ぎたトークンは `exp` で落ちるので、古い鍵を外しても安全。

## 開発

```sh
bundle install
bundle exec rake test
```

## License

MIT
