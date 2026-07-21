# 04. カタログ実装の比較

**調査基準日: 2026-07-17** / **健全性シグナル（コミット数・contributor 数）は GitHub API で実測**

[03-rest-catalog.md](03-rest-catalog.md) で見た通り、**IRC 仕様にはバージョン番号がなく**（`info.version: 0.0.1` のまま）、かつ Apache 自身が「**not all behaviors are strictly defined by the REST Specification**」と認めています。したがって「仕様準拠度」を単一の数値で語ることはできません。本ドキュメントでは機能単位で比較します。

---

## 比較表

### 一覧

提供形態とライセンス、credential vending と view の対応です。

| 実装 | 提供形態 | 言語 | ライセンス | vending | View |
|---|---|---|---|---|---|
| **Apache Polaris** | OSS（マネージド版あり） | Java | Apache-2.0 | ○ S3/GCS/Azure | ○ |
| **Project Nessie** | OSS | Java | Apache-2.0 | ○ signing + assume role | ○ |
| **Lakekeeper** | OSS（商用版あり） | **Rust** | Apache-2.0 | ○ **最も充実**（S3 signing+STS, ADLS SAS, GCS） | ○ |
| **Apache Gravitino** | OSS | Java | Apache-2.0 | ○ S3/GCS/ADLS/OSS | ○（1.3.0 で logical view） |
| **Unity Catalog OSS** | OSS | Java/Scala | Apache-2.0 | — | × |
| **Databricks Unity Catalog** | マネージド | — | 商用 | ○（Foreign は不可） | ○（MV は preview） |
| **AWS Glue Data Catalog** | マネージド | — | 商用 | ○ Lake Formation 経由 | × |
| **Amazon S3 Tables** | マネージド | — | 商用 | ※ ネイティブ endpoint では**文書化なし** | × |
| **Cloudflare R2 Data Catalog** | マネージド | — | 商用 | ○（token 権限を継承） | 不明 |
| **Snowflake Open Catalog** | マネージド | — | 商用 | ○ | ○ |
| **Hive Metastore** | OSS | Java | Apache-2.0 | × | 限定 |
| **Hadoop catalog** | OSS | Java | Apache-2.0 | × | — |
| **JDBC catalog** | OSS | Java | Apache-2.0 | × | ○ |
| **Apache XTable** | OSS | Java | Apache-2.0 | — | — |

### 仕様準拠・認証・権限管理

