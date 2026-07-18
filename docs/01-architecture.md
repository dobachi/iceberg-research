# 01. アーキテクチャと中核概念

**調査基準日: 2026-07-17** / **一次情報: [Apache Iceberg Table Spec](https://iceberg.apache.org/spec/)（生ソース: [`format/spec.md`](https://github.com/apache/iceberg/blob/main/format/spec.md)）**

> **取得方法についての注記**: `iceberg.apache.org/spec/` は JS レンダリングのため HTTP フェッチでは本文が取得できません。本報告書は同一内容の生ソース（`apache/iceberg` main の `format/spec.md`、2137行）を直接取得して精査しています。以降のドキュメントでも同じ手法を使っています。詳細は [99-methodology.md](99-methodology.md) を参照。

---

## Iceberg とは何か（そして何でないか）

Iceberg は**テーブルフォーマット**です。ファイルフォーマット（Parquet/ORC/Avro）でもストレージでもエンジンでもありません。「オブジェクトストレージ上に散らばったファイル群を、1つのテーブルとして正しく扱うためのメタデータの規約」がその実体です。

Hive テーブルとの根本的な違いは、仕様の Overview に明記されています。

> This table format tracks **individual data files** in a table instead of directories.

**ディレクトリではなくファイル単位で追跡する** — ここからほぼすべての設計上の帰結が導かれます。ディレクトリリスティングに依存しないため、オブジェクトストレージ上でも正確かつ高速に動作し、パーティションの物理レイアウトを変えてもクエリの書き換えは不要です。

---

## 三層のメタデータ構造

```
catalog                       … テーブル → 現 metadata ファイルへのポインタ
  └─ v<N>.metadata.json       … テーブル状態（JSON）
       └─ snapshot            … metadata.json 内に埋め込まれたリスト
            └─ manifest list  … snap-*.avro（1スナップショットに1つ）
                 └─ manifest  … *-m0.avro（データ用/削除用は分離）
                      └─ data file / delete file（Parquet/ORC/Avro/Puffin）
```

| 層 | ファイル名例 | フォーマット | 役割 |
|---|---|---|---|
| catalog | （外部） | メタストア/REST/DB | 現 metadata ファイルへのポインタを保持。**atomic swap の実行主体** |
| metadata file | `v<V>.metadata.json` または `<V>-<uuid>.metadata.json` | **JSON** | schema / spec / sort-order / snapshot 一覧 / properties |
| manifest list | `snap-<snapshot-id>-<n>.avro` | **Avro** | 1スナップショット分の manifest 一覧＋パーティション要約統計 |
| manifest | `<uuid>-m<n>.avro` | **Avro** | data file または delete file の一覧＋パーティション値＋列統計 |
| data file | `*.parquet` 等 | Parquet / ORC / Avro | 実データ |
| delete file / DV | `*-deletes.parquet` / `*.puffin` | Parquet/ORC/Avro / **Puffin** | 行レベル削除 |

仕様が明示する重要な性質:

- 「The data in a snapshot is the **union of all files in its manifests**.」
- 「Manifest files are **reused across snapshots** to avoid rewriting metadata that is slow-changing.」— マニフェストは変化の遅いメタデータを再利用する仕組みです。
- 「Manifests can track data files with **any subset of a table and are not associated with partitions**.」— **マニフェストはパーティションに紐づきません。** これは頻出する誤解です。

### マニフェストの制約

- 「A manifest may store either data files or delete files, **but not both** because manifests that contain delete files are **scanned first** during job planning.」— delete を先に読む必要があるため、分離されています。
- 「A manifest stores files for a **single partition spec**.」— manifest の Avro スキーマがパーティションスペックに依存するため、スペックが変わればファイルは別の manifest に書かれます。
- 「All columns must be written to data files even if they introduce redundancy with metadata（例: identity パーティション列）… provides a **backup in case of corruption or bugs in the metadata layer**.」— メタデータ層のバグに対する保険として、冗長でも全列を書きます。

---

## ACID と楽観的並行制御

仕様の記述:

> An **atomic swap** of one table metadata file for another provides the basis for **serializable isolation**.

> Readers use the snapshot that was current when they load the table metadata and are **not affected by changes until they refresh**.

> Writers create table metadata files **optimistically**, assuming that the current version will not be changed before the writer's commit.

そして最も重要な一文:

> **The conditions required by a write to successfully commit determines the isolation level. Writers can select what to validate and can make different isolation guarantees.**

**分離レベルは固定ではなく、書き込み側の検証条件で決まります。** これは実務上きわめて重要な性質で、`write.*.isolation-level`（既定 `serializable`、`snapshot` に緩和可能）という設定が存在する理由でもあります。

設計目標として「**Readers will not acquire locks.**」が明記されています。読み手はロックを取りません。

### コミットの実装

**Metastore Tables**（推奨）:
1. 現メタデータを基に新メタデータを作成
2. `<V+1>-<random-uuid>.metadata.json` に書き出し
3. メタストアに **check-and-put** でポインタ swap を要求 → 成功なら commit 成立、失敗なら 1 に戻る

**File System Tables**（**使わないこと**）: atomic rename を使う方式ですが、仕様が明示的に deprecated とし、さらに「The scheme is **unsafe** in object stores and local file systems.」と述べ、**v4 で削除予定**としています。カタログ（metastore / REST）を使ってください。

> **重要**: 仕様は commit の atomic 操作自体を標準化していません。「The atomic operation used to commit metadata depends on how tables are tracked and **is not standardized by this spec**.」— **カタログ実装依存**です。これが REST Catalog 仕様（[03](03-rest-catalog.md)）が重要になる理由の一つです。

### 競合解決とリトライ

| 操作 | 検証条件 |
|---|---|
| **Append** | 「have no requirements and can **always** be applied.」— 常に適用可能 |
| **Replace** | 削除予定ファイルがまだテーブルにあることを検証（compaction 等） |
| **Delete** | 削除対象ファイルがまだテーブルにあることを検証。ただし**式ベースの削除（`where timestamp < X`）は常に適用可能** |
| **スキーマ/スペック更新** | base 版と current 版でスキーマが変わっていないことを検証 |

### シーケンス番号と継承

コミット成功ごとに単調増加します。設計の妙は**継承（inheritance）機構**にあります。

> Inheriting the sequence number from manifest metadata allows **writing a new manifest once and reusing it in commit retries**. To change a sequence number for a retry, **only the manifest list must be rewritten**.

新規エントリは `null` で書かれ、読み取り時に manifest list の値へ置き換わります。おかげで**リトライのコストは manifest list の書き直しだけで済みます**。継承が効くのは status=1 (ADDED) のときに限られ、EXISTING/DELETED では明示値が必須です。

`sequence_number`（データシーケンス番号 = 内容の相対的な古さ）と `file_sequence_number`（追加時のスナップショット番号）は別物です。仕様は「**The file sequence number can't be used for pruning delete files**」と明記しています。

---

## クエリプランニングの多段プルーニング

仕様の設計目標:

> **Speed** — Operations will use **O(1) remote calls** to plan the files for a scan and **not O(n)** where n grows with the size of the table, like the number of partitions or files.

これを支えるのが多段プルーニングです。

**段1: manifest レベルのスキップ**
manifest list の各エントリは `field_summary`（`contains_null` / `contains_nan` / `lower_bound` / `upper_bound`）と各種カウントを持ちます。仕様: 「Manifests that contain no matching files, determined using either **file counts or partition summaries**, may be skipped.」— **manifest ファイル自体を開かずに除外**します。

**段2: manifest 内のパーティションプルーニング**
スキャン述語を **inclusive projection** でパーティション述語に変換します。「Conversion uses the partition spec that was **used to write the manifest file** regardless of the current partition spec.」— これがパーティション進化に対応できる鍵です。

**段3: 列統計によるファイルプルーニング**
「Scan predicates are also used to filter data and delete files using **column bounds and counts** that are stored by field id in manifests.」

**段4: delete ファイルのプルーニング**
> **The same filter logic can be used for both data and delete files** because both store metrics of the rows either inserted or deleted. If metrics show that a delete file has no rows that match a scan predicate, it may be **ignored just as a data file would be**.

具体例（仕様より）: 「if `file_a` has rows with `id` between 1 and 10 and a delete file contains rows with `id` between 1 and 4, a scan for `id = 9` **may ignore the delete file**」— **delete ファイルもプルーニング対象**です。MoR の性能を理解する上で重要な点です。

### inclusive projection とは

> if a scan predicate matches a row, then the partition predicate must match that row's partition. This is called _inclusive_ because **rows that do not match the scan predicate may be included in the scan** by the partition predicate.

例: `ts_day=day(ts)` パーティションで `ts > X` → `ts_day >= day(X)`。**false positive は許容、false negative は不可**という非対称な保証です。これが hidden partitioning（クエリにパーティション列を書かなくてよい）の実体です。

対になる **strict projection** は「a partition predicate that will match a file **if all of the rows in the file must match** the scan predicate」で、各ファイルの residual predicate 計算に使われます。

### 未知の transform

「The inclusive projection for an unknown partition transform is **_true_**」— フィルタリングでは無視されます。ただし「the result of an unknown transform is **still used when testing whether partition values are equal**」（delete 適用のパーティション一致判定には使われる）点に注意。

### スキャンの前提条件

> for any snapshot, all file paths marked with "ADDED" or "EXISTING" **may appear at most once** across all manifest files in the snapshot. If a file path appears more than once, the results of the scan are **undefined**.

---

## Puffin と統計情報

Puffin は統計とインデックスのための blob コンテナ形式です。現在2つの blob 型が定義されています。

- **`apache-datasketches-theta-v1`**: Apache DataSketches の compact Theta sketch。blob metadata の properties に `ndv`（distinct 値数の推定）を含みうる。
- **`deletion-vector-v1`**: v3 の deletion vector（[02](02-table-spec.md#deletion-vector-dv) 参照）。

**統計は情報提供目的（informational）です。**

> Statistics are informational. A reader can **choose to ignore** statistics information. **Statistics support is not required to read the table correctly.**

パーティション統計も同様に「not required for reading or planning」です。**正しさには不要で、速度のためだけに存在します。** ただし読み手が有効な統計ファイルとして扱うには「**must be registered in the table metadata file** to be considered as a valid statistics file for the reader」という登録が求められます。

---

## メタデータテーブル

`db.table.history` のようにテーブル名の後にメタデータテーブル名を付けて参照します。

| テーブル | 用途 |
|---|---|
| `history` | テーブル履歴。`is_current_ancestor` で**ロールバックされたコミットを検出**できる |
| `metadata_log_entries` | metadata.json の変遷 |
| `snapshots` | 有効なスナップショット一覧 |
| `entries` | 現在の manifest エントリ（data/delete 両方）。`readable_metrics` 付き |
| `files` / `data_files` / `delete_files` | 現在のファイル一覧と統計 |
| `manifests` | 現在の manifest 一覧と `partition_summaries` |
| `partitions` | 現在のパーティションとレコード数 |
| `position_deletes` | position delete の中身 |
| `refs` | branch / tag 一覧 |
| `all_*`（`all_files`, `all_entries`, `all_manifests` ほか） | **全スナップショット横断**。孤児ファイル調査に有用だがコスト高 |

実務上の注意:

- **`partitions` テーブルは delete を適用しません。** 「delete files are not applied, and so in some cases partitions may be shown even though all their data rows are marked deleted by delete files.」— 全行削除済みのパーティションも表示されます。
- `manifests` の `contains_nan` は **v1 テーブルでは null になりえます**（populate されないため）。
- `partitions` テーブルは非パーティションテーブルでは `partition` と `spec_id` 列を持ちません。

---

## タイムトラベルと2つの履歴

**Iceberg には2種類の履歴があり、食い違うことがあります。**

1. `snapshot-log`（過去の "current snapshot" の履歴）
2. `snapshots` 内の parent-child 系譜

> These two histories **might indicate different snapshot IDs for a specific timestamp**.

原因は「updating the `current-snapshot-id` can be used to set the snapshot of a table to **any arbitrary snapshot**, which might have a lineage derived from a table branch or **no lineage at all**」。`set_current_snapshot` プロシージャが系譜を持たないエントリを snapshot-log に生む可能性があります。

**仕様の指示**: 「When processing point in time queries implementations **should use "snapshot-log" metadata**」。該当が無い、または snapshot-log が未 populate なら「informative error message」を出すべきとされています。

---

## branch / tag と WAP

snapshot reference は `snapshot-id` / `type`（`tag` | `branch`）/ `min-snapshots-to-keep`（branch のみ）/ `max-snapshot-age-ms`（branch のみ）/ `max-ref-age-ms` を持ちます。

- 「There is always a `main` branch reference pointing to the `current-snapshot-id` even if the `refs` map is null.」
- **「The `main` branch never expires.」**

### スナップショット保持ポリシーのアルゴリズム

1. 保持集合を空で開始
2. main 以外の ref で、参照先が `max-ref-age-ms` より古いものを削除
3. 各 branch / tag について参照先スナップショットを保持集合に追加
4. 各 branch について、以下の**両方**を満たすまで祖先を追加: (a) `max-snapshot-age-ms` より古い **AND** (b) branch の最初の `min-snapshots-to-keep` 個に含まれない
5. 保持集合に無いスナップショットを expire

> **運用上の罠**: タグを1つ付けただけで、そのタグが参照するスナップショットとその依存ファイルは無期限に残ります。Amazon S3 Tables ではこれがさらに深刻な挙動（テーブル全体で自動メンテナンスが停止）になります → [06](06-operations.md#c-1-amazon-s3-tables)

### Write-Audit-Publish（WAP）

```sql
-- 1. WAP を有効化
ALTER TABLE db.table SET TBLPROPERTIES ('write.wap.enabled'='true');
-- 2. 監査ブランチを作成（7日保持）
ALTER TABLE db.table CREATE BRANCH `audit-branch` AS OF VERSION 3 RETAIN 7 DAYS;
-- 3. ブランチへ書き込み（main の履歴とは独立）
SET spark.wap.branch = audit-branch;
INSERT INTO prod.db.table VALUES (3, 'c');
-- 4. 検証ワークフローで audit-branch の状態を検証
-- 5. 検証後、main を audit-branch の head まで fast-forward
CALL catalog_name.system.fast_forward('prod.db.table', 'main', 'audit-branch');
```

snapshot summary の WAP 関連フィールド: `wap.id`（ステージされたスナップショットの WAP ID）、`published-wap-id`、`source-snapshot-id`（cherry-pick 元）。

> **重要な制約**: 「**the schema tracked for a table is valid across all branches**」— **スキーマはブランチ間で共有されます。** ブランチごとに独立したスキーマは持てません。

### rollback 系プロシージャ

| プロシージャ | 用途 |
|---|---|
| `rollback_to_snapshot('db.sample', 1)` | 特定スナップショットへロールバック |
| `rollback_to_timestamp('db.sample', TIMESTAMP '...')` | 特定時刻へロールバック |
| `set_current_snapshot('db.sample', 1)` | 現スナップショットを任意に設定（**祖先でなくてもよい**） |
| `cherrypick_snapshot('my_table', 1)` | 既存スナップショットの変更を現在の状態に適用 |
| `publish_changes('my_table', 'wap_id_1')` | WAP ID からスナップショットを publish。同じ wap_id が複数あると**失敗** |
| `fast_forward('my_table', 'main', 'audit-branch')` | ブランチを別ブランチの head へ早送り |

---

## 出典

- Iceberg Table Spec: https://iceberg.apache.org/spec/ / 生ソース https://github.com/apache/iceberg/blob/main/format/spec.md
- Puffin Spec: https://iceberg.apache.org/puffin-spec/ / https://github.com/apache/iceberg/blob/main/format/puffin-spec.md
- Spark Queries（メタデータテーブル、タイムトラベル）: https://github.com/apache/iceberg/blob/main/docs/docs/spark-queries.md
- Spark Procedures（rollback、cherrypick、fast_forward）: https://github.com/apache/iceberg/blob/main/docs/docs/spark-procedures.md
- Branching and Tagging（WAP）: https://github.com/apache/iceberg/blob/main/docs/docs/branching.md
