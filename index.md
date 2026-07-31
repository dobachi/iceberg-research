# Apache Iceberg 調査報告書


::: {.callout-warning}
## この文書の位置づけ


:::

> **これは著者による個人的な調査メモ（手記）であり、本番環境での利用を想定して書かれたものではありません。**
>

> - 特定時点（2026年7月）のスナップショットであり、**内容は急速に陳腐化します**
> - 網羅性を保証するものではなく、著者の関心に沿って調べた範囲に限られます
> - **本番システムの設計・構築の根拠として、そのまま用いないでください。** 判断に使う数値・バージョン・仕様は、必ず引用元の一次情報で確認してください
> - 記述の誤りによって生じた結果について、著者は責任を負いません
>

> 技術的な議論のたたき台や、調べ始める際の地図として使っていただくことを想定しています。

Apache Iceberg と Iceberg REST Catalog について、**一次情報の裏取りを前提に**調べた記録です。仕様やエコシステムの現況を把握するための地図として書いています。

**Version: 2026-07-18** / 調査基準日: 2026-07-17 / 対象: Apache Iceberg 1.11.0（2026-05-19 リリース）

> Version はこのページを更新した日付、調査基準日は内容を調べた時点です。Iceberg 周辺は変化が速いため、**調査基準日から離れるほど内容は古くなります**。