| 実装 | REST 準拠 | 認証 | RBAC / マルチテナント |
|---|---|---|---|
| **Apache Polaris** | 高（IRC の本命） | OAuth2 client_credentials, OIDC | ○ catalog/principal role の2層 |
| **Project Nessie** | **experimental**、branch は独自 URI 記法 | OIDC/Keycloak, OAuth2 | CEL 式ルール |
| **Lakekeeper** | 高（ただし準拠バージョンの公式明記なし） | OIDC/OAuth2, K8s SA。**Kerberos なし** | ○ OpenFGA、project→warehouse |
| **Apache Gravitino** | 中（**マルチテーブル tx・view 登録は非対応と明記**） | Simple/Basic/OAuth2/**Kerberos** | ○ Ranger 連携、metalake 階層 |
| **Unity Catalog OSS** | **読み取り専用・UniForm 経由のみ** | OAuth2/OIDC | 3層権限 |
| **Databricks Unity Catalog** | Managed Iceberg のみ**読み書き可**、Foreign/UniForm は読取のみ | OAuth2/PAT | UC |
| **AWS Glue Data Catalog** | 中（**view API・RenameTable なし**、単一階層 namespace、独自 prefix `/catalogs/{c}`） | **SigV4** | ○ **最も強力**（LF 行/列レベル） |
| **Amazon S3 Tables** | 中（**CTAS 不可**＝stage-create なし、**view 非対応**、purge=false 不可） | SigV4（**OAuth 不可**） | IAM/リソースポリシー |
| **Cloudflare R2 Data Catalog** | 要検証 | **Bearer API token** | token スコープのみ（粗い） |
| **Snowflake Open Catalog** | Polaris 準拠 | Polaris 準拠 | Polaris RBAC + Horizon |
| **Hive Metastore** | REST でない（Thrift） | Kerberos | 弱 |
| **Hadoop catalog** | REST でない | — | × |
| **JDBC catalog** | REST でない | DB 認証 | × |
| **Apache XTable** | **カタログではない**（メタデータ変換器） | — | — |

### 成熟度と現況

| 実装 | 成熟度・現況 |
|---|---|
| **Apache Polaris** | **ASF TLP（2026-02）**、contributor 156、年間 2,100 commits（**うち35%はボット、人間 1,356**） |
| **Project Nessie** | **実質1人保守**（年間の人間コミット245件、うち212が1人。全体の85%はボット）。Dremio 主導だが戦略的地位は低下 |
| **Lakekeeper** | **v0.13.1 / pre-1.0**、star 1.4k、**実質コア2名**、**公表採用事例なし** |
| **Apache Gravitino** | **TLP（2025-06）**、v1.3.0、star 3.1k、**Uber/Pinterest 採用** |
| **Unity Catalog OSS** | LF AI&Data **sandbox**、v0.5.0、API 不安定と明記 |
| **Databricks Unity Catalog** | **GA**（Iceberg v3 も GA） |
| **AWS Glue Data Catalog** | GA |
| **Amazon S3 Tables** | GA（REST は 2025-03〜）、**自動 compaction 標準 ON** |
| **Cloudflare R2 Data Catalog** | **open beta（GA 未達）** |
| **Snowflake Open Catalog** | GA。**ただし新規顧客に実質クローズ**（下記） |
| **Hive Metastore** | 枯れているが漸減。**公式な非推奨宣言は存在しない** |
| **Hadoop catalog** | **S3 で危険**。2.0 での deprecate 提案あり |
| **JDBC catalog** | 安定。**Hadoop catalog の推奨代替** |
| **Apache XTable** | **incubating のまま**。0.3.0-incubating（2025-06）から**13ヶ月リリースなし** |

---

## 主要実装の詳細

### Apache Polaris — TLP 卒業済み（最大の変化）

**2026年2月に Apache Incubator を卒業し Top-Level Project 化しました。**（正確な卒業日は公式ソース間で食い違っており、本報告書は単一の日付には断定しません。下記参照。）

リリース履歴が卒業タイミングと一致しています（`-incubating` サフィックスが 1.3.0 で終わり、1.4.0 以降が TLP リリース）:

| バージョン | 日付 |
|---|---|
| 1.6.0 | 2026-07-09 |
| 1.5.0 | 2026-05-18 |
| 1.4.1 / 1.4.0 | 2026-05-01 / 2026-04-21 |
| 1.3.0-incubating | 2026-01-16 |
| 1.0.0-incubating | 2025-07-11 |

**健全性の実測**: star 2,014 / fork 485 / **全期間 contributor 156** / 直近365日 **2,100 commits（うち 744 = 35.4% は renovate ボット。人間は 1,356）** / 直近365日のユニーク作者 106 / 最終 push 2026-07-16。

ボットを除いても人間 1,356 コミット・106人が関与しており、**開発は実際に活発**です（Nessie とは対照的）。

**Generic Table**: 非 Iceberg テーブル（Delta, CSV 等）を扱う **beta** 機能。**Iceberg REST とは別エンドポイント** `/polaris/v1/{prefix}/namespaces/{ns}/generic-tables`。制約が多く、Schema/Partition spec を持たない・コミット調整をしない・**更新不可（drop & recreate）**・**credential vending 非対応**。

> **要検証**: 1.5 で `Polaris-Generic-Table-Access-Delegation` ヘッダによる vending 拡張が入ったとの Snowflake の記述がありますが、公式 docs の「vending 非対応」という制約記述と食い違います。

> **卒業日は公式ソース3つが3つとも食い違っています**（実測）:
>

> | ソース | 日付 |
> |---|---|
> | [Polaris 公式ブログ](https://polaris.apache.org/blog/2026/02/19/apache-polaris-graduates-to-top-level-project/) | **2026-02-19** |
> | [Incubator ステータスページ](https://incubator.apache.org/projects/polaris.html) | **2026-02-15** |
> | [Incubator プロジェクト一覧](https://incubator.apache.org/projects/) | **2026-02-18** |
>

> 後者2つは**同じ incubator.apache.org 内での自己矛盾**です。02-18 が ASF 理事会の議決日、02-19 がプロジェクト側の告知日である可能性が高いと思われますが、**board minutes を確認していないため断定できません**。本報告書は日付を1つに断定せず、食い違いの存在を事実として記します。
>

> なおステータスページは「2026-02-15 Graduation as TLP.」と**確定形で記載**しており、*projected*（予定）の但し書きは**ありません**（ページ全文を検索して 0 件）。

### Project Nessie — 「Polaris に統合されて廃止」は実現していない

**ここが最も誤解されやすい点です。**

2024年の報道（[BigDATAwire](https://hpcwire.com/bigdatawire/2024/07/30/polaris-catalog-to-be-merged-with-nessie-now-available-on-github/)、[Dremio newsroom](https://www.dremio.com/newsroom/polaris-catalog-to-be-merged-with-nessie-now-available-on-github/)）は Dremio CMO の「We will treat Polaris as our catalog and we will merge Nessie into Polaris」を引用し、**Nessie は retire される**と伝えました。しかし2026年7月の実測は逆です:

- 最新リリース **0.108.2（2026-07-17）**、直近も継続パッチ
- **archived: false**、最終 push は測定日当日
- Nessie 公式サイトに Polaris への統合・廃止の記載は**一切なし**

> **ただし「活発」という評価語は使えません。** 直近365日のコミット 1,652 のうち **85.2%（1,407件）が renovate ボット**で、**人間のコミットは 245 件**、しかも実質1人に集中しています（`snazy` が 212、残り全員で 33）。ユニーク作者は **22人**（Iceberg 270 の 1/12）。**リリース頻度が高いのは、依存更新を自動リリースしているためです。** → [07-ecosystem.md](07-ecosystem.md#a-2-健全性シグナル2026-07-17-実測)

Nessie 自身の[公式アナウンス](https://projectnessie.org/blog/2024/08/02/open-source-polaris-announcement/)の表現は retire ではなく「Nessie の機能（カタログレベル versioning、Git-like セマンティクス、マルチテーブルトランザクション）を Polaris に**コントリビュートする意図**」であり、両者は併存前提です。

**結論**: 「統合の噂」は Dremio 側の発言に基づく報道であり、**2026年7月時点で Nessie は独立プロジェクトとして存続しています**（archived ではなく、リリースも継続）。

**しかし「活発」とは言えません。** 人間のコミットは年間 245 件・実質1人であり、**bus factor は 1 に近い**。「retire された」は誤りですが、「健在」と言うのも過大評価です。**正確には「形式的には存続、実質的には少数保守モード」**です。Dremio の戦略的重心が Polaris にある以上、長期的な先細りリスクは現実的です。

**Iceberg REST 対応**（[guides/iceberg-rest](https://projectnessie.org/guides/iceberg-rest/)）: 実装済みですが**公式に「experimental」と明記**されています。エンドポイントは `/iceberg`、ブランチは URI に `{branch}|{warehouse}` 形式で埋め込みます（例 `http://127.0.0.1:19120/iceberg/experiments|sales`）— **これは REST 仕様の標準的な prefix 用法ではない独自拡張**です。S3 request signing と credential vending（assume role）は両方対応。制約: テーブルの base location は Nessie が強制し、変更は無視されます。

### Lakekeeper

Rust 製で JVM 不要、credential vending が最も充実しています。技術的な出来は良いのですが、**本番マルチテナントには時期尚早**と判断します:

- **pre-1.0（v0.13.1、2026-06-30）**
- **コミット実績が実質2名に集中**（bus factor ≈ 2）
- **公式に名前の出た本番採用事例がゼロ**
- **REST 仕様の準拠バージョンとエンドポイント単位の適合表が、公式 docs にもリポジトリにも存在しない**

### Apache Gravitino

**TLP 卒業（2025-06-03）**、v1.3.0、star 3.1k、**Uber / Pinterest の採用実績**あり。**Kerberos 対応**が特徴で、既存 Hadoop 資産との統合が必要な場合の選択肢になります。

ただし [Iceberg REST service の docs](https://github.com/apache/gravitino/blob/main/docs/iceberg-rest-service.md) が**マルチテーブルトランザクションと view 登録を非対応と明記**しています。

### Hadoop catalog は本番使用不可

Javadoc が「atomic rename を要求」「renameTable は未サポート」と明記し、[dev@ML で Ryan Blue](https://www.mail-archive.com/dev@iceberg.apache.org/msg07006.html) が「**HDFS 以外（ローカルFS、S3、一般的なオブジェクトストア）では安全でない**」として 2.0 での deprecate を提案、概ね合意済みです。

これは [01-architecture.md](01-architecture.md#コミットの実装) で見た仕様側の記述（File System Tables 方式は deprecated、オブジェクトストアでは unsafe、v4 で削除予定）と一致します。**ローカルの単一ライタ検証以外では使わないでください。** 推奨代替は **JDBC catalog** です。

### Apache XTable はカタログの代替ではない

Hudi/Delta/Iceberg 間の**メタデータ変換層**です。CoW/read-optimized のみ対応（Hudi log file・Delta deletion vector は未反映）。

**実測で明確に停滞**しています:

- 最新リリース **0.3.0-incubating = 2025-06-04**（**13ヶ月以上リリースなし**）
- コミット: 直近90日 **10件** / 365日 **42件**（うち6件はボット。人間は36件。Iceberg は人間 1,387件）
- Incubation 入りは 2024-02-11、**2026年7月時点でまだ incubating**（約2年5ヶ月）

ベンダー中立の相互運用を担う唯一のプロジェクトがこの状態である点は、ロックインの観点でリスクとして認識すべきです → [07-ecosystem.md](07-ecosystem.md)

### Snowflake Open Catalog は新規顧客に実質クローズ

公式 docs が明言しています（逐語）:

> Customers who **haven't previously created a Snowflake Open Catalog account can't sign up for their first Open Catalog account**.
>

> **New customers should use Snowflake Horizon Catalog** for Apache Iceberg™ tables and multi-engine interoperability with Iceberg.
>

> **Existing** Snowflake Open Catalog customers who already have at least one Open Catalog account **can continue using Open Catalog and can create additional Open Catalog accounts** if necessary.

**正式な deprecation ではありません**（docs に deprecation/EOL の語はなく、既存顧客の継続利用と追加アカウント作成を明示的に許可）。しかし新規サインアップは**できません**。

> **決着つかず**: 課金について docs は「Open Catalog is currently free to use with general availability. **Billing will begin in the first half of 2026**」と将来形のままです。現在は2026年7月で上半期は既に経過しており、**docs の更新漏れか課金開始の遅延か判別できません**。

### AWS: Glue と S3 Tables は別エンドポイント

AWS は使い分けを案内しています。

- **細粒度ガバナンスが要る** → Glue endpoint（`glue.<region>.amazonaws.com/iceberg`）+ Lake Formation
- **単一バケットの素の読み書き** → S3 Tables ネイティブ（`s3tables.<region>.amazonaws.com/iceberg`）

> **要検証**: S3 Tables ネイティブ側の credential vending は AWS 公式ドキュメントに記述がなく、[re:Post に失敗報告](https://repost.aws/questions/QUhvqWn5ChS9yvhsjhql9xyQ/py-iceberg-in-aws-lambda-gets-403-on-s-3-tables-backing-bucket-glue-iceberg-rest-returns-no-vended-s-3-credentials)もあります。採用前に必ず PoC で検証してください。

S3 Tables の自動メンテナンスには重大な落とし穴があります → [06-operations.md](06-operations.md#c-1-amazon-s3-tables)

---

## ローカル構築のしやすさ（実際の compose ファイルを取得して評価）

**結論: Apache Polaris が最有力。次点で Lakekeeper。**

### 1位: Apache Polaris — 4サービス・自動ブートストラップ・外部DB不要

[公式 quickstart compose](https://github.com/apache/polaris/blob/main/site/content/guides/quickstart/docker-compose.yml) の実内容:

| サービス | イメージ | 役割 |
|---|---|---|
| `polaris` | `apache/polaris:latest` | 本体（8181=API, 8182=管理）。**永続化は in-memory 既定 → Postgres 不要** |
| `rustfs` | `rustfs/rustfs:1.0.0-alpha.81` | S3 互換ストア（9000/9001） |
| `bucket-setup` | `amazon/aws-cli:2.35.21` | バケット作成の使い捨て |
| `polaris-setup` | `alpine/curl:8.21.0` | catalog/principal/role/grant を curl で自動作成 |

```bash
curl -s https://raw.githubusercontent.com/apache/polaris/refs/heads/main/site/content/guides/quickstart/docker-compose.yml \
  | docker compose -p polaris-quickstart -f - up -d
docker compose -p polaris-quickstart logs | grep -i client   # 資格情報を拾う
```

`docker compose up` だけで catalog・principal・role・権限まで自動生成し、最後に **Spark の接続コマンドと発行済み認証情報を丸ごと標準出力に表示**します。公式の注記: 「**This setup is not intended for production use.**」

**決定的な強み**は `site/content/guides/` 配下に用途別 compose が完備されていることです（実測で存在確認）:

```
.it-setup, assets, ceph, cockroachdb, flink, jdbc, keycloak,
minio, ozone, quickstart, rustfs, spark, telemetry, trino
```

**Keycloak を足して OIDC、`jdbc` で Postgres 永続化、Trino/Flink でマルチエンジン**、と段階的にラボを拡張できます。

> **注意点**:
> - `guides/quickstart` は `rustfs:1.0.0-alpha.81`、`guides/rustfs` は `rustfs:1.0.0-beta.8` と**別バージョンを使っています**。
> - `apache/polaris:latest` はタグ固定されておらず、1.6.0 相当かは**未確認**。再現性重視なら固定してください。
> - `getting-started/eclipselink/` は**撤去済み（404）**。永続化ガイドは `jdbc`（PostgreSQL）に置換されました。古い記事の手順は動きません。

**認証の要点**（公式 `assets/polaris/obtain-token.sh` より）:

```bash
TOKEN=$(curl --fail-with-body -s \
  http://polaris:8181/api/catalog/v1/oauth/tokens \
  --user ${CLIENT_ID}:${CLIENT_SECRET} \
  -H "Polaris-Realm: $realm" \
  -d grant_type=client_credentials \
  -d scope=PRINCIPAL_ROLE:ALL | jq -r .access_token)
```

- OAuth2 **client_credentials**、`scope=PRINCIPAL_ROLE:ALL`、realm は `Polaris-Realm` ヘッダ
- ブートストラップ: `POLARIS_BOOTSTRAP_CREDENTIALS: POLARIS,${ROOT_CLIENT_ID:-root},${ROOT_CLIENT_SECRET:-s3cr3t}`（**書式は `realm,clientId,clientSecret`**）
- ※ **`/v1/oauth/tokens` は削除予定**（[03-rest-catalog.md](03-rest-catalog.md#v1oauthtokens-の非推奨) 参照）。Polaris も「already deprecated for removal due to security concerns」とし、外部 IdP を構成した realm では **HTTP 501** を返します。

### 2位: Lakekeeper — Rust で JVM 不要、Trino/StarRocks 同梱

[`examples/minimal/docker-compose.yaml`](https://github.com/lakekeeper/lakekeeper/blob/main/examples/minimal/docker-compose.yaml): `quay.io/lakekeeper/catalog` + Postgres 17 + SeaweedFS + Jupyter/PySpark + Trino 476 + StarRocks。依存は **Postgres + S3 ストアのみ**。Polaris より1歩重い（Postgres 必須）ですが、Trino/StarRocks が最初から入っているのは魅力です。

> compose 既定は `latest-main` タグ = **開発ブランチ追従**で、リリース版 v0.13.1 とは別物です。

### 3位: Project Nessie — 最小構成は圧倒的に軽い

[`docker/in_memory/docker-compose.yml`](https://github.com/projectnessie/nessie/blob/main/docker/in_memory/docker-compose.yml) は **1サービスのみ**。Git-like ブランチを試すだけなら最速です。ただし REST は experimental。

### `apache/iceberg-rest-fixture`

**タグ**（Docker Hub tags API 実測）: `latest`(2026-04-29), `1.10.1`(2025-12-22), `1.10.0`, `1.9.1`, `1.9.0`, `1.8.1`

> `latest`(2026-04-29) がバージョン付き最新 `1.10.1`(2025-12-22) より**新しい** ＝ 中身が一致しない可能性。タグ固定必須。

**「本番非推奨」の正確な扱い** — ここは訂正が必要です。しばしば「公式が本番使用を禁止している」と言われますが、**README を直接確認した限り、そのような明示的な免責文は存在しません（未確認）**。よく引用される「integration tests will delete data…」は **RCK（統合テスト実行）側の警告**であり、fixture イメージへの本番禁止表明とは別物です。

ただし**テスト用途であることを示す状態証拠は強固**です:

- README タイトル「Iceberg REST Catalog Adapter **Test Fixture**」
- ソース配置が `open-api/src/**testFixtures**/java/...`
- **既定がインメモリ SQLite JdbcCatalog**（再起動で全メタデータ消失）
- イメージ名自体が "fixture"

正確な言い方は「公式が本番禁止と明記している」ではなく「**命名・ソース配置・既定値のすべてがテスト用途を示す**」です。

**環境変数の変換規則**（README + `RCKUtils.java` の実装で二重検証）:

```
CATALOG_ 除去 → "__" を "-" へ → 残る "_" を "." へ → 小文字化
```

**順序が本質的**です（`__`→`-` を先に処理するため `CATALOG_IO__IMPL` → `io-impl`。逆順なら `io.impl` になり壊れます）。

| 環境変数 | プロパティ |
|---|---|
| `CATALOG_WAREHOUSE` | `warehouse` |
| `CATALOG_IO__IMPL` | `io-impl` |
| `CATALOG_S3_ENDPOINT` | `s3.endpoint` |
| `CATALOG_S3_PATH__STYLE__ACCESS` | `s3.path-style-access` |

### その他

- **Unity Catalog OSS**: 2サービスで起動は最も手軽ですが、**Iceberg REST が読み取り専用**なのでラボの題材には不適。
- **Apache Gravitino**: compose は別リポジトリ [gravitino-playground](https://github.com/apache/gravitino-playground)。約11サービス、**2 CPU / 8GB RAM / 25GB disk**、起動3〜5分。重い。
- **クラウド系（Glue / S3 Tables / R2）**: R2 と Glue の `/iceberg` エンドポイントにはエミュレータが見つかりません。S3 Tables は LocalStack が対応しますが **Ultimate ティア（有償）**。

---

## 選定指針

### シナリオA: セルフホストで REST カタログを試したい → **Apache Polaris**

quickstart が4サービス・外部DB不要・完全自動ブートストラップで、接続情報まで出力してくれます。TLP 卒業済みで仕様のリファレンス実装的な位置づけであり、**学んだことがそのまま本番知識になります**。用途別 compose ガイドが揃い、段階的にラボを育てられます。

**推奨の進め方**: Polaris quickstart → `guides/jdbc` で永続化 → `guides/keycloak` で OIDC → `guides/trino` でマルチエンジン。

*対抗*: Rust 単一バイナリの軽さと vending の充実を重視するなら Lakekeeper。Git-like ブランチが主目的なら Nessie の in_memory 1サービス。

> 本報告書の検証環境もこの構成を採用しています。

### シナリオB: 本番マルチテナント → **Apache Polaris**

TLP ガバナンス、contributor 156名、catalog role / principal role の2層 RBAC、realm によるマルチテナント分離、Postgres/CockroachDB バックエンド、Helm chart 提供。**ベンダー中立性が最重要ならここ。**

- **Kerberos や既存 Hadoop 資産との統合が必須** → **Gravitino**（Kerberos 対応 + Uber/Pinterest の本番実績 + ASF TLP）。ただし IRC がマルチテーブル tx・view 登録を非対応と明記している点を許容できるか確認を。
- **行・列レベルのガバナンスが必須で AWS 中心** → **Glue + Lake Formation**。細粒度権限はこの中で最強。
- **Lakekeeper は時期尚早**（pre-1.0、bus factor ≈ 2、公表採用事例ゼロ）。リスクを取れるなら選択肢。

### シナリオC: クラウドマネージドで済ませたい

| 状況 | 推奨 | 注意 |
|---|---|---|
| **AWS 完結・運用ゼロ最優先** | **S3 Tables** | 自動 compaction/snapshot 管理が標準 ON なのが最大の価値。ただし **CTAS 不可・view 非対応**を設計前に織り込むこと。さらに[自動メンテナンスの fail-closed 問題](06-operations.md#c-1-amazon-s3-tables)を必ず理解すること |
| **複数エンジン・複数アカウントの統合ガバナンス** | **Glue Iceberg REST + Lake Formation** | 2025-11 のカタログフェデレーションで Polaris/Unity も Glue 配下に束ねられる |
| **OSS Polaris と同じ API のまま管理サービス化** | **Snowflake Horizon Catalog** | **Open Catalog は新規顧客に実質クローズ**。新規は Horizon へ誘導される |
| **Databricks 中心** | **UC 管理版** | Managed Iceberg なら IRC 経由で**読み書き両方 GA**、v3 も GA。ただし **Foreign Iceberg / UniForm 経由は読み取り専用かつ vending 不可**という非対称性に注意 |
| **データ持ち出し料金（エグレス）が支配的な多クラウド** | **R2 Data Catalog**（エグレス無料） | **依然 open beta で GA 未達**、RBAC は token スコープのみ。本番採用は慎重に |

---

## 未確認事項

1. **Lakekeeper の REST 仕様準拠バージョンとエンドポイント単位の適合表** — 公式 docs にもリポジトリにも記載なし。「マルチテーブルコミット含む完全準拠」はブログ由来で未確認。
2. **Lakekeeper の本番採用事例** — 公式情報源にゼロ。
3. **Polaris 1.5 の Generic Table vending 拡張** — Snowflake ブログの記述と公式 docs の「vending 非対応」が食い違う。
4. **S3 Tables ネイティブエンドポイントの vending 有無** — AWS 公式に記述なし、コミュニティでは失敗報告あり。
5. **Glue REST の view / RenameTable 対応** — サポート一覧に無いが、明示的な非対応宣言でもない。
6. **Glue の vending ヘッダ機構**（`X-Iceberg-Access-Delegation`）— AWS 公式ドキュメント上に記述なし。
7. **R2 Data Catalog の view 対応と GA 時期** — 情報なし。
8. **Gravitino の remote signing 対応**（vended credentials のみ文書化）と詳細 RBAC モデル。
9. **Hive Metastore の非推奨化** — **Iceberg 公式に非推奨宣言は存在しません。** 「REST が新規推奨」もセカンダリブログ由来で、Apache Iceberg 公式はカタログの推奨ランキングを公開していません。
10. **Nessie の長期的な将来** — 2024年の Dremio 発言（retire 予定）と2026年の実態（活発に開発中）が矛盾しており、公式の最新見解が見当たりません。
11. **Polaris の TLP 卒業日** — Incubator ページ 2026-02-15 vs 公式ブログ 2026-02-19。
12. **`apache/polaris:latest` の実体バージョン**、および `iceberg-rest-fixture` の `latest` と `1.10.1` の中身の異同。
13. **Nessie の公式 docker compose 例**（`/guides/docker/` は `docker run` のみ）。

---

## 出典

- [Polaris TLP 卒業ブログ（2026-02-19）](https://polaris.apache.org/blog/2026/02/19/apache-polaris-graduates-to-top-level-project/) · [ASF news](https://news.apache.org/foundation/entry/the-apache-software-foundation-graduates-two-open-source-projects-from-incubator) · [Incubator status](https://incubator.apache.org/projects/polaris.html)
- [Polaris quickstart compose](https://github.com/apache/polaris/blob/main/site/content/guides/quickstart/docker-compose.yml) · [Generic Table](https://polaris.apache.org/in-dev/unreleased/generic-table/) · [obtain-token.sh](https://raw.githubusercontent.com/apache/polaris/main/site/content/guides/assets/polaris/obtain-token.sh)
- [Nessie Iceberg REST guide](https://projectnessie.org/guides/iceberg-rest/) · [Nessie/Polaris 公式見解](https://projectnessie.org/blog/2024/08/02/open-source-polaris-announcement/) · [BigDATAwire（retire 報道）](https://hpcwire.com/bigdatawire/2024/07/30/polaris-catalog-to-be-merged-with-nessie-now-available-on-github/)
- [Lakekeeper compose](https://github.com/lakekeeper/lakekeeper/blob/main/examples/minimal/docker-compose.yaml) · [Lakekeeper storage docs](https://docs.lakekeeper.io/docs/nightly/storage/)
- [Gravitino TLP](https://gravitino.apache.org/blog/gravitino-top-level-project/) · [Gravitino Iceberg REST](https://github.com/apache/gravitino/blob/main/docs/iceberg-rest-service.md) · [gravitino-playground](https://github.com/apache/gravitino-playground)
- [UC UniForm](https://docs.unitycatalog.io/usage/tables/uniform/) · [Databricks Iceberg 外部アクセス](https://docs.databricks.com/aws/en/external-access/iceberg)
- [Glue Iceberg REST](https://docs.aws.amazon.com/glue/latest/dg/connect-glu-iceberg-rest.html) · [Glue REST API 仕様](https://docs.aws.amazon.com/glue/latest/dg/iceberg-rest-apis.html)
- [S3 Tables OSS 連携](https://docs.aws.amazon.com/AmazonS3/latest/userguide/s3-tables-integrating-open-source.html)
- [R2 Data Catalog](https://developers.cloudflare.com/r2/data-catalog/) · [Snowflake Open Catalog overview](https://docs.snowflake.com/en/user-guide/opencatalog/overview)
- [XTable incubator status](https://incubator.apache.org/projects/xtable.html)
- [HadoopCatalog javadoc](https://iceberg.apache.org/javadoc/nightly/org/apache/iceberg/hadoop/HadoopCatalog.html) · [dev@ deprecation スレッド](https://www.mail-archive.com/dev@iceberg.apache.org/msg07006.html)
- [iceberg-rest-fixture tags API](https://hub.docker.com/v2/repositories/apache/iceberg-rest-fixture/tags?page_size=50) · [RCKUtils.java](https://raw.githubusercontent.com/apache/iceberg/main/open-api/src/testFixtures/java/org/apache/iceberg/rest/RCKUtils.java)
