# cloudflare-origin-jwt

Cloudflare の前段（gateway）が署名した JWT を持たないリクエストを、**origin に届かせない**。

Worker（TypeScript）が署名し、Rails / Rack（Ruby）が検証する。**契約はこのリポジトリの `contract/` に1つだけ**置く。

```
contract/
  claims.json          # フラグを含む claims の形（両言語のテストが読む）
  token.jwt            # Worker が生成したゴールデントークン（Ruby が検証する）
  keys/test-*.pem      # テスト専用の鍵。本物の保護には使わない
packages/
  worker/              # 署名する（Cloudflare Workers / Bun）
  gem/                 # 検証する（Rack middleware / Rails）
```

## なぜ Access ではないか

Cloudflare Access は「誰が入れるか」を決める仕組みで、利用者のログインが要る。**公開ページ**には使えない。この gem は「gateway を通ったか」だけを見るので、誰でも見るページにも置ける。

ログインして使う社内画面を Access で守るなら、別の仕組み（例: [`cloudflare_access_gate`](https://rubygems.org/gems/cloudflare_access_gate)）を使う。

## 仕組み

```
ブラウザ → Cloudflare Worker（gateway）
            秘密鍵で Ed25519 署名、claims にフラグを詰める
            X-Cf-Origin-Jwt ヘッダに載せて origin へ
          → Fly / Rails
            公開鍵で検証。無効なら 404（本文なし）
            検証済みの claims からフラグを読む
```

- origin は**公開鍵だけ**を持つ。origin が漏れてもトークンは偽造できない
- 署名は短命（既定 60 秒）
- 失敗は **404**

## 使い方（Rails）

```ruby
# Gemfile
gem "cloudflare-origin-jwt"
```

```ruby
# config/initializers/cloudflare_origin_jwt.rb
CloudflareOriginJwt.configure do |config|
  config.public_key = ENV["CF_ORIGIN_JWT_PUBLIC_KEY"] # PEM
  config.issuer     = "hairbook-gateway"
  config.audience   = "salonpage"
end
```

`public_key` が空なら何もしない（ローカル開発は gateway 無しで動く）。

```ruby
CloudflareOriginJwt.flags(request.env) # => { "page_published" => 1, ... }
```

## 使い方（Worker）

```ts
import { importPrivateKey, signOriginToken, originTokenHeaders } from "./src/index";

const key = await importPrivateKey(env.CF_ORIGIN_JWT_PRIVATE_KEY);
const token = await signOriginToken(key, {
  iss: "hairbook-gateway",
  aud: "salonpage",
  sub: salonId,
  flags: { page_published: 1, noroshi_reserve: 0, noroshi_production_released: 1 },
});
const headers = originTokenHeaders(token);
```

## 開発

```sh
# Ruby
cd packages/gem && bundle install && bundle exec rake test

# TypeScript
cd packages/worker && bun install && bun test && bun run typecheck

# contract（commit 済みのトークンが今の署名と一致するか）
cd packages/worker && bun run script/emit-fixture.ts && git diff --exit-code ../../contract/token.jwt
```

Ed25519 は決定的なので、同じ鍵と claims からは必ず同じトークンが出る。claim の形を変えると `contract/token.jwt` が差分になり、CI で落ちる。

## 設定（gem）

| 設定 | 既定 | 説明 |
|---|---|---|
| `public_key` | `nil` | Ed25519 公開鍵（PEM か `Ed25519::VerifyKey`）。空なら素通し |
| `issuer` | `nil` | 検証する `iss`。空なら検証しない |
| `audience` | `nil` | 検証する `aud`。空なら検証しない |
| `header` | `HTTP_X_CF_ORIGIN_JWT` | Rack の env キー |
| `exempt_paths` | `["/up", "/healthz"]` | トークン無しで通すパス（完全一致） |
| `leeway` | `30` | 時計ずれの許容（秒） |
| `status` | `404` | 拒否時のステータス |
| `logger` | `nil` | 検証失敗の理由を残す |

## License

MIT
