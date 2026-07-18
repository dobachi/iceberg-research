# 05. エンジン対応状況

**調査基準日: 2026-07-17** / **Iceberg 1.11.0（2026-05-19）基準**

## 読み方（重要）

本ドキュメントは判定を**3値**で区別します。この区別こそが本調査の価値の中心です。

| 記号 | 意味 |
|---|---|
| **【確認】** | 公式ソースで対応と確認 |
| **【明示的非対応】** | **公式ソースが非対応と明記** |
| **【未確認】** | **ソースが見つからなかった。「非対応」ではない** |

さらに「**マージ済み ≠ リリース済み ≠ サポート対象**」を厳密に区別します。この罠は Trino・Presto・Spark で繰り返し現れました。

---

## サマリ表

| エンジン | 読み | 書き | REST catalog | format v3 |
|---|---|---|---|---|
| **Spark** | GA | GA（MERGE/UPDATE/DELETE、パーティション/スキーマ進化） | クライアント GA | 最も進んでいるが**サブ機能ごとに差**（下記） |
| **Flink** | GA | GA だが **INSERT/UPSERT のみ。MERGE/UPDATE/DELETE の SQL なし** | クライアント GA | 部分的 |
| **Trino 482** | GA（v1/v2） | GA（MERGE あり） | クライアント GA | **experimental**（docs 明記） |
| **Presto 0.298.1** | GA（v1/v2） | GA だが **MERGE 非対応**（Java）、**C++ は INSERT のみ** | クライアント GA | 部分的、大半がトランク上で未リリース |
| **PyIceberg 0.11.1** | GA | GA だが**制約が重い**（下記） | クライアント GA | **読めるが書けない** |
| **Snowflake** | GA | GA | **サーバ + クライアント** | **GA**（2026-05-07） |
| **Databricks** | GA | GA（**managed のみ**） | **サーバ + クライアント** | **GA**（2026-05-28） |
| **Dremio** | GA | GA（フル DML） | **サーバ + クライアント**（Polaris ベース） | **Preview** |
| **StarRocks 4.0.1** | GA | **INSERT 系のみ。DELETE/UPDATE/MERGE なし** | クライアント | **なし**（tracker #63819 未アサイン） |
| **Doris 4.1.1** | GA（**v3 読みは 4.1.0〜**） | INSERT/CTAS は GA、**UPDATE/DELETE/MERGE は experimental** | クライアント（3.1.0〜） | 部分的/preview |
| **Impala 4.5.0** | GA（v1/v2） | INSERT/DELETE/UPDATE/MERGE（**position delete のみ、Parquet のみ、MoR のみ**） | **未リリース**（5.0 目標） | **なし** |
| **Hive 4.2.0** | GA | GA（フル DML、Tez 必須） | **クライアント + サーバ**（HMS REST Catalog、4.2.0） | 部分的/preview（**row lineage は既知のギャップ**） |
| **DuckDB** | GA | 1.4〜（CREATE/INSERT/COPY） | クライアント | 未確認 |
| **ClickHouse** | GA（catalog 経路は experimental） | **experimental・フラグ制**（INSERT/CREATE のみ） | クライアント（experimental） | 未確認 |
| **BigQuery** | GA | GA（managed）／**BigLake external は読み取り専用** | BigLake Metastore（IRC）**GA** | 未確認 |
| **Athena** | GA | GA（MERGE、OPTIMIZE、VACUUM） | Glue 経由 | DV + row lineage（2025-11 発表） |
| **Redshift** | GA（Spectrum/Glue/S3 Tables） | **未確認**（AWS docs に肯定も否定もなし） | Glue/S3 Tables 経由 | 未確認 |

---

## ベンダー3社の v3 対応 — 食い違いを一次情報で決着

先行の調査結果の間で主張が食い違ったため、改めて一次情報で検証しました。**結果として、食い違いの大半は「時系列の異なる時点を切り取った」ことによるもの**でした。

### Databricks — 【確定】**GA**

**両方の主張が正しく、見ていた時点が違っただけ**でした。