本報告書の主張の一部は、Apache Polaris と PyIceberg を用いた実環境で検証しています。検証環境と実験の記録は姉妹リポジトリ [**Iceberg REST Lab**](https://dobachi.github.io/iceberg-rest-lab/) に公開しています。

::: {.content-visible when-format="html"}
全文をまとめた [**PDF 版**](/iceberg-research.pdf) もあります（本編＋付録の一冊もの）。
:::

---

## 目次

| # | ドキュメント | 内容 |
|---|---|---|
| 01 | [アーキテクチャと中核概念](docs/01-architecture.md) | 三層メタデータ構造、スナップショット、楽観的並行制御、クエリプランニング |
| 02 | [テーブル仕様 v1/v2/v3](docs/02-table-spec.md) | 各バージョンの差分、スキーマ/パーティション進化、CoW/MoR、deletion vector、row lineage、**v4 の現況** |
| 03 | [REST Catalog 仕様](docs/03-rest-catalog.md) | エンドポイント、コミットプロトコル、認証、credential vending、server-side scan planning |
| 04 | [カタログ実装の比較](docs/04-catalog-implementations.md) | Polaris / Nessie / Lakekeeper / Gravitino / Glue / S3 Tables / Unity Catalog ほか、選定指針 |
| 05 | [エンジン対応状況](docs/05-engine-support.md) | Spark / Flink / Trino / Presto / Snowflake / Databricks / Dremio ほかの対応マトリクス |
| 06 | [運用・メンテナンス・性能](docs/06-operations.md) | 必須メンテナンス、テーブルプロパティ、アンチパターン、性能劣化の機序 |
| 07 | [エコシステムと業界動向](docs/07-ecosystem.md) | Delta / Hudi / Paimon 比較、「標準になったのか」の検証、**使うべきでない場面** |
| 08 | [選定ガイド](docs/08-decision-guide.md) | **要求から技術選択への決定チャート**（フォーマット→カタログ→エンジンの3段階） |
| 90 | [用語集](docs/90-glossary.md) | 本報告書で使う用語の一覧（**各項目に出典を明記**） |
| 99 | [調査方法論と未確認事項](docs/99-methodology.md) | 証跡の扱い方、踏んだ罠、未確認事項の一覧 |

---

## 先に知っておくと良い結論

報告書全体から、実務判断に効く事実を抜き出したものです。詳細は各ドキュメントを参照してください。

### 仕様

- **v4 は仕様として未採択ですが、Java 実装ではすでに v4 テーブルを作れます。** ここは取り違えやすく、取り違えると判断を誤ります。仕様本文は「Version 4 is under active development and **has not been formally adopted**」と明記していますが、**Iceberg Java は 1.10.0（2025-09-11）以降 `format-version=4` を設定できます**（`SUPPORTED_TABLE_FORMAT_VERSION = 4`）。一方 **PyIceberg 0.11.1 は受け付けません**（`TableVersion = Literal[1, 2, 3]`）。既定値はいずれも 2。→ [02](docs/02-table-spec.md#v4-metadata-structure-and-representation--未採択ただし実装は先行している)

- **デフォルトは今も v2 + copy-on-write。** `format-version` の既定値は 2、`write.{delete,update,merge}.mode` の既定値は `copy-on-write` です。v3 の恩恵（deletion vector 等）は明示的なオプトインなしには得られません。→ [02](docs/02-table-spec.md)

- **v3 の「GA」は Apache の宣言ではありません。** Apache 側の公式ステータスは「complete and adopted by the community」までで、「GA」はベンダー用語です。→ [02](docs/02-table-spec.md#v3-の策定リリース状況)

### エンジン

- **v3 対応はベンダーごとにバラバラです。** Snowflake GA（2026-05-07）、Databricks GA（2026-05-28）、**Dremio は今も Preview**。Trino は**公式 docs 上まだ experimental**（PR はマージ済みだが「マージ済み ≠ リリース済み ≠ サポート対象」）。→ [05](docs/05-engine-support.md)

- **PyIceberg は v3 テーブルを書けません。** 読めますが書けません。equality delete は**読むこともできません**。merge-on-read を指定しても警告を出して copy-on-write に落ちます。→ [05](docs/05-engine-support.md#pyiceberg)

### 運用

- **公式は compaction を "Optional"、`expire_snapshots` と metadata 掃除を "Recommended" に分類しています。** 一般的な認識と逆です。しかも **`expire_snapshots` を回さない限り compaction は容量を一切解放しません**（むしろ増えます）。→ [06](docs/06-operations.md#公式の分類-recommended-と-optional)

- **`write.metadata.delete-after-commit.enabled` はテーブル作成時に決めるべき設定です。** 既定は false で、`previous-versions-max`（既定100）を溢れた metadata JSON は追跡対象から外れ、**後から有効化しても救済できません**。→ [06](docs/06-operations.md#5-メタデータ-json-肥大)

- **S3 Tables はタグやブランチを1つ作るだけで自動スナップショット管理がテーブル全体で停止します**（fail-closed）。`history.expire.*` の設定でも同様。しかも失敗は課金増加としてしか現れません。→ [06](docs/06-operations.md#c-1-amazon-s3-tables)

### エコシステム

- **「Iceberg がデファクト標準になった」は不正確です。** カタログの相互接続層としては REST Catalog 仕様が共通語になりつつある一方、フォーマット単体では決着していません（Fabric のネイティブは Delta、Confluent/Fivetran は両対応、Paimon の開発速度は Iceberg の1.63倍〔人間コミット換算〕、DuckLake v1.0 が2026年4月に登場）。→ [07](docs/07-ecosystem.md#b-iceberg-は事実上の標準になったのか)

- **Databricks が Delta 5.0 に Iceberg v4 のメタデータ構造を採用する提案を出しています。** 実現すれば「勝敗」ではなく統合になります。ただし Delta 5.0 も Iceberg v4 も未リリースです。→ [07](docs/07-ecosystem.md)

---

## 本報告書の証跡方針

> **この報告書は人間と AI の共同作業で作成しています。** 調査・執筆・検証を人間と AI が分担しており、**人間が書いた部分と AI が書いた部分が混在しています。** 正確性を高めるため一次情報での裏取りと公開前のファクトチェックを行い、その過程で見つかった誤りは修正しましたが（[fact-check-report.md](fact-check-report.md) に記録）、**すべての主張を検証したわけではなく、誤りが残っている可能性があります。** 重要な判断に使う数値・バージョン・仕様の記述は、引用元の一次情報で再確認してください。

誤りを減らすため、**同じ問いを複数回・独立に調べ、結果が食い違った点は改めて一次情報に当たって決着させています**。方針は以下の通りです。

1. **一次情報に直接あたって確認する。** 記憶や推測でバージョン番号・プロパティ名・API シグネチャを書きません。
2. **優先順位を固定する。** 公式ドキュメント > リポジトリの実ファイル/ソースコード > 公式ブログ・プレスリリース > 技術ブログ。矛盾したら上位を採用し、**矛盾の存在自体を記録します**。
3. **「未確認」と「非対応」を区別する。** 「ソースが見つからなかった」と「公式が非対応と明記している」は全く別の事実です。本文中でも区別しています。
4. **「マージ済み ≠ リリース済み ≠ サポート対象」を区別する。**
5. **出典 URL を付ける。** 日付が判明するものは日付も添えます。

調査中に判明した具体的な罠（リリースノートは遡及更新されない、プレスリリースと docs が食い違う、など）は [99-methodology.md](docs/99-methodology.md) に方法論としてまとめています。**この報告書を更新する人、および同種の調査を行う人はそちらを先に読むことを勧めます。**

### 実機で検証した範囲

**Apache Polaris 1.6.0 + PyIceberg 0.11.1 の実環境に対して、以下を実際に確認済み**です。

| 主張 | 検証結果 |
|---|---|
| 新規テーブルの既定は format-version=2 | ○ 実測で 2 |
| `write.delete.mode` の既定は copy-on-write | ○ 実測で copy-on-write |
| PyIceberg は V3 を書けない | ○ `NotImplementedError` を確認 |
| MoR 指定は警告を出して CoW に落ちる | ○ `Merge on read is not yet supported, falling back to copy-on-write` を捕捉 |
| `MaintenanceTable` は `expire_snapshots` のみ | ○ compaction / orphan 削除の不在を確認 |
| `s3.path-style-access` は PyIceberg に存在しない | ○ 定数の不在を確認 |
| rename しても field ID は変わらない | ○ 実測で一致 |
| credential vending の prefix スコープ | ○ テーブル単位の短命資格情報が払い出されることを確認 |
| 409 CommitFailedException とそのメッセージ | ○ 意図的に再現 |
| サーバが `overrides` で `prefix` を配る | ○ `prefix = lab_catalog` を確認 |
| `namespace-separator` の既定は `0x1F` | ○ `%1F` を確認 |

### 既知の限界

- **調査基準日時点のスナップショットです。** Iceberg 周辺は変化が速く、特にベンダーの対応状況は数ヶ月で変わります。バージョン番号や GA/Preview の別を引用する際は再確認してください。
- **実機検証は上記の範囲に限られます。** それ以外はドキュメントとソースコードの読解に基づきます。特に **Spark / Flink / Trino / Snowflake / Databricks / Dremio の対応状況は未検証**で、各社のドキュメントの読解に依拠しています。
- **未確認事項が残っています。** [99-methodology.md](docs/99-methodology.md#d-未確認事項の一覧) に一覧化しています。

---

## ライセンス

本報告書は [CC BY 4.0](LICENSE) のもとで公開します。引用元の各プロジェクト・製品のドキュメントの権利は、それぞれの権利者に帰属します。
