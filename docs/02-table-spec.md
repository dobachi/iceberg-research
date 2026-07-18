# 02. テーブル仕様 v1 / v2 / v3（と v4 の現況）

**調査基準日: 2026-07-17** / **一次情報: [`format/spec.md`](https://github.com/apache/iceberg/blob/main/format/spec.md)（main、2137行を全文精査）**

---

**まず「フォーマットバージョン」とは何か。** Iceberg のテーブルには v1・v2・v3… というバージョンがあり、これは**テーブルのメタデータがどの決まりに従って書かれているか**を表します。ソフトウェアのファイル形式にバージョンがあるのと同じで、新しいバージョンほど新しい機能（行単位の削除、新しいデータ型など）を扱えます。逆に、v2 までしか理解しないツールは v3 の新機能を正しく読めません。だからバージョンを上げるかどうかは、**使いたい機能と、読み書きするツールの対応状況しだい**で決まります。

大きな流れはこうです。**v1** はファイルを並べるだけの素朴な形式、**v2** で「一部の行だけを消す・更新する」が効率的にできるようになり、**v3** で新しいデータ型や高度な機能が加わりました。**v4** はまだ策定中です。以下で1つずつ見ていきます。

## 最初に: バージョンの現況

仕様書の冒頭が、すべてを簡潔に述べています。

> Versions 1, 2 and 3 of the Iceberg spec are **complete and adopted by the community**.
> **Version 4 is under active development and has not been formally adopted.**

| バージョン | 名称 | ステータス |
|---|---|---|
| v1 | Analytic Data Tables | 採択済み |
| v2 | Row-level Deletes | 採択済み。**現在のデフォルト** |
| v3 | Extended Types and Capabilities | **採択済み**（1.8.0〜段階的に実装） |
| v4 | Metadata Structure and Representation | **仕様は未採択**。ただし **Java 実装は 1.10.0+ で `format-version=4` を受け付ける**（PyIceberg は不可）。既定は 2 |

### バージョニングの原則

> The format version number is incremented when new features are added that will break **forward-compatibility** — that is, when **older readers would not read newer table features correctly**.

前方互換性が壊れるときにだけ上がります。「新機能が入ったから上げる」わけではありません。

---

## v1: Analytic Data Tables

イミュータブルなファイル形式（Parquet, Avro, ORC）で大規模分析テーブルを管理する、最初の仕様です。データファイルは一度書いたら変更しない前提で、大量データの分析に向いています。その代わり、**行単位の削除・更新という仕組みがまだ無く**、一部の行を消すだけでもファイルを丸ごと書き直す必要がありました。これを解決したのが v2 です。

「All version 1 data and metadata files are valid after upgrading a table to version 2.」— **v1→v2 アップグレードでメタデータツリーの書き換えは不要**です。

---

## v2: Row-level Deletes

v2 の目玉は、名前のとおり **行単位の削除（row-level delete）** です。「削除された行」を別の小さなファイル（delete file）に記録しておき、読み取り時に元データと突き合わせて除外する — という仕組みを導入しました。おかげで、数行消すために巨大なデータファイルを書き直さずに済みます。`MERGE` / `UPDATE` / `DELETE` が現実的なコストで回るのは、これがあるからです。

仕様レベルの細かな変更点は次の通りです（Appendix E より）:

- **delete file の追加**（position / equality）→ ファイル書き換えなしの行単位削除・更新
- **シーケンス番号**の導入
- `data_file.content` 追加（0=data, 1=position deletes, 2=equality deletes）、`equality_ids` 追加
- manifest list `content` 追加（0=data, 1=deletes）
- **必須化**: `table-uuid`, `current-schema-id`, `schemas`, `partition-specs`, `default-spec-id`, `last-partition-id`, `sort-orders`, `default-sort-order-id`, snapshot の `manifest-list`, manifest list の各カウント類
- **削除**: `block_size_in_bytes`（**v1 reader 互換を破ると明記**）, `file_ordinal`, `sort_columns`
- `manifest_entry.snapshot_id` が optional 化（継承サポートのため）
- 「Manifest list files are **required in v2**」

---

## v3: Extended Types and Capabilities

v3 は、v2 までで扱えなかった **新しいデータ型** と、いくつかの **高度な機能** を加えたバージョンです。半構造化データ（variant）、地理データ（geometry / geography）、ナノ秒精度の時刻といった型に加え、列のデフォルト値、行の来歴を追う row lineage、より効率的な削除方式の deletion vector などが入りました。仕様が挙げる新機能は次の通りです:

> * New data types: **nanosecond timestamp(tz)**, **unknown**, **variant**, **geometry**, **geography**
> * **Default value support** for columns
> * **Multi-argument transforms** for partitioning and sorting
> * **Row Lineage** tracking
> * **Binary deletion vectors**
> * **Table encryption keys**

### 新しい型

| 型 | 説明 |
|---|---|
| `unknown` | 「Default / null column type used when a more specific type is not known」。**optional かつ null default 必須、データファイルに格納しない**。任意の型へプロモーション可能 |
| `timestamp_ns` / `timestamptz_ns` | ナノ秒精度。Avro は `timestamp-nanos`（**Iceberg 独自規約、Avro spec には無い**と明記）、Parquet は `TIMESTAMP_NANOS` |
| `variant` | 半構造化データ。**エンコーディングは Parquet プロジェクト側で定義**（VariantEncoding.md）、現状 **V1 のみ**。Avro では**シュレッディング非対応** |
| `geometry(C)` | OGC Simple feature access。エッジ補間は**常に線形/平面（Cartesian）**。CRS パラメータ C、既定 `OGC:CRS84` |
| `geography(C, A)` | CRS C ＋エッジ補間アルゴリズム A（`spherical`(既定) / `vincenty` / `thomas` / `andoyer` / `karney`） |

**CRS の重要な制約**:

> CRS value **must not contain inlined PROJJSON definitions** and implementations **must not parse** the contents of the CRS as PROJJSON. PROJJSON definitions are very verbose, hence inlining them as part of schema would cause **significant performance degradation**.

`projjson:<property-name>` 形式でテーブルプロパティを参照します。

### default values

- **`initial-default`**: フィールド追加**以前**に書かれた全レコードの値を埋めます → **データファイルを書き換えずに SQL の DEFAULT 挙動を実現**します
- **`write-default`**: フィールド追加**以後**、writer が値を供給しない場合に埋めます

規則:
- 「The `initial-default` is set only when a field is added to an existing schema.」
- 「If the write default for a **required** field is not set, the writer **must fail**.」
- **`unknown`, `variant`, `geometry`, `geography` は全て null default 必須**（非 null は invalid）
- ネスト struct の default は「null または**フィールド値を持たない非 null struct（`{}`）**」のみ

**前方互換性の注意**: 「Old readers will **fail to read required fields** which are populated by `initial-default` because that default is not supported.」

> **実装状況の注意**: Spark は default values の**書き込みを明示的に拒否**します（[05](05-engine-support.md#apache-spark) 参照）。読み取り適用は 1.8.0 から対応。

### multi-argument transforms

Partition Field / Sort Field JSON に **`source-ids`**（JSON int リスト）が追加されました。

- 「For partition fields with a transform with a **single argument, only `source-id` is written**. In case of a **multi-argument transform, only `source-ids` is written**.」— 排他的です。
- v3 では `source-id` / `source-ids` **両方 optional**（v1/v2 では `source-id` が required）。

**注記**: 仕様の transform 一覧表には現時点で**複数引数の具体的な transform は載っていません**。仕組み（`source-ids`）のみが定義された状態です。将来の transform 追加のための基盤整備と読めます。

### row lineage

> In v3 and later, an Iceberg table **must** track row lineage fields for all newly created rows.

**v3 では必須で、オプトインではありません。** 1.10.0 のリリースノート「remove update to enable row lineage as it is **always on for V3 table**」がこれを裏付けます。

2つの行レベルフィールド:
- **`_row_id`**（field id 2147483540）: テーブル内で一意な long。行が最初に追加された時に**継承で割り当て**
- **`_last_updated_sequence_number`**（field id 2147483539）: 最後に更新したコミットのシーケンス番号

**なぜ継承なのか**:

> the commit sequence number and starting row ID are **not assigned until the snapshot is successfully committed**. Inheritance is used to allow writing data and manifest files before values are known so that it is **not necessary to rewrite data and manifest files when an optimistic commit is retried**.

割り当ての連鎖: table `next-row-id` → snapshot `first-row-id` → manifest `first_row_id` → data file `first_row_id` → 行の `_row_id = first_row_id + _pos`

#### row lineage の重大な制約: equality delete では追跡されない

> engines using equality deletes **avoid reading existing data before writing changes** and can't provide the original row ID for the new rows. These updates are always treated as if the existing row was **completely removed and a unique new row was added**.

**CDC 用途で row lineage を当てにするなら、equality delete を使うエンジン（典型的には Flink の upsert）では機能しません。** これは v3 の目玉機能の実用上最大の穴です。

#### アップグレード時の非対称性

v3 化で `next-row-id` は 0 に初期化され、既存スナップショットは変更されず `first-row-id` は未設定のままです。→ **アップグレード前のスナップショットには row ID が無く、`_row_id` は全行 null として読まれます。** 後付けできません。

行を別ファイルに移動する場合（compaction 等）の規則:
1. 既存の非 null `_row_id` をコピー
2. 変更していれば `_last_updated_sequence_number` を null に
3. 変更していなければ既存値をコピー

### table encryption keys

`encryption-keys`（`key-id` / `encrypted-key-metadata`(base64) / `encrypted-by-id` / `properties`）を table metadata に持ち、snapshot は `key-id` で参照します。1.10.0 で仕様に追加されました。

---

## Copy-on-Write と Merge-on-Read

行を更新・削除するとき、Iceberg には**2つの書き込み方**があります。

- **Copy-on-Write（CoW）**: 変更が及ぶデータファイルを**丸ごと書き直す**方式。書き込みは重いですが、読み取りは速い（読む側は特別なことをしなくてよい）。
- **Merge-on-Read（MoR）**: 元のデータファイルはそのままに、「この行は消えた」という情報を別ファイルに**追記するだけ**の方式。書き込みは軽いですが、読み取り時に元データと差分を突き合わせる手間がかかります。

どちらを使うかはテーブルプロパティで選びます。既定は CoW です。

### デフォルトは CoW（重要）

| プロパティ | デフォルト | 説明 |
|---|---|---|
| `write.delete.mode` | **copy-on-write** | copy-on-write または merge-on-read（**v2 以上**） |
| `write.update.mode` | **copy-on-write** | 同上 |
| `write.merge.mode` | **copy-on-write** | 同上 |
| `write.delete.granularity` | **partition** | partition または file |
| `write.delete.isolation-level` | serializable | serializable または snapshot |
| `format-version` | **2** | 「Defaults to 2 since version 1.4.0.」 |

**Iceberg のテーブルはデフォルトで format-version=2 かつ CoW です。MoR を使うには明示設定が必要です。** そして **v3 にしても DV は自動では使われません**（`write.delete.mode` の既定が CoW のままのため）。見落とされやすい点です。

なお仕様自体は CoW/MoR という用語で書き分けておらず、これはエンジン側（Spark 等）の書き込み戦略の設定です。

---

## delete の3形式

行を削除したとき、その「削除」をどう記録するかに3つの方式があります。いずれも**元のデータファイルはいじらず、削除の情報を別に持つ**（＝ MoR）点は同じで、記録の仕方が異なります。

> Row-level deletes are added by **v2** and are **not supported in v1**. Deletion vectors are added in **v3** and are **not supported in v2** or earlier. **Position delete files must not be added to v3 tables**, but existing position delete files are valid.

| 形式 | 導入 | 識別方法 | 状態 |
|---|---|---|---|
| **Position delete file** | v2 | データファイルパス + 行位置 | **v3 で deprecated**、v3 テーブルへの新規追加は禁止 |
| **Equality delete file** | v2 | 1つ以上の列値（例 `id = 5`） | 現役 |
| **Deletion vector (DV)** | **v3** | 単一データファイル内の位置ビットマップ | v3 の推奨形式 |

### Position delete file

`file_position_delete` 構造体: `file_path`（string）/ `pos`（long, 0始まり）/ `row`（optional struct）

- 「The rows in the delete file **must be sorted by `file_path` then `pos`**」— `file_path` ソートは列指向でのフィルタプッシュダウン、`pos` ソートは**削除情報をメモリに保持せずスキャンできるようにする**ため。
- `row` 列は「present なら required」（統計の正確性を担保するため）。ただし「no implementation currently writes it … **deprecated in version 1.11.0**」。

### Equality delete file

- 各行が1つの等値述語を生成し、複数列は `AND` として扱われます。**`null` は `col IS NULL` と等価にマッチ**します。
- **列が後で drop されても、equality delete の適用時には使い続けなければなりません。**

### Deletion vector (DV)

Puffin の **`deletion-vector-v1`** blob 型で格納されます。

- **Roaring bitmap** ベース。64-bit 位置をサポートしつつ「optimized for cases where most positions fit in 32 bits」— 上位4バイトを "key"、下位4バイトをサブ位置とし、key ごとに 32-bit Roaring bitmap を保持。
- **スナップショット内で 1 データファイルにつき DV は最大1つ**。
- 「If a DV is written for a data file, it must **replace all previously written position delete files** so that when a DV is present, **readers can safely ignore matching position delete files**.」
- manifest 側は `file_path` / `content_offset` / `content_size_in_bytes` で DV blob を個別追跡。**Puffin footer の値と厳密一致必須**。
- **1つの Puffin ファイルに複数の DV を格納可能**、参照先データファイルに制限なし。
- データファイル削除時は delete manifest から対応 DV も削除必須。ただし **Puffin ファイル自体の書き直しは不要**。

**シリアライズ形式**:
- 4バイト big-endian: ベクトル＋マジックバイトの長さ
- 4バイトマジック: **`D1 D3 39 64`**
- Roaring bitmap "portable" format（**little-endian**）
- 4バイト big-endian: CRC-32
- 「Big endian values were chosen for **compatibility with existing deletion vectors in Delta tables**.」— **Delta 互換を意識した設計**です
- `properties` に `referenced-data-file` と `cardinality` 必須、`compression-codec` は省略必須（非圧縮）
- 「`snapshot-id` and `sequence-number` must be set to **-1**」（Puffin 作成時点で未確定のため）

### delete 適用のスコープ規則（実務上最重要）

| 形式 | 適用条件 |
|---|---|
| **DV** | `file_path` == `referenced_data_file` **かつ** データシーケンス番号 **≤** DV のそれ **かつ** パーティション（spec と値の両方）が一致 |
| **Position delete** | 同様 ＋「**適用すべき DV が存在しないこと**」 |
| **Equality delete** | データシーケンス番号が **厳密に小さい（strictly less than）** ＋ パーティション一致 **または delete 側の spec が unpartitioned** |

**2つの特例**:
1. 「Equality delete files stored with an **unpartitioned spec are applied as global deletes**.」— **グローバル equality delete は全データファイルに対して照合が必要**になります。MoR の最悪ケースです。
2. 「Position deletes (vectors and files) **must be applied to data files from the same commit**, when the data and delete file data sequence numbers are **equal**.」— 同一コミット内で追加した行を削除できるようにするため。

→ **position delete は `≤`、equality delete は `<`** という非対称性が肝です。

### DV が改善したこと

1. **実行時効率**: 仕様が「**deletion vector は単一データファイルに対する delete のバイナリ表現であり、実行時に position delete ファイルより効率的**」と明言。
2. **不変条件による予測可能性 — これが最大の改善**: 「1 データファイルにつき DV は高々1つ」。v2 の position delete は1データファイルに対して**無制限に**積み上がりえたため、読み取りコストが「これまで何回 delete したか」に依存して**単調悪化**しました。v3 ではこれが構造的に不可能になり、**読み取りコストが delete 回数に依存しなくなります**。定量的改善ではなく漸近的な性質の変化です。
3. **メンテナンス負荷の消滅**: 上記の帰結として、v2 で必須だった「delete ファイルの minor compaction」というタスク自体が不要になります。
4. **直接アクセス**: `content_offset` / `content_size_in_bytes` により、Puffin ファイル全体を読まずに必要な DV blob だけレンジ取得できます。

**ただし残る問題**: 「writer は削除された DV を含む Puffin ファイルを書き直す必要はない」ため、**参照されない DV blob を含む Puffin ファイルが物理的に残りえます**。`remove_orphan_files` の領分です。DV は運用を楽にしますが、ゼロにはしません。

---

## スキーマ進化

### field ID ベース

> Columns in Iceberg data files are **selected by field id**. The table schema's column names and order may change after a data file is written, and projection **must** be done using field ids.

**Rename は field ID を変えません。** 「Renaming an existing field must change the name, **but not the field ID**.」

### 型プロモーション

| 元の型 | v1, v2 | **v3+** |
|---|---|---|
| `unknown` | — | **任意の型へ** |
| `int` | `long` | `long` |
| `date` | — | **`timestamp`, `timestamp_ns`**（`timestamptz` 系へは**不可**） |
| `float` | `double` | `double` |
| `decimal(P,S)` | `decimal(P',S)` P'>P | 同左（精度拡大のみ） |

**実務上の落とし穴**:

> Iceberg's Avro manifest format **does not store the type of lower and upper bounds**, and type promotion does not rewrite existing bounds.

bounds のバイト長から書き込み時の型を推論する必要があります（`long` 4バイト → 元は `int`、`double` 4バイト → 元は `float` 等）。仕様に推論テーブルが定義されています。

**禁止事項**: struct のフィールドをネスト struct にグルーピングする／その逆（`struct<a,b,c> ↔ struct<a,struct<b,c>>`）は**不可**。プリミティブ↔struct も不可。

**bucket transform との相互作用**:

> `bucket[N]` produces different hash values for `34` and `"34"` (2017239379 != -427558391) but the same value for `34` and `34L`

パーティションソース列は、transform 結果が変わるプロモーションが禁止されます。

### 列プロジェクションの解決順序

データファイルに field id が無い場合:
1. identity transform のパーティションメタデータから値を返す（**Hive テーブルのメタデータのみの移行**を可能にする）
2. `schema.name-mapping.default` で field id をマップ
3. `initial-default` があればそれを返す
4. それ以外は `null`

---

## パーティション進化と transform

### partition transform

| transform | 説明 | ソース型 | 結果型 |
|---|---|---|---|
| `identity` | そのまま | `geometry`/`geography`/`variant` **以外**の任意 | ソース型 |
| `bucket[N]` | ハッシュ mod N | int, long, decimal, date, time, timestamp(tz), timestamp(tz)_ns, string, uuid, fixed, binary | `int` |
| `truncate[W]` | 幅 W で切り詰め | int, long, decimal, string, binary | ソース型 |
| `year` | 1970年からの年数 | date, timestamp(tz), timestamp(tz)_ns | `int` |
| `month` | 1970-01-01 からの月数 | 同上 | `int` |
| `day` | 1970-01-01 からの日数 | 同上 | **`date`** |
| `hour` | 1970-01-01 00:00:00 からの時間数 | timestamp(tz), timestamp(tz)_ns | `int` |
| `void` | 常に `null` | 任意 | ソース型 or `int` |

細部（間違えやすい点）:
- **全 transform は `null` 入力に対し `null` を返す**こと
- `day` の結果型は `date`。ただし「Readers must also **accept `int` values** for the `day` transform」（後方互換）
- **bucket のハッシュは 32-bit Murmur3、x86 variant、seed=0**。`bucket_N(x) = (murmur3_x86_32_hash(x) & Integer.MAX_VALUE) % N`（符号ビットを捨てて正値化）
- `truncate` の負値: 「remainders must be positive」→ `v - (((v % W) + W) % W)`。`W=10` で `-1` → `-10`
- `truncate` の decimal は**列のスケールを使って** W を適用（`W=50, s=2`: `10.65` → `10.50`）。string は**コードポイント**単位、binary は**バイト**単位
- `void` は v1 テーブルでフィールドを実質的に drop するために使う

### 進化の規則

- スペック変更は新しい spec ID を生成し、テーブルの spec 一覧に追加されます。**既存データは書き換えません。**
- 「changes should not cause **partition field IDs to change** because the partition field IDs are used as the partition tuple field IDs in manifest files.」
- **v2 では partition field ID を明示的に追跡必須。v1 では追跡されず** 1000 から順に割り当てられていました。これが「複数スペックの manifest を跨いでメタデータテーブルを読むと、同じ ID のフィールドが異なる型を持ちうる」問題を生みました。
- **v1 テーブルでの推奨ルール**: ①フィールドを並べ替えない ②drop せず `void` transform に置換する ③末尾にのみ追加する
- 未知の transform: v1/v2 では reader は無視すべき、**v3 では無視が必須**。writer は未知 transform を含む spec でのコミットは**禁止**

---

## sort order

- 構成要素: source column id(s) / transform / direction(`asc`|`desc`) / null order(`nulls-first`|`nulls-last`)
- **order id `0` は unsorted 用に予約**
- 浮動小数点の順序: `-NaN < -Infinity < -value < -0 < 0 < value < Infinity < NaN`
- 「Writers **should** use this default sort order to sort the data on write, but are **not required to** if the default order is prohibitively expensive, **as it would be for streaming writes**.」
- **position delete file は sort order id を null にすること**、reader は position delete file の sort order id を**無視しなければならない**

---

## v3 の策定・リリース状況

### Apache 側の公式ステータス

**「v3 が GA」という宣言は Apache の公式リリースノート・仕様のいずれにも存在しません。** 公式ステータスは仕様冒頭の「complete and adopted by the community」という表現に留まります。**「GA」はベンダー側の製品提供状況を指す用語です。**

### 参照実装（Java）のリリース経緯

| リリース | 日付 | v3 関連の主な内容 |
|---|---|---|
| **1.8.0** | 2025-02-13 | **Deletion vectors を table spec に追加**、**Variant Type 追加**、`EnableRowLineage` メタデータ更新、snapshot に `added-rows` 追加。API: **UnknownType 追加** |
| **1.9.0** | 2025-04-28 | equality delete と row lineage の挙動定義、**V3 での source-id 使用許可**。Core: **全 v3 テーブルで row lineage を有効化**、**geometry / geography 型サポート追加**、Variant reader/writer 実装 |
| **1.10.0** | 2025-09-11 | 孤立 DV 防止の write 要件明確化、**encryption keys 追加**、default values の struct フィールド衝突回避。REST: **「row lineage is always on for V3 table」のためオプトイン更新を削除** |
| **1.11.0** | **2026-05-19** | **SQL UDF 仕様の導入**、snapshot に `added-rows` を復活、**position delete files with row data を deprecated 化**。API: **V4 manifest サポートの基盤型を導入**、**content stats のクラス導入**。Java 11 サポート終了 |

**v3 の機能は 1.8.0（2025年2月）から段階的に投入され、1.9.0 で geometry/geography と row lineage の全 v3 テーブル有効化、1.10.0 で encryption keys まで到達**しました。

### ベンダーの GA 状況

| ベンダー | v3 の状態 | 日付 | 備考 |
|---|---|---|---|
| **Snowflake** | **GA** | 2026-05-07 | 新規 managed テーブルの既定は**依然 v2**（v3 はオプトイン） |
| **Databricks** | **GA** | 2026-05-28 | 2026-04-09 に Public Preview → 5/28 GA。**defaults / unknown 型 / ns timestamp / multi-arg transforms は明示的に非対応** |
| **Dremio** | **Preview** | — | プレスリリース（2026-04-06）は "at GA" と書くが、**docs は今も "Iceberg v3 Preview" と明記**。Cloud のみで Software 側には記述なし |

詳細は [05-engine-support.md](05-engine-support.md) を参照。

### デフォルトは依然 v2

`format-version` プロパティのデフォルトは **2**（「Defaults to 2 since version 1.4.0.」）。v3 を使うには明示的な指定/アップグレードが必要です。

---

## v4: Metadata Structure and Representation — 未採択、ただし実装は先行している

### 現況 — 「未採択」と「設定できない」は別物です

仕様本文は「**Version 4 is under active development and has not been formally adopted.**」と明記しています。**仕様としては未採択です。**

**しかし、参照実装は既に v4 を受け付けます。** ここを取り違えないでください。

| 実装 | `format-version=4` | 根拠（実測） |
|---|---|---|
| **Iceberg Java 1.10.0+**（2025-09-11〜） | **設定できる** | `TableMetadata.java`: `SUPPORTED_TABLE_FORMAT_VERSION = 4`。バリデーションは `formatVersion <= SUPPORTED_TABLE_FORMAT_VERSION` なので v4 は通過する |
| Iceberg Java 1.9.0 以前 | 設定できない | 同定数が `3` |
| **PyIceberg 0.11.1** | **設定できない** | `typedef.py`: `TableVersion = Literal[1, 2, 3]`。`metadata.py`: `SUPPORTED_TABLE_FORMAT_VERSION = 2` |

リリースタグごとの実測値:

| タグ | `SUPPORTED_TABLE_FORMAT_VERSION` |
|---|---|
| apache-iceberg-1.8.0 | 3 |
| apache-iceberg-1.9.0 | 3 |
| **apache-iceberg-1.10.0**（2025-09-11） | **4** |
| apache-iceberg-1.11.0（2026-05-19） | 4 |

さらに main の `TableMetadata.java` には **v4 機能のゲートがコードとして存在**します:

```java
static final int DEFAULT_TABLE_FORMAT_VERSION = 2;
static final int SUPPORTED_TABLE_FORMAT_VERSION = 4;
static final int MIN_FORMAT_VERSION_ROW_LINEAGE = 3;
static final int MIN_FORMAT_VERSION_PARQUET_MANIFESTS = 4;   // ← v4 機能
static final int MIN_FORMAT_VERSION_OPTIONAL_LOCATION = 4;   // ← v4 機能（相対パス）
```

関連コミット: `Core: Add basic classes for writing table format-version 4 (#13123)`（2025-06-04）、`Core, Parquet: Allow for Writing Parquet/Avro Manifests in V4 (#15634)`（2026-05-22）、`Core: v4 table metadata location should be optional (#16572)`（2026-06-01）。

**正確な言い方**: 「v4 は**仕様として未採択**だが、**Java 実装では 1.10.0 以降 `format-version=4` の設定自体は可能**。ただし仕様が流動的なため本番利用は想定されていない。**既定値は依然として 2**。

> **この区別が重要な理由**: 「未採択だから触れない」と「実装が受け付けない」は違います。前者は**あなたの判断**の問題ですが、後者は**物理的な制約**です。Java では前者しか存在しません。**仕様が固まる前の v4 テーブルを作れてしまう**ということでもあり、それはそれでリスクです。

### なぜ「公開された」と誤解されやすいか

紛らわしい材料が揃っています。

1. **仕様書に既に v4 の記述が入っている。** main の `format/spec.md` には「Version 4: Metadata Structure and Representation」という節があり、相対パス対応や `content_stats` が書かれています。**未採択のドラフトが同じファイルに同居している**状態です。
2. **参照実装に v4 の足場が入り始めた。** 1.11.0（2026-05-19）に「Introduce foundational types for V4 manifest support」「Introduce classes for content stats」が入っています。**コードが入った ≠ 仕様が採択された**。
3. **Iceberg Summit 2026 で大きく取り上げられた。** Adaptive Metadata Tree、single-file commit、column families、拡張可能な列統計といった提案が語られ、ブログが大量に出ました。**提案の議論 ≠ 採択**。
4. **v3 の「GA」ラッシュと混ざりやすい。**

### 公式マイルストーンの実態

[Iceberg V4 Spec マイルストーン #58](https://github.com/apache/iceberg/milestone/58) に載っているのは**2件だけ**（Open 2 / Closed 0、**期日なし**）:

1. **Column Stats Improvements**（#13153、2025-05-26）
2. **Relative Path Support In Table Spec**（#13141、2025-05-23）

**Summit やブログで語られる Adaptive Metadata Trees・column families・single-file commits は、公式マイルストーン上にはまだ存在しません。**

### 仕様に現時点で書かれている v4 の内容

- **相対パス（relative locations）**: 「enabling tables to be **relocated without rewriting metadata files**」。table metadata の `location` が **optional** 化。
- **`content_stats`（型付き列統計）**: v3 までの `map<int, binary>` 形式を**型付きの構造体**に置き換え。新規メトリクスとして **`tight_bounds`**（true なら bounds が実際の min/max と厳密一致）と **`avg_value_size_in_bytes`**。
- **File System Tables 方式の削除**: 「will be removed in version 4 of this spec」

### 実務上の結論

**v4 を前提にした設計判断は時期尚早です。** 公式マイルストーンは2提案のみ、期日なし。ブログ等で語られるタイムライン（2027年前後）は**公式には裏取りできません**。

**ただし「作れないから安全」ではありません。** 上記のとおり Iceberg Java 1.10.0+ は `format-version=4` を受け付けます。**仕様が採択前に変更されれば、作ってしまった v4 テーブルが読めなくなりかねません。** 明示的に避ける判断が必要です。

ただし、v4 の方向性は業界動向として重要です。**Databricks が Delta 5.0 に Iceberg v4 の adaptive metadata tree 構造を採用する提案を公式ブログで出しています** → [07-ecosystem.md](07-ecosystem.md)。

---

## 実務者向けサマリ

1. **デフォルトは v2 + copy-on-write。** v3 の恩恵（DV、row lineage 等）を得るには**明示的なアップグレードと設定変更の両方**が必要です。v3 にしただけでは DV は使われません。

2. **v3 で position delete file は事実上終了。** v3 テーブルへの新規追加は**禁止**。v2 から上げた場合、既存 position delete file は有効ですが、対象データファイルの DV を作る際に**マージが必須**です。

3. **row lineage は v3 で必須かつ後付け不可。** アップグレード前のスナップショットには row ID が無く `_row_id` は null。**CDC 目的なら、equality delete を使うエンジン（Flink upsert 等）では追跡されない**点が最大の制約です。

4. **v4 は仕様未採択だが、Java 実装は受け付ける。** 公式マイルストーンは2提案のみ。**Iceberg Java 1.10.0+ で `format-version=4` は設定でき、PyIceberg では設定できません。**「未採択」と「設定不可」を取り違えないこと。v4 前提の計画は時期尚早ですが、理由は「作れない」ではなく「**仕様が変わりうる**」です。

5. **File System Tables（HDFS の atomic rename 方式）は使わない。** 仕様が deprecated + 「オブジェクトストアとローカルファイルシステムでは **unsafe**」+ v4 で削除予定と宣言しています。

6. **統計は「あれば速くなる」もので、正しさには不要。** Puffin の theta sketch（NDV）もパーティション統計も informational です。

---

## 出典

- Iceberg Table Spec: https://iceberg.apache.org/spec/ / 生ソース https://github.com/apache/iceberg/blob/main/format/spec.md
- Appendix E（バージョン差分）: https://iceberg.apache.org/spec/#appendix-e-format-version-changes
- Puffin Spec: https://iceberg.apache.org/puffin-spec/
- 公式リリースノート: https://iceberg.apache.org/releases/ / https://github.com/apache/iceberg/blob/main/site/docs/releases.md
- Configuration（CoW/MoR、format-version 既定値）: https://github.com/apache/iceberg/blob/main/docs/docs/configuration.md
- Iceberg V4 Spec マイルストーン: https://github.com/apache/iceberg/milestone/58
- Snowflake Iceberg v3 GA（2026-05-07）: https://docs.snowflake.com/en/release-notes/2026/other/2026-05-07-iceberg-v3-ga
- Databricks Iceberg v3 GA（2026-05-28）: https://www.databricks.com/blog/unity-catalog-and-next-era-apache-icebergtm
- Iceberg Summit 2026 recap（v4、二次情報）: https://www.snowflake.com/en/blog/engineering/iceberg-summit-2026-recap-v4-spec/