| 日付 | 出来事 |
|---|---|
| **2026-04-09** | [Public Preview 発表](https://www.databricks.com/blog/next-era-open-lakehouse-apache-icebergtm-v3-public-preview-databricks) — 「Today, Databricks's support of Iceberg v3 enters **Public Preview**」 |
| **2026-05-28** | [**GA 発表**](https://www.databricks.com/blog/unity-catalog-and-next-era-apache-icebergtm) — 「**Iceberg v3 (GA)**: Native support for deletion vectors, row tracking, and the new VARIANT type across managed, foreign, and UniForm-enabled tables.」 |
| **2026-06-17** | docs 最終更新。**Preview/Beta バナーなし**（Databricks は Preview 機能に明示ラベルを付ける慣習があり、その不在は GA と整合） |

**サブ機能**:
- 対応: deletion vectors / VARIANT / row lineage
- **【明示的非対応】**: 「Defaults, including write defaults and initial defaults, aren't supported」、**unknown 型**、**ナノ秒精度 timestamp**、**multi-argument transforms**

**書き込みの非対称性**（重要）:
- **Managed Iceberg のみ書き込み可**（外部エンジン Spark/Flink/Trino/Kafka からも可）
- **Foreign Iceberg は Databricks 内で読み取り専用**、**credential vending 非対応**、手動 `REFRESH FOREIGN TABLE` が必要
- **パーティション進化は外部エンジン経由でのみ GA。Databricks SQL 経由では非対応**
- **v2 の position/equality delete は非対応**（v3 の DV は対応）— 注目すべき相互運用ギャップ

> **未解決の食い違い**: foreign Iceberg の credential vending は 2026-05-28 のブログが GA と述べる一方、REST API docs ページは非対応としています。docs の遅れの可能性がありますが未解決です。

### Snowflake — 【確定】**GA**、外部エンジンからの v3 書き込みも**対応済み**

**リリースノートと現行 docs の「矛盾」は、矛盾ではなく時系列でした。**

| 日付 | 出来事 |
|---|---|
| 2026-02-06 | 外部エンジンからの **read** が GA |
| 2026-03-04 | [Iceberg v3 サポート **Preview**](https://docs.snowflake.com/en/release-notes/2026/other/2026-03-04-iceberg-v3-support-preview) |
| 2026-03-16 | 外部エンジンからの **write** が Preview |
| **2026-05-07** | [**v3 が GA**](https://docs.snowflake.com/en/release-notes/2026/other/2026-05-07-iceberg-v3-ga) — 「Writes from external engines to Snowflake-managed Iceberg v3 tables through Horizon Catalog **aren't supported yet**」← **この時点では write 自体がまだ Preview だったので正しい記述** |
| **2026-05-26** | [**外部エンジン write が GA**](https://docs.snowflake.com/en/release-notes/2026/other/2026-05-26-tables-iceberg-query-using-external-query-engine-snowflake-horizon-writes-ga) — 「read and write to Snowflake-managed Iceberg **v2 and v3** tables」← **ここで v3 制約が解消** |

現行 docs（最終根拠）:
> You can **read and write** to Snowflake-managed Iceberg **v2 and v3** tables from external engines through the Horizon Iceberg REST Catalog API

> **教訓**: **Snowflake のリリースノートを現況の根拠に使わないこと。** 仕様上、後から更新されることはなく、その時点の記述がそのまま残り続けます。→ [99-methodology.md](99-methodology.md)

**IRC**: サーバ（Horizon Catalog、`https://<account>.snowflakecomputing.com/polaris/api/catalog`）とクライアントの**両方向 GA**。ただしサーバ側が公開するのは **Snowflake-managed Iceberg テーブルのみ**です。

**【明示的非対応】**: nested VARIANT、multi-arg transforms、table encryption keys、UNKNOWN 型、**in-place の v2→v3 アップグレード**、externally-managed v3 での append-only stream

**新規 managed テーブルの既定は依然 v2**（v3 はオプトイン）。

### Dremio — 【確定】**Preview**

**ここだけ本当の誤りがありました。** プレスリリースの表現を採った調査結果が、docs と突き合わせられていませんでした。

| ソース | 主張 |
|---|---|
| [プレスリリース（2026-04-06）](https://www.dremio.com/press-releases/dremio-deepens-apache-iceberg-leadership-with-v3-support-new-community-appointments-and-polaris-momentum/) | 副題で「ships the latest V3 spec **at GA**」、本文「V3 support is **now available in Dremio Cloud**」「full read and write support」 |
| [**docs（現時点）**](https://docs.dremio.com/dremio-cloud/developer/data-formats/iceberg/) | 見出しに **"Iceberg v3 Preview"** と明記。「Although **v2 remains the default format version in Dremio**…」 |

**docs 優先ルールにより Preview を採用します。**

**Cloud と Software の差**: Software（current/26.x）側の docs には **v3 の記述が一切ありません**。プレスリリースも Cloud に限定。→ **v3 は Cloud のみ（Preview）、Software は未提供/未文書化**。

**IRC**: 両方向 GA。Dremio 自身のカタログは **Apache Polaris ベース**で、`{DREMIO_ADDRESS}:8181/api/catalog` に IRC エンドポイントを公開します。

---

## Apache Spark

### サポート対象バージョン（Iceberg 1.11.0）

| Spark | 状態 | 初回サポート | 最終サポート |
|---|---|---|---|
| 3.4 | **End of Life** | 1.3.0 | **1.11.0（最後）** |
| 3.5 | Maintained | 1.4.0 | 1.11.0 |
| 4.0 | Maintained | 1.10.0 | 1.11.0 |
| 4.1 | Maintained | **1.11.0** | 1.11.0 |

### v3 サブ機能ごとの対応

| サブ機能 | 判定 | 根拠 |
|---|---|---|
| **DV 書き込み** | **【確認】** 1.8.0〜 | PR #11561 "Spark: Write DVs for V3 MoR tables"（2024-12-06 merged） |
| **DV 読み取り** | **【確認】** 1.8.0〜 | Core #11481。Spark 側は #11657、1.9.0 で「Rewrite V2 deletes to V3 DVs」(#12250) |
| **DV の v3 デフォルト挙動** | **【確認】** | **`write.delete.mode` の既定は `copy-on-write`。v3 でも DV は自動では使われず、MoR を明示選択した場合のみ** |
| **row lineage 読み取り** | **【確認】** 1.9.0〜 | #12836（`_row_id` / `_last_updated_sequence_number` readers） |
| **row lineage 生成（通常書き込み）** | **【確認】** 1.10.0〜 | #13310 "Spark 4.0: Row Lineage support"。**Spark 3.5 と 4.0/4.1 で実装方式が異なる**（3.5 は Scala rule `RewriteOperationForRowLineage.scala`、4.0/4.1 は `ExtractRowLineage.java`） |
| **row lineage の compaction 保存** | **【確認】** 1.10.0〜 | #13555。ただし PR タイトルが **"Spark 4.0" 限定**。**3.5 での保存は未確認** |
| **VARIANT 読み取り** | **【確認】** 1.10.0〜 | #13219。型表は `variant \| variant \| Spark 4.0+` |
| **VARIANT shredding 書き込み** | **【確認】** 1.11.0〜、**Spark 4.1 のみ** | #14297。変更ファイルは **`spark/v4.1/` のみ**。型表の「Spark 4.0+」とは食い違うので注意 |
| **default values 読み取り適用** | **【確認】** 1.8.0〜 | #11803 |
| **default values 書き込み/DDL 設定** | **【明示的非対応】** | 下記 |
| **geometry / geography** | **【明示的非対応】（1.11.0）** / **1.12.0 でマージ済み・未リリース** | 下記 |
| **nanosecond timestamps** | **【明示的非対応】** | 型表が `Not supported`。コードも `TIMESTAMP_NANO` の case が無く `UnsupportedOperationException` に落ちる |
| **multi-argument transforms** | **【明示的非対応】** | `Spark3Util.java`: `checkArgument("zorder".equals(transform.name()) \|\| transform.references().length == 1, "Cannot convert transform with more than one column reference: %s")` — **zorder 以外の複数カラム参照を明示的に拒否** |

### 罠1: default values は「サポート追加」に見えて書けない

1.11.0 のリリースノートに「Add schema conversion support for default values (#14407)」とあります。しかし:

- 実タイトルは **"Spark 4.0: Add schema conversion support for default values"**、変更は `TypeToSparkType.java` のみ = **スキーマ変換だけ**
- 1.11.0 タグの `Spark3Util.java` に以下が**実在**します:
  ```java
  throw new UnsupportedOperationException(
      "Cannot add column %s since setting default values in Spark is currently unsupported");
  ```
- 1.10.0 に「Throw unsupported exception for ADD COLUMN with default value (#13464)」

→ **リリースノートの文言だけを読むと誤読を招きます。DDL での default 設定は依然として不可です。**

### 罠2: geometry/geography はマージ済みだが使えない

- 1.11.0 タグの `spark-getting-started.md`: `geometry | | Not supported`
- 一方 `main` の `spark/v4.1/.../TypeToSparkType.java` は `case GEOMETRY:` を持つ
- PR **#17073** "Spark 4.1: Read and write geometry and geography values in Parquet"、merged **2026-07-08**、**milestone: Iceberg 1.12.0**

→ **マージ済みだが未リリース。今日時点で使えません。**「マージ済み ≠ リリース済み」の典型例です。

### 発見: Spark の公式 docs が v3 に追いついていない

| 箇所 | 問題 |
|---|---|
| **`spark-writes.md`** | **1.11.0 タグでも DV / row lineage / variant / format-version の言及が 0 件。** Spark の主要書き込みドキュメントが v3 に完全に追いついていない |
| `spark-ddl.md` | default values への言及なし（実際は非対応なのに、その旨の記載もない）。transform 一覧は単一引数のみ |
| `spark-queries.md` | `_row_id` / `_last_updated_sequence_number` メタデータカラムの記載なし（1.9.0 で reader 実装済みなのに） |

**v3 の実装状況はリリースノート・PR・ソースコードのレベルでは十分に追跡可能ですが、ユーザー向け docs はほぼ v2 のまま放置されています。** これ自体が本調査の発見の一つです。

---

## Apache Flink

### サポート対象バージョン（Iceberg 1.11.0）

| Flink | 状態 | 初回 | 最終 |
|---|---|---|---|
| 1.19 | **End of Life** | 1.6.0 | 1.10.2 |
| 1.20 | Maintained | 1.7.0 | 1.11.0 |
| 2.0 | Maintained | 1.10.0 | 1.11.0 |
| 2.1 | Maintained | **1.11.0** | 1.11.0 |

### 書き込みは Spark より狭い

**INSERT INTO / INSERT OVERWRITE / UPSERT のみ。MERGE / UPDATE / DELETE の SQL はありません。**

UPSERT は equality delete ベース（`write.upsert.enabled`、v2+）。exactly-once はチェックポイントで担保。`DynamicIcebergSink` は 1.11.0 時点で **experimental**。

### v3 サブ機能

| サブ機能 | 判定 | 根拠 |
|---|---|---|
| **DV 書き込み** | **【確認】** 1.11.0〜、**Flink 2.1** | #14197。変更ファイルは `flink/v2.1/.../sink/` |
| **DV（equality delete 変換）** | **【確認】** | `flink-writes.md`: 「`convertEqualityDeletes()` converts equality deletes to deletion vectors (**requires equality fields and table format version >= 3**)」 |
| **DV 読み取り** | **【未確認】** | Flink 固有の DV 読み取りを述べる公式ソースなし。Core #11481 経由で機能する可能性が高いが**Flink レベルの証跡なし** |
| **row lineage 読み取り** | **【確認】** 1.11.0〜 | #14148 |
| **row lineage の compaction 保存** | **【確認】** 1.11.0〜 | #14149 "Preserve row lineage in RewriteDataFiles" |
| **row lineage 生成（通常書き込み）** | **【未確認】** | Flink sink が生成すると述べる公式ソースなし |
| **VARIANT** | **公式ソース同士が矛盾** | 下記 |
| **default values 読み取り適用** | **【確認】** 1.8.0〜 | #12072。`defaultReader()` が `field.initialDefault()` を参照 |
| **default values 書き込み/DDL** | **【未確認】** | |
| **geometry / geography** | **【明示的非対応】** | 型表が `Not supported`。GitHub code search `GeometryType path:flink` → **0件**（Spark は8件）。1.12.0 向け PR も見つからず |
| **nanosecond timestamps** | **【確認】** 1.9.0〜（1.11.0 強化） | 型表が `timestamp(9)` / `timestamp_ltz(9)`（Note 欄空＝対応）。#12470、#15475 |
| **multi-argument transforms** | **【未確認】** | |

### VARIANT — 公式ソース同士の矛盾

| ソース | 主張 |
|---|---|
| `flink.md` 型表（**1.11.0 タグ・main 双方**） | `variant \| \| Not supported` |
| 1.11.0 リリースノート | 「Support Variant to Flink 2.1 (#15265)」（2026-02-26 merged） |
| 1.11.0 タグの実コード | `flink/v2.1/.../TypeToFlinkType.java` に variant 参照 **3件を実測**。テストも存在 |

→ **実装は Flink 2.1 に入っており、型対応表が未更新（ドキュメントの遅れ）と判断します。** ただし型表という公式ソースが「Not supported」と書いている事実は残ります。

### v3 アップグレード時の制約

`flink-writes.md`（**【確認】**）:
> **Table Format Version upgrade**: Dynamic sink does not support upgrading a table with dynamic records. **The job should not be running while the V2 to V3 upgrade is in progress.**

### ナノ秒 timestamp の非対称

**Flink は対応、Spark は非対応**という非対称があります。Spark はコード上も `UnsupportedOperationException` に落ちます。

### Flink docs の不整合

- `flink-ddl.md` の `format-version` の例が**すべて `'2'`**。v3 テーブル作成例なし
- `flink-writes.md` の UPSERT 節は「The table must use **v2 table format**」と v2 前提のまま。**同ファイル内で DV（v3以上）に言及しているのに未整合**

---

## Trino（482、2026-06-25）

### v3 は experimental — ブログを信じないこと

**docs（master、`connector/iceberg.md`）が明記**:

> **Support for format version 3 is experimental.**

> **Version 3 support is experimental; row-level updates, deletes, and OPTIMIZE are not supported.** Tables with v3 features such as **column default values and encryption are not supported**. Version 3 is required for tables containing VARIANT columns.

一方、v3 の PR は**すべてマージ済み**です（API で `merged_at` を検証）:

| PR | 内容 | merged |
|---|---|---|
| #27786 | v3 read 有効化 | 2026-01-10 |
| #27837 | column default values | 2026-01-16 |
| #27788 | deletion vector | 2026-01-16 |
| #27836 | row lineage | 2026-03-19 |
| #27753 | VARIANT | 2026-03-30 |
| #27893 | geometry/geography | 2026-06-03 |

**コードは landed しているが、docs は今も v3 を experimental とし、row-level updates/deletes/OPTIMIZE を非対応と宣言し、default values も #27837 がマージされている**にもかかわらず非対応としています。

→ **マージ済み PR のリストを「サポート済み」と読まないこと。docs が authoritative です。**

v1/v2 の読み書きは GA（MERGE、パーティション進化、スキーマ進化あり）。`format_version` の既定は 2。REST カタログはクライアントとして GA（`iceberg.catalog.type=rest`）。482 で prefixed-path storage credentials と view の `location` を追加。

> **注意**: 482 の「data loss … when deletion vectors are enabled」という注記は **Delta Lake コネクタの DV** を指す可能性があり、Iceberg の証拠として引用すべきではありません（未解決）。

---

## Presto（PrestoDB 0.298.1、2026-06-17）— Trino とは別物

**Trino と混同しないこと。** 機能差が実在します。

- **読み**: GA。docs は v1/v2 に限定（「SELECT table operations are supported for Iceberg format version 1 and version 2」）
- **書き**: v1/v2 で GA だが **MERGE は "No"（Presto Java）**。`format-version` は「either 1 or 2」で **v3 は legal な値ですらない**
- **Presto C++ は INSERT のみ**（DML なし）、Presto Java はフル DML
- **row lineage は読み取り専用**

**v3**: 部分的で、大半が未リリース。docs が認めるのは **default column values のみ**（metadata-only、`initial-default` を読み取り時に注入）。残りは [prestodb/presto#27198](https://github.com/prestodb/presto/issues/27198)（**Open**、2026-06-23 更新）で進行中:
- **M1（2026年6月）**: API を 1.10.0 へ、DV **read**（Velox マージ済み、Prestissimo 保留）、default-value read マージ済み
- **M2（目標 2026年9月）**: multi-arg transforms、**VARIANT read**、UNKNOWN 型、ナノ秒 timestamp → **VARIANT は今日の Presto では使えません**

トランクにはマージ済みだが**どのリリースにも入っていない**もの: #28058/#27943（DV + UPDATE/MERGE、2026-06-30/06-24）、#28116（field-id プロトコル + Velox bridge、2026-07-08）、#27197（native row lineage read、2026-07-02）

---

## PyIceberg

**最新: 0.11.1（2026-03-03）**（PyPI の `upload_time_iso_8601` で実測）

| Version | Upload (UTC) |
|---|---|
| **0.11.1** | **2026-03-03** |
| 0.11.0 | 2026-02-10 |
| 0.10.0 | 2025-09-11 |
| 0.9.1 | 2025-04-30 |

`requires_python`: `<4.0.0,>=3.10.0`

### 0.11.0 の主要変更

- **ORC read サポート**
- **Sort order evolution**
- **REST scan planning**（サーバサイド scan planning、**同期のみ**。async は将来）
- **ConfigResponse の supported endpoints ネゴシエーション**（未対応操作で明快なエラー）
- スナップショットのロールバック、Entra ID auth manager
- **Breaking**: **Python 3.9 サポート打ち切り**

### 制約 — ここが重要（released 0.11.1 のソースを直接読んで確定）

**PyIceberg のドキュメントサイトにはバージョンセレクタがなく、`main` 追従の疑いがあります。** そのため以下はリリースタグ `pyiceberg-0.11.1` のソースを直接参照して照合した結果です。

#### 1. format-version 3 は読めるが書けない 【明示的非対応】

```python
# table/metadata.py TableMetadataV3.model_dump_json
raise NotImplementedError("Writing V3 is not yet supported, see: https://github.com/apache/iceberg-python/issues/1551")
```

- `TableMetadataV3` は**実在**し、`format_version: Literal[3]`、`next_row_id` を持つ。**パース（読み取り）は可能**
- しかし**書き込みは明示的に禁止**
- 追跡 issue [apache/iceberg-python#1551](https://github.com/apache/iceberg-python/issues/1551) は **2026-07-17 時点で Open**（マイルストーン/紐付け PR なし）
- `TableProperties.DEFAULT_FORMAT_VERSION = 2`

→ **deletion vector / row lineage といった v3 機能は利用不可。v3 前提の設計は不可能です。**

#### 2. equality delete は書けないだけでなく**読めない** 【明示的非対応】

```python
# table/__init__.py L2114
raise ValueError("PyIceberg does not yet support equality deletes: https://github.com/apache/iceberg/issues/6568")
# L1886 (REST scan planning 経路)
raise NotImplementedError(f"PyIceberg does not yet support equality deletes: {delete_file.file_path}")
```

**Spark や Flink が equality delete を書いたテーブルは PyIceberg で開けません。** 「書けない」だけでない点が重要です。Flink の UPSERT は equality delete ベースなので、この組み合わせは実害が出ます。

#### 3. merge-on-read は警告を出して copy-on-write に落ちる 【明示的非対応】

```python
# table/__init__.py L686
warnings.warn("Merge on read is not yet supported, falling back to copy-on-write", stacklevel=2)
```

テーブルプロパティ `write.delete.mode=merge-on-read` を設定していても**警告を出して CoW で実行**します。position delete の書き出しは行われません。

#### 4. compaction / orphan files 削除は非対応

`pyiceberg/table/maintenance.py` の `MaintenanceTable` は **`expire_snapshots` のみ**。他のメソッドは存在しません。

#### 5. MERGE INTO 相当はない

`upsert()` が近いですが SQL の MERGE INTO そのものではありません。

```python
def upsert(self, df, join_cols=None, when_matched_update_all=True,
           when_not_matched_insert_all=True, case_sensitive=True,
           branch=MAIN_BRANCH, snapshot_properties=EMPTY_DICT) -> UpsertResult
```

真偽値2つのみで、**条件付き句や `WHEN MATCHED THEN DELETE` はありません**。

### 対応している操作

| 操作 | 可否 |
|---|---|
| `create_namespace` / `drop_namespace` / `list_namespaces` / `namespace_exists` | ○ |
| `create_table` / `create_table_if_not_exists` / `create_table_transaction` | ○ |
| `register_table` / `load_table` / `table_exists` / `rename_table` / `drop_table` / `purge_table` | ○ |
| `append`（既定 fast append） | ○ |
| `overwrite`（`overwrite_filter` 可） / `dynamic_partition_overwrite` | ○ |
| `delete`（`delete_filter`） | ○（**CoW のみ**） |
| `upsert` | ○ |
| `add_files`（`check_duplicate_files=True` 既定） | ○ |
| `update_schema`（add/rename/update/delete/move/union_by_name） | ○ |
| **パーティション進化** `update_spec` | ○ |
| `update_sort_order` | ○（0.11.0〜） |
| `manage_snapshots`（create/remove tag・branch） | ○ |
| タイムトラベル、ロールバック | ○ |
| `scan` → `to_arrow` / `to_pandas` / `to_duckdb` / `to_polars` / `to_ray` / `to_daft` / `to_bodo` | ○ |
| `inspect.*`（snapshots/partitions/entries/refs/manifests/history/files/…） | ○ |
| `table.maintenance.expire_snapshots()` | ○ |

### extras（PyPI の `provides_extra` で実測、全24件）

```
pyarrow, pandas, duckdb, ray, bodo, daft, polars, snappy,
hive, hive-kerberos, s3fs, glue, adlfs, dynamodb, bigquery,
sql-postgres, sql-sqlite, gcsfs, rest-sigv4, hf,
pyiceberg-core, datafusion, gcp-auth, entra-auth
```

> `rest` や `minio` という extras は**存在しません**。REST カタログは追加 extras 不要（コア機能）です。

### 設定の落とし穴

**`s3.path-style-access` は PyIceberg に存在しません。**

released 0.11.1 のソース全体を grep しても該当キーはなく、`S3_FORCE_VIRTUAL_ADDRESSING = "s3.force-virtual-addressing"` のみ実在します。`s3.path-style-access` は **Java 版 Iceberg / Spark 側のキー**であり、PyIceberg に書いても**エラーにならず黙って無視されます**（プロパティは単なる dict 参照のため）。

さらに重要なのは、**MinIO 等で path-style を使いたい場合、何も設定しなくてよい**という点です:
- `_initialize_s3_fs` は**プロパティが明示指定された時のみ** `force_virtual_addressing` を PyArrow へ渡す
- PyArrow の既定は `False` で、意味は「If false, then virtual addressing is only enabled if `endpoint_override` is empty」
- → **`s3.endpoint` を設定した時点で自動的に path-style になります**

**実在する S3 キー**（`pyiceberg/io/__init__.py` から実測）:
```
s3.endpoint            s3.access-key-id       s3.secret-access-key
s3.session-token       s3.region              s3.resolve-region
s3.profile-name        s3.anonymous           s3.proxy-uri
s3.connect-timeout     s3.request-timeout     s3.signer
s3.signer.uri          s3.signer.endpoint     s3.role-arn
s3.role-session-name   s3.force-virtual-addressing   s3.retry-strategy-impl
```

**`s3.region` は実質必須**です。未指定だと `_cached_resolve_s3_region(bucket=...)` でバケットのリージョン解決を試み、S3 以外（MinIO/RustFS）では失敗/遅延の原因になります。

**FileIO の優先順位**（`SCHEMA_TO_FILE_IO` より）:

| scheme | 優先順 |
|---|---|
| `s3` / `s3a` / `s3n` | **PyArrowFileIO → FsspecFileIO** |
| `oss`, `gs`, `hdfs`, `viewfs` | PyArrowFileIO のみ |
| `abfs(s)`, `wasb(s)` | FsspecFileIO → PyArrowFileIO |

> **落とし穴**: `s3` は PyArrow が優先です。`pip install pyiceberg[s3fs]` だけ入れて pyarrow も入っていると、**s3fs ではなく PyArrow が使われます**。明示するには `py-io-impl` を指定してください。

**`X-Iceberg-Access-Delegation` は自動送信されます**（`rest/__init__.py` L773: `session.headers.setdefault("X-Iceberg-Access-Delegation", "vended-credentials")`）。手動で付ける必要はありません。

**`scope` の既定は `catalog`**。Polaris では `PRINCIPAL_ROLE:ALL` の明示が必須です。

---

## その他のエンジン（要点のみ）

### StarRocks（4.0.1、2025-11-17）
読みは GA（v2.4+）、書きは **INSERT 系のみ**（CTAS/INSERT/OVERWRITE、v3.1+）。**DELETE/UPDATE/MERGE なし**。v3 は**なし**（tracker #63819、未アサイン）。

### Doris（4.1.1）
**V3 read は 4.1.0〜**。INSERT/CTAS は GA、**UPDATE/DELETE/MERGE は 4.1.0 から experimental**（「POC before production」）。DV read あり、row lineage は experimental。

### Impala（4.5.0、2025-03-03）
INSERT、DELETE（4.3）、UPDATE（4.4）、**MERGE（4.5）**。ただし **position delete のみ、Parquet のみ、MoR のみ**。**REST catalog はどのリリースにも入っておらず**、未リリースの 5.0 が目標（IMPALA-15144 In Progress）。v3 は**なし**。**16ヶ月リリースが止まっています**。

### Hive（4.2.0、2025-11-23）— 死んでいない
**Attic に入っていません**（attic.apache.org を実際に取得して確認。Hive は不在。なお HiveMind は Attic にあるが別プロジェクト）。

リリース: 4.0.0（2024-03）→ 4.1.0（2025-07-31）→ 4.2.0（2025-11-23）。`[DISCUSS] Next Release (4.3.0)` スレッド（2026-01-19〜2026-05-20）で **Iceberg V3 が最優先スコープ**（「Hive should be one of the core engines supporting Iceberg v3」）。

**この中で唯一 IRC サーバを持つエンジン**です（HMS REST Catalog、4.2.0）。4.2.0 で auto-compaction と Z-ordering を追加。

**正直な注記**: dev リストの流量は細く（2026年7月は1メッセージ）、4.3.0 は ~4月目標を過ぎています。**going concern だが遅い**、というのが実態です。「Hive は死んだ」という言説を支持する一次情報は見つかりませんでした。

### DuckDB
書きは **1.4（2025-09-16）から**（CREATE/INSERT/COPY）。UPDATE/DELETE/MERGE は**未確認**。カタログ接続は S3 Tables、R2、Polaris、Lakekeeper、Unity に対応。scan planning は**未対応**（[Issue #977](https://github.com/duckdb/duckdb-iceberg/issues/977) オープン）。

### ClickHouse
書きは **experimental・フラグ制**（`allow_experimental_insert_into_iceberg`）、INSERT/CREATE のみ、DML なし。カタログ経路も experimental（`allow_experimental_database_iceberg`）。

> **注意**: DuckDB / ClickHouse の**ネイティブ VARIANT 型と Iceberg v3 VARIANT を混同しないこと。** 両者を結びつけるソースはありません。

### BigQuery
2026-04-20 に **BigLake を「Lakehouse for Apache Iceberg」へ改称**。Managed Iceberg tables **GA**、BigLake Metastore（Iceberg REST カタログ）**GA**。BigLake external tables は**設計上読み取り専用**。

### Athena
engine v3 で GA。INSERT/UPDATE/DELETE/**MERGE**、OPTIMIZE、VACUUM。DV + row lineage は 2025-11 の AWS 発表による。

### Redshift
読みは GA（Spectrum/Glue/S3 Tables 経由）。**書き込みは【未確認】** — AWS のドキュメントに肯定も否定も見つかりませんでした。**これは本調査で最大の真の未知です。**

---

## 未確認事項

- **Flink の row lineage 生成（通常書き込みパス）** / **DV 読み取り** / **multi-arg transforms** / **default values 書き込み** — 一次情報を探した限り**本当に見つかりませんでした**
- **Spark 3.5 での row lineage compaction 保存**（PR タイトルが "Spark 4.0" 限定）
- **Trino / Presto の CoW vs MoR 設定**
- **Redshift の Iceberg 書き込み可否**
- **Databricks の新規 managed テーブルの既定 format version**
- **Snowflake の externally-managed テーブルにおける MERGE の制限**（列挙された DML 制約以外）
- **Dremio の並行ライタ / 外部エンジンとの競合セマンティクス**
- **iceberg-rust の対応状況**

---

## 出典

**Apache Iceberg**
- Multi-engine support: https://raw.githubusercontent.com/apache/iceberg/main/site/docs/multi-engine-support.md
- Releases: https://iceberg.apache.org/releases/ / https://github.com/apache/iceberg/releases/tag/apache-iceberg-1.11.0
- Spark docs（生ソース）: `https://raw.githubusercontent.com/apache/iceberg/main/docs/docs/spark-{writes,ddl,configuration,queries,procedures}.md`
- Flink docs（生ソース）: `https://raw.githubusercontent.com/apache/iceberg/main/docs/docs/flink-{writes,ddl,configuration}.md`
- PR #11561（Spark DV write）、#13310（Spark 4.0 row lineage）、#14297（VARIANT shredding）、#17073（geometry、1.12.0）
- PR #14197（Flink DV write）、#14148（Flink row lineage read）、#15265（Flink VARIANT）

**PyIceberg**
- PyPI JSON API: https://pypi.org/pypi/pyiceberg/json
- 0.11.0 release blog: https://iceberg.apache.org/blog/apache-iceberg-python-0.11.0-release/
- Configuration: https://py.iceberg.apache.org/configuration/
- released tag `pyiceberg-0.11.1` ソース（`io/__init__.py`, `io/pyarrow.py`, `table/__init__.py`, `table/metadata.py`, `table/maintenance.py`, `catalog/rest/__init__.py`）
- Issue #1551（V3 write）: https://github.com/apache/iceberg-python/issues/1551

**エンジン各社**
- Trino: https://trino.io/docs/current/connector/iceberg.html / https://raw.githubusercontent.com/trinodb/trino/master/docs/src/main/sphinx/connector/iceberg.md
- Presto: https://prestodb.io/docs/current/connector/iceberg.html / https://github.com/prestodb/presto/issues/27198
- Snowflake: https://docs.snowflake.com/en/user-guide/tables-iceberg-access-using-external-query-engine-snowflake-horizon / release notes 2026-05-07, 2026-05-26
- Databricks: https://docs.databricks.com/aws/en/iceberg/iceberg-v3 / https://www.databricks.com/blog/unity-catalog-and-next-era-apache-icebergtm
- Dremio: https://docs.dremio.com/dremio-cloud/developer/data-formats/iceberg/
