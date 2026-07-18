# 03. Iceberg REST Catalog (IRC) 仕様

**調査基準日: 2026-07-17** / **一次情報: [`open-api/rest-catalog-open-api.yaml`](https://github.com/apache/iceberg/blob/main/open-api/rest-catalog-open-api.yaml)（main、5822行を精査）**

> **出典の注記**: `https://iceberg.apache.org/rest-catalog-spec/` は Swagger UI がクライアント側で描画する方式のため、仕様本文をそのまま取り込めません。そこで本ドキュメントは、同ページが読み込む大元の YAML を出典としています。

---

## まず知るべきこと: 仕様にバージョンが無い

```yaml
openapi: 3.1.1
info:
  title: Apache Iceberg REST Catalog API
  version: 0.0.1     # ← ずっとこのまま
```

**`info.version` は `0.0.1` のままです。IRC 仕様には意味のあるセマンティックバージョンが付いていません。**

これは実務上重い意味を持ちます。「このカタログは IRC v1.2 準拠」といった表現は成立せず、**機能の有無は Iceberg のリリース番号と、実行時の `GET /v1/config` の `endpoints` フィールドで判断するしかありません**。カタログ実装を比較する際に「仕様準拠度」を単一の数値で語れないのはこのためです。

---

## 1. なぜ REST Catalog が生まれたか

公式の動機説明は、用語集 [`site/docs/terms.md`](https://github.com/apache/iceberg/blob/main/site/docs/terms.md) の「Decoupling Using the REST Catalog」節が唯一です。

> The REST catalog was introduced in the **Iceberg 0.14.0** release and provides greater control over how Iceberg catalogs are implemented. Instead of using technology-specific logic contained in the catalog clients, **the implementation details of a REST catalog lives on the catalog server**. … The server-side logic can be written in **any language** and use any custom technology, as long as the API follows the Iceberg REST Open API specification.

> A great benefit of the REST catalog is that it allows you to use **a single client to talk to any catalog backend**. This increased flexibility makes it easier to make custom catalogs compatible with engines like Athena or Starburst **without requiring the inclusion of a Jar into the classpath**.

| 課題 | REST Catalog による解決 |
|---|---|
| **カタログ実装の乱立**（Hive Metastore, JDBC, Nessie, Glue, DynamoDB, Hadoop + ベンダー独自） | 単一の OpenAPI 契約に統一。「a single client to talk to any catalog backend」 |
| **クライアント側にテクノロジ固有ロジックが分散**（コミットロジック・ロック・リトライがクライアント JAR に埋め込まれる） | 「implementation details … lives on the catalog server」。サーバ側は任意の言語で実装可 |
| **JAR クラスパス依存** | 「without requiring the inclusion of a Jar into the classpath」 |
| **多言語対応の困難**（Thrift ベースの HMS は実質 JVM 前提） | HTTP/JSON なので Python / Rust / Go から素直に実装可能 |

カタログの最重要責務についての公式定義:

> The most important responsibility of a catalog is **tracking a table's current metadata**, which is provided by the catalog when you load a table.

これは [01-architecture.md](01-architecture.md#コミットの実装) で見た「仕様は commit の atomic 操作を標準化していない（カタログ実装依存）」という事実と表裏です。**カタログこそが ACID の実行主体**であり、その実装が乱立していたことが問題でした。

> **未確認事項**: 「Hive Metastore は Thrift で JVM を要求する」「HMS はロッキングの問題を抱えていた」といった具体的な HMS 批判は、**Apache Iceberg の公式一次情報には見つかりませんでした**。これらはベンダーブログ由来の説明です。公式は Hive Thrift service を「批判」ではなく「類似のアーキテクチャ」として引き合いに出しているのみです。

---

## 2. エンドポイント一覧（全35オペレーション）

IRC の API は、大きく **リソース階層（namespace の中に table と view がある）への CRUD** と、それを支える **横断的な操作群**（設定取得・認証・トランザクション・スキャンプランニング・認証情報の払い出し）でできています。namespace / table / view はどれも **list（一覧）・create（作成）・load（読み込み）・update（更新）・drop（削除）・exists（存在確認）** という同じ形をしているので、1つ分かれば残りも読めます。以下、グループごとに見ていきます。

### Configuration

クライアントが**最初に叩くべき**エンドポイントです。サーバの設定と対応機能（ケイパビリティ）を受け取ります（詳細は [§6](#6-get-v1config--ケイパビリティネゴシエーション)）。

| パス | メソッド | operationId | 用途 |
|---|---|---|---|
| `/v1/config` | GET | `getConfig` | カタログ設定取得。**`prefix` を取らない唯一のパス**。`?warehouse=` 対応 |

### OAuth2（非推奨）

トークン取得用ですが、セキュリティ上の理由で**非推奨・削除予定**です。本番では外部の IdP を使います（[§4](#4-認証)）。

| パス | メソッド | operationId | 用途 |
|---|---|---|---|
| `/v1/oauth/tokens` | POST | `getToken` | **DEPRECATED for REMOVAL**（`deprecated: true`）→ [§4](#4-認証) |

### Namespace

テーブルや view をまとめる入れ物（データベースのスキーマに相当）を操作します。

| パス | メソッド | operationId |
|---|---|---|
| `/v1/{prefix}/namespaces` | GET | `listNamespaces`（`?parent=` で階層指定、ページネーション対応） |
| `/v1/{prefix}/namespaces` | POST | `createNamespace` |
| `/v1/{prefix}/namespaces/{namespace}` | GET | `loadNamespaceMetadata` |
| `/v1/{prefix}/namespaces/{namespace}` | HEAD | `namespaceExists` |
| `/v1/{prefix}/namespaces/{namespace}` | DELETE | `dropNamespace` |
| `/v1/{prefix}/namespaces/{namespace}/properties` | POST | `updateProperties` |

**namespace の区切り文字**（見落としやすい）:

> Multipart namespace parts must be separated by the namespace separator as indicated via the /config override `namespace-separator`, which **defaults to the unit separator `0x1F` byte (url encoded `%1F`)**. To be compatible with older clients, servers must use **both** the advertised separator and `0x1F` as valid separators when decoding namespaces.

例: `accounting.tax` → `GET /v1/{prefix}/namespaces/accounting%1Ftax`

### Table

テーブルの CRUD です。中でも `updateTable` が**唯一の書き込み経路**で、追記も削除もコミットはすべてここを通ります（[§3](#3-コミットプロトコル)）。

| パス | メソッド | operationId | 用途 |
|---|---|---|---|
| `/v1/{prefix}/namespaces/{namespace}/tables` | GET | `listTables` | |
| `/v1/{prefix}/namespaces/{namespace}/tables` | POST | `createTable` | `stage-create: true` でステージング |
| `/v1/{prefix}/namespaces/{namespace}/tables/{table}` | GET | `loadTable` | `LoadTableResult` を返す |
| `/v1/{prefix}/namespaces/{namespace}/tables/{table}` | POST | `updateTable` | **コミット** → [§3](#3-コミットプロトコル) |
| `/v1/{prefix}/namespaces/{namespace}/tables/{table}` | DELETE | `dropTable` | `?purgeRequested=` |
| `/v1/{prefix}/namespaces/{namespace}/tables/{table}` | HEAD | `tableExists` | |
| `/v1/{prefix}/namespaces/{namespace}/register` | POST | `registerTable` | 既存 metadata file location で登録 |
| `/v1/{prefix}/namespaces/{namespace}/tables/{table}/unregister` | POST | `unregisterTable` | データを消さずに登録解除 |
| `/v1/{prefix}/tables/rename` | POST | `renameTable` | namespace 跨ぎ可 |
| `/v1/{prefix}/namespaces/{namespace}/tables/{table}/metrics` | POST | `reportMetrics` | |

### View

SQL の view を操作します。テーブルと同じ CRUD の形です。

| パス | メソッド | operationId |
|---|---|---|
| `/v1/{prefix}/namespaces/{namespace}/views` | GET / POST | `listViews` / `createView` |
| `/v1/{prefix}/namespaces/{namespace}/views/{view}` | GET / POST / DELETE / HEAD | `loadView` / `replaceView` / `dropView` / `viewExists` |
| `/v1/{prefix}/views/rename` | POST | `renameView` |
| `/v1/{prefix}/namespaces/{namespace}/register-view` | POST | `registerView`（**1.11.0 で実装**、PR #14870） |

### Function（新しい領域）

SQL の関数（UDF）を扱う新しい領域です。今のところ read 系（一覧・読み込み）のみ。

| パス | メソッド | operationId |
|---|---|---|
| `/v1/{prefix}/namespaces/{namespace}/functions` | GET | `listFunctions` |
| `/v1/{prefix}/namespaces/{namespace}/functions/{function}` | GET | `loadFunction` |

1.11.0 で「Introduce SQL UDF specification」（PR #14117）が入り、`site/docs/udf-spec.md` が存在します。**両者を結びつける明示的な公式記述は未確認**ですが、対応するものと考えられます。

### Transaction

複数のテーブルへの変更を、**1つの単位でまとめてコミット**します。

| パス | メソッド | operationId | 用途 |
|---|---|---|---|
| `/v1/{prefix}/transactions/commit` | POST | `commitTransaction` | **複数テーブルのアトミックコミット**。`CommitTransactionRequest { table-changes: [CommitTableRequest] }` |

### Scan Planning

「どのファイルを読むか」の計画をサーバ側で行う仕組みです（[§7](#7-サーバサイド-scan-planning)）。

| パス | メソッド | operationId |
|---|---|---|
| `/v1/{prefix}/namespaces/{namespace}/tables/{table}/plan` | POST | `planTableScan` |
| `/v1/{prefix}/namespaces/{namespace}/tables/{table}/plan/{plan-id}` | GET | `fetchPlanningResult` |
| `/v1/{prefix}/namespaces/{namespace}/tables/{table}/plan/{plan-id}` | DELETE | `cancelPlanning` |
| `/v1/{prefix}/namespaces/{namespace}/tables/{table}/tasks` | POST | `fetchScanTasks` |

→ [§7](#7-サーバサイド-scan-planning)

### Credentials / Remote Signing

ストレージへアクセスするための**短命の認証情報を払い出す/署名する**エンドポイントです（[§5](#5-credential-vending--remote-signing)）。

| パス | メソッド | operationId |
|---|---|---|
| `/v1/{prefix}/namespaces/{namespace}/tables/{table}/credentials` | GET | `loadCredentials`（`?planId=`, `?referenced-by=`） |
| `/v1/{prefix}/namespaces/{namespace}/tables/{table}/sign` | POST | `signRequest`（**S3 remote signing**） |

→ [§5](#5-credential-vending--remote-signing)

### 横断パラメータ

特定のグループに属さず、多くのエンドポイントで共通して使うパラメータです。

| パラメータ | 位置 | 内容 |
|---|---|---|
| `prefix` | path | 「An optional prefix in the path」→ [§6](#6-get-v1config--ケイパビリティネゴシエーション) |
| `X-Iceberg-Access-Delegation` | header | `vended-credentials` / `remote-signing`（カンマ区切り） |
| `Idempotency-Key` | header | UUID（36文字固定）。「Optional client-provided idempotency key for **safe request retries**」 |
| `pageToken` / `pageSize` | query | ページネーション |
| `referenced-by` | query | view 経由アクセス時の参照チェーン |

---

## 3. コミットプロトコル

### 仕様本文

> Commits have two parts, **requirements** and **updates**. Requirements are assertions that will be validated before attempting to make and commit changes. … **Server implementations are required to fail with a 400 status code if any unknown updates or requirements are received.**

**「unknown requirement は 400 で落とす」という規約が楽観ロックの安全性の要です。** サーバが知らない assertion を黙って無視すると、クライアントが期待した検証が行われないままコミットが通ってしまいます。

### requirements 一覧

| `type` | 追加フィールド | 意味 |
|---|---|---|
| `assert-create` | — | テーブルが未存在であること（create transaction 用） |
| `assert-table-uuid` | `uuid` | table UUID の一致 |
| `assert-ref-snapshot-id` | `ref`, `snapshot-id`（nullable） | 指定 ref が指定スナップショットを参照。**`null` なら「ref がまだ存在しないこと」の表明** |
| `assert-last-assigned-field-id` | `last-assigned-field-id` | 最後に割り当てられた列 ID の一致 |
| `assert-current-schema-id` | `current-schema-id` | 現在のスキーマ ID の一致 |
| `assert-last-assigned-partition-id` | `last-assigned-partition-id` | 最後のパーティション ID の一致 |
| `assert-default-spec-id` | `default-spec-id` | デフォルト spec ID の一致 |
| `assert-default-sort-order-id` | `default-sort-order-id` | デフォルト sort order ID の一致 |

### updates 一覧（23種）

`AssignUUIDUpdate`, `UpgradeFormatVersionUpdate`, `AddSchemaUpdate`, `SetCurrentSchemaUpdate`, `AddPartitionSpecUpdate`, `SetDefaultSpecUpdate`, `AddSortOrderUpdate`, `SetDefaultSortOrderUpdate`, **`AddSnapshotUpdate`**, **`SetSnapshotRefUpdate`**, `RemoveSnapshotsUpdate`, `RemoveSnapshotRefUpdate`, `SetLocationUpdate`, `SetPropertiesUpdate`, `RemovePropertiesUpdate`, `SetStatisticsUpdate`, `RemoveStatisticsUpdate`, `SetPartitionStatisticsUpdate`, `RemovePartitionStatisticsUpdate`, `RemovePartitionSpecsUpdate`, `RemoveSchemasUpdate`, **`AddEncryptionKeyUpdate`**, **`RemoveEncryptionKeyUpdate`**

### 具体例（append コミット）

```http
POST /v1/prod/namespaces/accounting%1Ftax/tables/paid HTTP/1.1
Authorization: Bearer eyJhbGciOi...
Content-Type: application/json
Idempotency-Key: 017F22E2-79B0-7CC3-98C4-DC0C0C07398F
```

```json
{
  "identifier": { "namespace": ["accounting", "tax"], "name": "paid" },
  "requirements": [
    { "type": "assert-table-uuid",
      "uuid": "9c12d441-03fe-4693-9a96-a0705ddf69c1" },
    { "type": "assert-ref-snapshot-id",
      "ref": "main",
      "snapshot-id": 3051729675574597004 }
  ],
  "updates": [
    { "action": "add-snapshot",
      "snapshot": {
        "snapshot-id": 3055729675574597004,
        "parent-snapshot-id": 3051729675574597004,
        "sequence-number": 34,
        "timestamp-ms": 1785000000000,
        "manifest-list": "s3://bucket/warehouse/.../metadata/snap-3055729675574597004-1-.avro",
        "summary": { "operation": "append", "added-data-files": "4", "added-records": "10000" },
        "schema-id": 0
      }
    },
    { "action": "set-snapshot-ref",
      "ref-name": "main", "type": "branch",
      "snapshot-id": 3055729675574597004 }
  ]
}
```

成功レスポンス（200, `CommitTableResponse`。`metadata-location` と `metadata` が required）:

```json
{
  "metadata-location": "s3://bucket/warehouse/.../metadata/00042-9c12d441-....metadata.json",
  "metadata": { "format-version": 2, "table-uuid": "9c12d441-...", "...": "(TableMetadata 全体)" }
}
```

### 409 CommitFailedException

> **Conflict - CommitFailedException, one or more requirements failed. The client may retry.**

```json
{
  "error": {
    "message": "Requirement failed: branch main has changed: expected id 3051729675574597004 != 3055729675574597004",
    "type": "CommitFailedException",
    "code": 409
  }
}
```

**409 はリトライ可能**と仕様が明示しています。テーブルを再ロード → 最新の `snapshot-id` を取得 → requirements を作り直して再コミット、という古典的な CAS リトライループです。

### 500 CommitStateUnknownException — 最重要の落とし穴

> An unknown server-side problem occurred; **the commit state is unknown.**

**409 と 500 の決定的な違い**:

| | 意味 | 対処 |
|---|---|---|
| **409** | コミットは**確実に失敗した** | 安全にリトライできる |
| **500 CommitStateUnknown** | コミットが成功したか失敗したか**わからない** | **単純にリトライするとスナップショットの二重適用が起こりえます** |

これが `Idempotency-Key` ヘッダが存在する理由に直結します（**因果を明示する公式記述は未確認**ですが、`Idempotency-Key` の「safe request retries」および `ServiceUnavailableResponse` の「request could have been partially processed … a **non idempotent request should only be retried by the client when the Retry-After header is present**」という記述と整合します）。

---

## 4. 認証

### 仕様上の securitySchemes

```yaml
security:
  - OAuth2: [catalog]
  - BearerAuth: []
```

> This scheme is used for OAuth2 authorization. For unauthorized requests, services should return an appropriate 401 or 403 response. **Implementations must not return altered success (200) responses when a request is unauthenticated or unauthorized.**

未認可時に「空の結果を 200 で返す」ような挙動を明確に禁止しています（情報漏洩防止）。

**SigV4 は OpenAPI の securitySchemes に含まれていません。** 仕様レベルではなく**クライアント設定プロパティ**として定義されています。

### クライアント認証プロパティ

[`docs/docs/catalog-properties.md`](https://github.com/apache/iceberg/blob/main/docs/docs/catalog-properties.md) より:

> The following catalog properties configure authentication for the REST catalog. They support **Basic, OAuth2, SigV4, and Google** authentication.

| Property | Default | 説明 |
|---|---|---|
| `rest.auth.type` | `none` | `none` / `basic` / `oauth2` / `sigv4` / `google` |
| `rest.auth.basic.username` / `.password` | null | Basic 認証用 |
| `rest.auth.sigv4.delegate-auth-type` | `oauth2` | **SigV4 署名後に委譲する認証方式** |

**OAuth2**

| Property | Default | 説明 |
|---|---|---|
| `token` | null | Bearer token。`token` か `credential` のいずれかが必須 |
| `credential` | null | `client_id:client_secret` 形式 |
| `oauth2-server-uri` | `v1/oauth/tokens` | **REST カタログが OAuth2 認証サーバでない場合は必須** |
| `token-expires-in-ms` | 3600000（1時間） | |
| `token-refresh-enabled` | true | |
| `token-exchange-enabled` | true | 無効化すると client credential flow にフォールバック |
| `scope` | `catalog` | |

**SigV4**

| Property | Default |
|---|---|
| `rest.signing-region` | null |
| `rest.signing-name` | `execute-api` |
| `rest.access-key-id` / `rest.secret-access-key` / `rest.session-token` | null |
| `client.credentials-provider` | null |

> **重要**: `rest.auth.sigv4.delegate-auth-type`（既定 `oauth2`）が示す通り、**SigV4 は排他的ではなく合成可能**です。AWS Glue の IRC エンドポイントのように「SigV4 で署名した上で、さらに OAuth2 トークンを載せる」構成が想定されています。

### `/v1/oauth/tokens` の非推奨

仕様本文（原文）:

> summary: "Get a token using an OAuth2 flow (**DEPRECATED for REMOVAL**)"
>
> The `oauth/tokens` endpoint is **DEPRECATED for REMOVAL**. It is _not_ recommended to implement this endpoint, unless you are fully aware of the potential security implications.
>
> All clients are encouraged to explicitly set the configuration property `oauth2-server-uri` to the correct OAuth endpoint.
>
> **Deprecated since Iceberg (Java) 1.6.0. The endpoint and related types will be removed from this spec in Iceberg (Java) 2.0.**

**非推奨の理由**（[Issue #10537](https://github.com/apache/iceberg/issues/10537) "Security improvements in the Iceberg REST specification"）:

1. **クレデンシャル漏洩リスク** — 正しい OAuth エンドポイントを設定していないと、**平文クレデンシャルを誤ったサービスに送ってしまう**
2. **中間者化（MITM）** — 素朴な実装がトークンリクエストをプロキシしてしまい、OAuth 2.0 仕様に反する中継者になる
3. **認可方式の硬直化** — OAuth 一択を強制し、SAML など他の方式を選べなくする

推奨される方向性は、標準的な OAuth2/OIDC プロバイダ（Okta, Keycloak, Authelia 等）と直接連携し、**IRC サーバから認可サーバの責務を切り離す**ことです。

| バージョン | 日付 | 出来事 |
|---|---|---|
| **1.6.0** | 2024-07-23 | 非推奨化（PR #10603） |
| **2.0** | 未定 | 仕様から**削除**予定 |

> **齟齬の注記**: Issue #10537 のマイルストーンは「M1 (v1.7.0): Deprecate」「M5 (v1.9.0 or v2.0): Remove」とありますが、**リリースノートと OpenAPI 本文の双方が 1.6.0 での非推奨を示しています**。Issue は提案段階の計画、YAML/リリースノートは実際に起きたこと、と解釈すべきです。2026年7月時点で Iceberg 2.0 (Java) は未リリースで、エンドポイントは `deprecated: true` のまま残存しています。

---

## 5. Credential Vending / Remote Signing

### `X-Iceberg-Access-Delegation` ヘッダ

```yaml
name: X-Iceberg-Access-Delegation
in: header
description: >
  Optional signal to the server that the client supports delegated access
  via a comma-separated list of access mechanisms.  The server may choose
  to supply access via any or none of the requested mechanisms.
schema:
  type: array
  items: { type: string, enum: [vended-credentials, remote-signing] }
example: "vended-credentials,remote-signing"
```

**これはシグナルであって要求ではありません。** 「The server may choose to supply access via **any or none** of the requested mechanisms」— サーバは要求されたメカニズムのいずれかを提供することも、**どれも提供しない**ことも選べます。そのためクライアントは、ヘッダを送っても credential が返ってこないケースを常に想定しておく必要があります。

### `LoadTableResult` の規約

> **## Storage Credentials**
> Credentials for ADLS / GCS / S3 / … are provided through the `storage-credentials` field.
> **Clients must first check whether the respective credentials exist in the `storage-credentials` field before checking the `config` for credentials.**

**優先順位ルール**: `storage-credentials` が新しい正式ルートで、`config` 内の `s3.access-key-id` 等はレガシー互換のフォールバックです。

### `StorageCredential` と longest-prefix-wins

```yaml
StorageCredential:
  required: [prefix, config]
  properties:
    prefix:
      description: Indicates a storage location prefix where the credential is relevant.
        **Clients should choose the most specific prefix (by selecting the longest prefix)
        if several credentials of the same type are available.**
    config:
      additionalProperties: { type: string }
```

**longest-prefix-wins ルール**が明記されています。1つのテーブルが複数バケット/コンテナに跨る場合（例: データとメタデータが別ロケーション）に、それぞれ異なるスコープの credential を配ることを想定した設計です。

### やりとりの実例

**リクエスト**:
```http
GET /v1/prod/namespaces/accounting%1Ftax/tables/paid HTTP/1.1
Authorization: Bearer eyJhbGciOi...
X-Iceberg-Access-Delegation: vended-credentials,remote-signing
```

**レスポンス（vended-credentials 選択時）**:
```json
{
  "metadata-location": "s3://bucket/warehouse/.../metadata/00042-....metadata.json",
  "metadata": { "format-version": 2, "...": "..." },
  "config": { "client.region": "us-east-1" },
  "storage-credentials": [
    {
      "prefix": "s3://bucket/warehouse/accounting/tax/paid",
      "config": {
        "s3.access-key-id": "ASIAIOSFODNN7EXAMPLE",
        "s3.secret-access-key": "wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY",
        "s3.session-token": "IQoJb3JpZ2luX2VjE...",
        "s3.session-token-expires-at-ms": "1785000000000"
      }
    }
  ]
}
```

**レスポンス（remote-signing 選択時）**:
```json
{
  "metadata-location": "s3://bucket/.../metadata/00042-....metadata.json",
  "metadata": { "...": "..." },
  "config": {
    "s3.remote-signing-enabled": "true",
    "signer.endpoint": "v1/prod/namespaces/accounting%1Ftax/tables/paid/sign",
    "signer.uri": "https://catalog.example.com"
  }
}
```

この場合、クライアントは S3 への各リクエストについて `POST .../sign` を呼び、サーバが署名した URL/ヘッダを受け取って S3 にアクセスします。**クライアントは AWS クレデンシャルを一切保持しません。**

### なぜセキュリティ上重要か

| 従来（vending なし） | credential vending / remote signing あり |
|---|---|
| エンジン（Spark executor 等）に**長命かつ広範な**ストレージクレデンシャルを配布する必要がある | カタログが**テーブル単位・prefix 単位・短命**の credential を都度払い出す |
| カタログでテーブルレベルの ACL を設定しても、**エンジンがストレージに直接アクセスすればバイパス可能** | ストレージアクセス自体がカタログの認可を経由するため、**バイパス不能** |
| クレデンシャル漏洩でバケット全体が危険 | prefix スコープ + 期限付き。remote signing ならクライアントは credential を**そもそも持たない** |

仕様が裏付ける設計上の根拠:
- `StorageCredential.prefix` + longest-prefix-wins → **最小権限をロケーション粒度で実現**
- `s3.session-token` の存在 → **短命の STS セッション credential** が前提
- `loadCredentials` の `?planId=` → **scan planning で払い出したプラン専用に credential をスコープできる**
- `loadCredentials` の `?referenced-by=` → **view 経由アクセスの参照チェーンをサーバが把握**でき、「元テーブルへの直接権限を与えずに view 経由でのみアクセス許可」を実装可能

> **未確認**: 「カタログ ACL のバイパス防止」という動機付けは仕様設計から論理的に導かれますが、公式がこの言葉で明示的に説明する箇所は見つかりませんでした。

### バージョン履歴

| バージョン | 内容 | PR |
|---|---|---|
| 1.7.0（2024-11-08） | `loadCredentials` エンドポイント追加 | #11281 |
| 1.7.0 | `storage-credentials` フィールドの標準化 | #10722 |
| 1.9.0（2025-04-28） | AWS/GCP: 複数の storage credential prefix をサポート | #12799, #12881 |
| 1.11.0（2026-05-19） | AWS/GCP: held storage credentials の定期リフレッシュ | #15678, #15696 |

S3 remote signing（`/sign`）はさらに古く 1.3 系から存在し、**vending より先にありました**。

---

## 6. `GET /v1/config` — ケイパビリティネゴシエーション

### 適用順序（決定的に重要）

> **All REST clients should first call this route** to get catalog configuration properties from the server…
>
> - **defaults** - properties that should be used as default configuration; applied **before** client configuration
> - **overrides** - properties that should be used to override client configuration; applied **after** defaults and client configuration

```
defaults  →  クライアント設定  →  overrides     （後勝ち）
 ↑弱い                              ↑最強
```

- **`defaults`**: サーバの提案。クライアントが上書きできる。
- **`overrides`**: サーバの命令。クライアントは上書きできない。→ **マルチテナントで運用者がテナントに強制したい値（`warehouse`、`prefix`、FileIO 実装クラス等）を置く場所。**

仕様の例: 「An override might be used to set the **warehouse location, which is stored on the server rather than in client configuration**.」

### `endpoints` フィールドと後方互換設計

> The catalog configuration also holds an optional `endpoints` field… **If a server does not send the `endpoints` field, a default set of endpoints is assumed**

形式は `"<HTTP verb> <resource path>"`（空白1つで区切る）。

**省略時に仮定されるデフォルトセット（13個）**:

```
GET    /v1/{prefix}/namespaces
POST   /v1/{prefix}/namespaces
GET    /v1/{prefix}/namespaces/{namespace}
DELETE /v1/{prefix}/namespaces/{namespace}
POST   /v1/{prefix}/namespaces/{namespace}/properties
GET    /v1/{prefix}/namespaces/{namespace}/tables
POST   /v1/{prefix}/namespaces/{namespace}/tables
GET    /v1/{prefix}/namespaces/{namespace}/tables/{table}
POST   /v1/{prefix}/namespaces/{namespace}/tables/{table}
DELETE /v1/{prefix}/namespaces/{namespace}/tables/{table}
POST   /v1/{prefix}/namespaces/{namespace}/register
POST   /v1/{prefix}/namespaces/{namespace}/tables/{table}/metrics
POST   /v1/{prefix}/tables/rename
POST   /v1/{prefix}/transactions/commit
```

**この後方互換設計が肝です。** `endpoints` を送らない古いサーバは「view も scan planning も credential vending も**サポートしていない**」と正しく解釈されます。逆に言えば、**view 系エンドポイントを1つでも使いたいサーバは `endpoints` を必ず送る必要があります**（デフォルトセットに view が含まれないため）。

### レスポンス例（仕様の example そのまま）

```json
{
  "overrides": { "warehouse": "s3://bucket/warehouse/" },
  "defaults": { "clients": "4" },
  "idempotency-key-lifetime": "PT30M",
  "endpoints": [
    "GET /v1/{prefix}/namespaces/{namespace}",
    "GET /v1/{prefix}/namespaces",
    "POST /v1/{prefix}/namespaces",
    "GET /v1/{prefix}/namespaces/{namespace}/tables/{table}",
    "GET /v1/{prefix}/namespaces/{namespace}/views/{view}"
  ]
}
```

`CatalogConfig` の **required は `defaults` と `overrides` のみ**。`endpoints` と `idempotency-key-lifetime` は optional です。

### `idempotency-key-lifetime`

> **Presence of this field indicates the server supports Idempotency-Key semantics for mutation endpoints. If absent, clients MUST assume idempotency is not supported.**

`endpoints` と同じ「**フィールドの存在＝ケイパビリティの宣言**」パターンです。

### `prefix` とマルチテナント

仕様上の定義は驚くほど素っ気ないものです（原文全文）:

```yaml
prefix:
  name: prefix
  in: path
  schema: { type: string }
  required: true
  description: An optional prefix in the path
```

**確認できた事実**:
- `prefix` は path parameter で `required: true`（パス上は必ず何かが入る）だが description は "An optional prefix"
- `/v1/config` **だけ**が `prefix` を取らない。これが「まず config を叩け」の理由でもある
- `/v1/config` は `?warehouse=` を受け取り、404 は「Warehouse provided in the `warehouse` query parameter is not found」

**典型的なマルチテナントのフロー**（仕様の構造から強く支持される推測）:
1. クライアントが `GET /v1/config?warehouse=my_warehouse` を呼ぶ
2. サーバが `overrides` に `prefix` を入れて返す（例: `{"overrides": {"prefix": "ws/tenant-a/wh-123"}}`）
3. 以降クライアントは全リクエストを `/v1/ws/tenant-a/wh-123/namespaces/...` に送る

> **未確認**: 「prefix はマルチテナント用である」と明言する公式記述は OpenAPI 内に見つかりませんでした。**仕様は意図的に prefix の意味論をサーバ実装に委ねています。** `prefix` に `/` を含められるかも仕様は明示していません。

---

## 7. サーバサイド Scan Planning

### 結論

| 問い | 回答 |
|---|---|
| **仕様に入ったか？** | **入っている。1.7.0（2024-11-08）で OpenAPI に追加**（PR #9695、dev ML の [VOTE] を経て正式マージ） |
| **実装はあるか？** | **ある。1.11.0（2026-05-19）でクライアント実装が完成**（PR #13400 + Spark 統合 #14963） |

**仕様追加（1.7.0）から実用実装（1.11.0）まで約1年半**かかっており、この機能が長く「仕様はあるが Java クライアント実装がない」状態だったことが読み取れます。

| バージョン | 日付 | 内容 | PR |
|---|---|---|---|
| **1.7.0** | 2024-11-08 | OpenAPI: Scan Planning Endpoints 追加（**仕様のみ**） | #9695 |
| **1.10.0** | 2025-09-11 | REST: request/response models and parsers | #13004 |
| **1.11.0** | 2026-05-19 | **REST Scan Planning Task Implementation** | #13400 |
| **1.11.0** | 2026-05-19 | **Spark: Enable remote scan planning** | #14963 |

### なぜ重要か

1.11.0 のリリースブログが位置づけを明確に述べています。

> 1.11.0 は REST カタログプロトコルが導入されて以来、**最も重要な前進**を表す。**Remote scan planning**（PR #13400）はカタログサーバがテーブルスキャンをプランし、file scan task を直接ストリームバックすることを可能にする。**以前は、全てのクライアントがどのファイルを読むか判断するために manifest list と manifest を自分で取得しなければならなかった。server-side planning により、クライアントは関連する scan task のみを受け取り、driver のメモリ圧迫を軽減し、クエリエンジンに透過的なサーバサイド最適化を可能にする。**

これは [06-operations.md](06-operations.md) で扱う「メタデータが肥大するとクライアント側 driver が死ぬ」という構造的問題への**プロトコルレベルの解**です。従来は運用（`expire_snapshots` 等）で対処するしかありませんでした。

1.11.0 はさらに以下も追加しています:
- **incremental scans** への拡張（#14661、Structured Streaming 向け）
- **メタデータテーブル**（`history`, `snapshots` 等）への拡張（#14881）
- **per-table override**（#15572）— 個別テーブルがカタログレベルの mode をオプトアウト可能
- **`scan-planning-mode` を `LoadTableResult` に**（#14867）— クライアントが probing せずに事前に知れる
- **scan planning レスポンスにストレージ認証情報**（#15524）

### ステートマシン

```
POST /plan
   ├─ 200 { status: "completed", plan-tasks: [...], file-scan-tasks: [...] }  → 同期完了
   ├─ 200 { status: "submitted", plan-id: "..." }                             → 非同期。↓へ
   └─ 200 { status: "failed", error: {...} }                                  → 失敗

   GET /plan/{plan-id}   （ポーリング）
      ├─ { status: "submitted" }   → 再ポーリング
      ├─ { status: "completed", plan-tasks: [...], file-scan-tasks: [...] }
      ├─ { status: "cancelled" }
      └─ { status: "failed", error: {...} }

   POST /tasks  { "plan-task": "<opaque>" }   → 各 plan-task を file scan tasks に展開
   DELETE /plan/{plan-id}                     → 不要になったら明示的にキャンセル
```

仕様の規定:
- **「A "cancelled" status is considered invalid for this endpoint」**（`POST /plan` のレスポンスとして）
- 「Responses that include a `plan-id` indicate that the service is **holding state or performing work for the client**」
- **「Cancellation is not necessary after fetchScanTasks has been used to fetch scan tasks for each plan task.」**
- 「Requests that include both point in time config properties and incremental config properties are **invalid**」

### `PlanTableScanRequest` の主なフィールド

| フィールド | 説明 |
|---|---|
| `snapshot-id` | point-in-time scan 用 |
| `select` | 選択するスキーマフィールド |
| `filter` | フィルタ式 |
| `min-rows-requested` | **ヒントであって強制ではない**（「It is not required for the server to return that many rows … The server can also return more rows than requested」） |
| `case-sensitive` | 既定 `true` |
| `use-snapshot-schema` | 既定 `false`。「**When time travelling, the snapshot schema should be used (true). When scanning a branch, the table schema should be used (false).**」 |
| `start-snapshot-id` / `end-snapshot-id` | incremental scan 用（start は**排他的**、end は**包含的**） |
| `stats-fields` | 列統計を返してほしいフィールド |

`PlanTask` の定義: 「**An opaque string** provided by the REST server that represents a unit of work… This allows clients to fetch tasks across multiple requests to accommodate large result sets.」

`FileScanTask.residual-filter`: 「**If the residual is not present, the client must produce the residual or use the original filter.**」

### `scan-planning-mode` — サーバがモードを強制できる

> - `scan-planning-mode`: Communicates to clients the supported planning mode. **Clients should use this value to fail fast if the supported scanning mode is not available on the client.** Valid values:
>   - `client`: Clients **MUST** use client-side scan planning
>   - `server`: Clients **MUST** use server-side scan planning via the `planTableScan` endpoint

**これは強い規定です。** `server` を返すカタログに対しては、クライアントは manifest を自分で読むことを**許されません**。この規定があってはじめて、管理型カタログがガバナンス（行/列レベルセキュリティ、監査）をスキャンプランニングに埋め込み、**クライアントによるメタデータの直接読み取りを禁止する**ユースケースが成立します。

### エコシステムの実装状況

**確認済み**: Iceberg Java 1.11.0（クライアント実装 + Spark 統合）

**未確認 / 二次情報**:
- DuckDB (`duckdb-iceberg`) は 2026年5月時点で未対応（[Issue #977](https://github.com/duckdb/duckdb-iceberg/issues/977) がオープン）
- **PyIceberg は 0.11.0 で REST scan planning に対応**（**同期のみ**、async は将来）→ [05-engine-support.md](05-engine-support.md#pyiceberg)

---

## 8. エラーレスポンス

### `IcebergErrorResponse` — 必ず `error` でラップされる

全ての非 2xx レスポンスは以下の形になります:

```json
{
  "error": {
    "message": "The given namespace does not exist",
    "type": "NoSuchNamespaceException",
    "code": 404
  }
}
```

`ErrorModel` の required は `message` / `type` / `code`。`stack`（string 配列）は optional（本番では返さないのが通例）。

> **よくある実装ミス**: `ErrorModel` を裸で返すこと。仕様上は必ず `{"error": {...}}` でラップします。

### 主要ステータスコード

| コード | 型の例 | 意味 | リトライ |
|---|---|---|---|
| **400** | `BadRequestErrorResponse` | 不正なリクエスト。**unknown updates/requirements は 400 必須** | 不可 |
| **401** | `UnauthorizedResponse` | 未認証 | 再認証後 |
| **403** | `NotAuthorizedException` | 権限不足 | 不可 |
| **404** | `NoSuchTableException` 等 | 対象が存在しない | 不可 |
| **406** | `UnsupportedOperationException` | 「The server does not support this operation」。`planTableScan` 等で使用 | 不可 |
| **409** | `CommitFailedException` / `AlreadyExistsException` | **2つの意味を持つ（下記）** | 文脈による |
| **419** | `AuthenticationTimeoutException` | トークン期限切れ。ただし「**401 SHOULD be preferred over this response type on token expiry**」 | 可 |
| **500** | `CommitStateUnknownException` | **コミット状態不明** | **危険** |
| **503** | `SlowDownException` | 「request could have been **partially processed**」「a non idempotent request should only be retried **when the Retry-After header is present**」 | 条件付き |

### 409 の2つの意味に注意

| 文脈 | 意味 | 対処 |
|---|---|---|
| `updateTable`, `commitTransaction`, `replaceView` | **CommitFailedException** — 楽観ロック競合 | テーブル再ロード → requirements 再構築 → リトライ |
| `createTable`, `createNamespace`, `renameTable`, `registerTable` | **AlreadyExistsException** — 識別子が既に存在 | **リトライ不可** |

### 429 は存在しない

**仕様には 429 Too Many Requests が定義されていません。** レート制限は **503 + `Retry-After`**（`SlowDownException`）で表現するのが仕様の意図です。実装によっては 429 を返す可能性がありますが、仕様準拠クライアントは 503 を期待します。

---

## 補足: REST Compatibility Kit (RCK)

[`open-api/README.md`](https://github.com/apache/iceberg/blob/main/open-api/README.md) より:

> The REST Compatibility Kit (RCK) is a Technology Compatibility Kit (TCK) implementation for the Iceberg REST Specification. It comprises **a series of tests based on the Java reference implementation of the REST Catalog that can be executed against any REST server that implements the spec.**

> The RCK accommodates diverse implementations through configurable test behaviors, acknowledging that **"not all behaviors are strictly defined by the REST Specification."**

1.7.0 で追加されました（PR #10908）。

**この「not all behaviors are strictly defined」という Apache 自身の認識は重要**で、`prefix` の意味論のように、**仕様が意図的に未定義のまま残している領域が存在する**ことを裏付けています。カタログ実装ごとの挙動差が生じる根本原因はここにあります。

---

## 未確認事項

1. **Hive Metastore の具体的批判**（Thrift/JVM 必須、ロッキング問題）— Apache の一次情報には見つからず。ベンダーブログ由来。
2. **Hadoop catalog の限界を REST catalog の動機として語る公式記述** — 未発見。
3. **`prefix` = マルチテナント用という明示** — 構造から導かれる強い推測に留まる。
4. **`prefix` に `/` を含められるか** — 仕様が明示せず。
5. **`Idempotency-Key` が `CommitStateUnknownException` 対策として導入された**という因果 — 記述同士は整合するが明示的な因果の記述は未発見。
6. **credential vending の「カタログ ACL バイパス防止」動機** — 公式がこの言葉で説明する箇所は未発見。
7. **function 系エンドポイントと SQL UDF spec（#14117）の関係** — 両者を結ぶ明示的記述は未確認。
8. **iceberg-rust の scan planning 対応状況** — 未確認。

---

## 出典

**一次情報（Apache Iceberg 公式）**
- OpenAPI 仕様本体: https://github.com/apache/iceberg/blob/main/open-api/rest-catalog-open-api.yaml
- Swagger UI: https://iceberg.apache.org/rest-catalog-spec/
- open-api README (RCK): https://github.com/apache/iceberg/blob/main/open-api/README.md
- 用語集 / REST catalog の背景: https://iceberg.apache.org/terms/
- カタログプロパティ（認証）: https://github.com/apache/iceberg/blob/main/docs/docs/catalog-properties.md
- リリースノート: https://iceberg.apache.org/releases/
- Issue #10537（OAuth セキュリティ改善）: https://github.com/apache/iceberg/issues/10537
- PR #9695（Scan Planning 仕様）/ #13400（実装）/ #14963（Spark 統合）
- PR #11281（loadCredentials）/ #10722（storage-credentials 標準化）
- dev ML [VOTE] Scan Planning APIs: https://www.mail-archive.com/dev@iceberg.apache.org/msg07629.html
- dev ML [DISCUSS] REST: Scan Planning mode: http://www.mail-archive.com/dev@iceberg.apache.org/msg12158.html
