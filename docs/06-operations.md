# 06. 運用・メンテナンス・性能

**調査基準日: 2026-07-17** / **Iceberg 1.11.0 基準。プロパティ名・デフォルト値・シグネチャはすべて `main` の原文から逐語確認**

---

## 公式の分類: "Recommended" と "Optional"

**最初にこれを知ってください。一般的な認識と逆です。**

`maintenance.md` の分類:

| 分類 | 作業 |
|---|---|
| **Recommended Maintenance** | **Expire Snapshots** / **Remove old metadata files** / **Delete orphan files** |
| **Optional Maintenance** | **Compact data files** / **Rewrite manifests** |

**公式は compaction を「オプション」、スナップショット期限切れと metadata 掃除を「推奨（必須級）」に位置づけています。**

そしてこの因果関係が決定的です（`maintenance.md` の `!!! info`）:

> **データファイルは、タイムトラベルやロールバックに使われうるスナップショットから参照されなくなるまで削除されない。定期的なスナップショット期限切れが未使用データファイルを削除する。**

→ **`expire_snapshots` を回さない限り、compaction は容量を一切解放しません。むしろ増えます**（新しいファイルを書いた上で、古いファイルもスナップショットに参照されたまま残るため）。運用上もっとも誤解されやすい点です。

---

## A. メンテナンス作業

### A-1. compaction / `rewrite_data_files`

**なぜ必要か**（公式の理由）: 「Iceberg はテーブル内の各データファイルを追跡する。データファイルが増えるほど manifest に格納されるメタデータが増え、小さなデータファイルは**ファイルオープンコストにより不要な量のメタデータと非効率なクエリ**を引き起こす」

**シグネチャ**:

| 引数 | 必須 | 型 | 説明 |
|---|---|---|---|
| `table` | ✔ | string | |
| `strategy` | | string | `binpack` または `sort`。**デフォルトは binpack** |
| `sort_order` | | string | Zorder は `zorder(c1,c2,c3)` 形式。それ以外は `(ColumnName SortDirection NullOrder)` のカンマ区切り |
| `options` | | map<string,string> | |
| `where` | | string | **フィルタに合致するデータを含みうる全ファイルが書き換え対象に選ばれる**点に注意 |

**3戦略の違い**:

- **bin-pack**（デフォルト）: 小ファイルを結合し、大ファイルは分割する。**行の並べ替えを伴わない**ため最も安価。
- **sort**: 指定した sort order で全データをソートして書き直す。専用オプション `compression-factor`（既定 1.0）、`shuffle-partitions-per-file`（既定 1）。
- **z-order**: `strategy => 'sort'` かつ `sort_order => 'zorder(c1,c2)'` として指定します（**独立した strategy 名ではありません**。実装上重要）。専用オプション `var-length-contribution`（既定 8）、`max-output-size`（既定 2147483647）。

**主要オプションとデフォルト値**:

| オプション | デフォルト | 意味 |
|---|---|---|
| `target-file-size-bytes` | 536870912（512MB） | `write.target-file-size-bytes` の既定値 |
| **`min-file-size-bytes`** | **目標サイズの 75%** | これ未満は他条件に関わらず書き換え候補 |
| **`max-file-size-bytes`** | **目標サイズの 180%** | これ超過は他条件に関わらず書き換え候補 |
| `min-input-files` | 5 | この数以上のファイルを持つグループは書き換え（最低2ファイル必要） |
| `max-concurrent-file-group-rewrites` | 5 | |
| `partial-progress.enabled` | false | 全体完了前に部分コミットを許可 |
| `partial-progress.max-commits` | 10 | |
| `partial-progress.max-failed-commits` | `max-commits` の値 | |
| `use-starting-sequence-number` | true | |
| `rewrite-job-order` | none | `bytes-asc`/`bytes-desc`/`files-asc`/`files-desc`/`none` |
| `rewrite-all` | false | 全ファイル強制書き換え |
| `max-file-group-size-bytes` | 107374182400（100GB） | 巨大パーティションをリソース制約内で分割処理するため |
| `delete-file-threshold` | 2147483647 | |
| `delete-ratio-threshold` | 0.3 | |
| `output-spec-id` | 現在の spec id | |
| `remove-dangling-deletes` | false | **追加コミットが1回発生** |
| `max-files-to-rewrite` | null | |

> **`min-file-size-bytes`=75% / `max-file-size-bytes`=180% は、実質的に「384MB〜922MB の範囲外のファイルは書き換え候補」という公式のヒステリシス帯**を意味します。**これが「望ましいファイルサイズ帯」について公式から導ける最も具体的な指針です。**

`remove-dangling-deletes` の公式注記: dangling delete はデータシーケンス番号のみに基づいて削除され、**グローバル equality delete、無効な equality delete、生存データファイルに合致しなくなった position delete を含む position delete ファイルには適用されません**。

### A-2. `rewrite_manifests`

**compaction とは目的が異なります。** これはデータではなく**インデックスの再編成**です。

> Iceberg は manifest list と manifest 内のメタデータを使ってクエリプランニングを高速化し、不要なデータファイルを枝刈りする。**メタデータツリーはテーブルのデータに対するインデックスとして機能する。**

> manifest は追加された順に自動的にコンパクションされるため、**書き込みパターンが読み取りフィルタと整合している場合**にクエリが速くなる（例: 時間範囲クエリに対する時間到着順の書き込み）。**テーブルの書き込みパターンがクエリパターンと整合しない場合**、`rewriteManifests` でメタデータを書き直してデータファイルを manifest に再グループ化できる。

→ **必要になるのは「書き込み順とクエリ述語がずれているとき」です。**

| 引数 | 必須 | 型 | 説明 |
|---|---|---|---|
| `table` | ✔ | string | |
| `use_caching` | | boolean | **既定 false**。有効化すると executor のメモリ使用量が増える |
| `spec_id` | | int | |
| `sort_by` | | array<string> | **頻繁にクエリされる transform を選ぶと不要な manifest をスキップして planning 時間を削減できる** |

公式注記: 「この procedure は対象テーブルを参照する**全てのキャッシュ済み Spark プランを無効化する**」

### A-3. `expire_snapshots`

**なぜ必要か**: 「Iceberg の各 write/update/delete/upsert/compaction は新しいスナップショットを生成し、**スナップショット分離とタイムトラベルのために古いデータとメタデータを残し続ける**」

**放置時**: 「スナップショットは expire されるまで蓄積し続ける」→ ストレージ課金の無限増加とメタデータサイズ増大。

**この procedure は、未期限のスナップショットがまだ必要としているファイルを削除することはありません。**

| 引数 | 必須 | 型 | デフォルト |
|---|---|---|---|
| `table` | ✔ | string | |
| `older_than` | | timestamp | **5日前** |
| `retain_last` | | int | **1** |
| `max_concurrent_deletes` | | int | **デフォルトではスレッドプールを使わない** |
| `stream_results` | | boolean | **大容量時の Spark driver OOM を防ぐため true 推奨** |
| `snapshot_ids` | | array of long | |
| `clean_expired_metadata` | | boolean | 参照されなくなった partition spec / schema も整理 |

> **運用上の罠**: 「**ブランチやタグから参照されているスナップショットは削除されません。** デフォルトではブランチとタグは決して expire しませんが、`history.expire.max-ref-age-ms` で変更できます。**`main` ブランチは決して expire しません。**」
>
> → **タグを1つ付けただけで、そのスナップショットと依存ファイルが無期限に残ります。** Amazon S3 Tables ではこれがさらに深刻な挙動になります（[C-1](#c-1-amazon-s3-tables)）。

### A-4. `remove_orphan_files` ※ 最も危険な操作

**なぜ必要か**: 「Spark やその他の分散処理エンジンでは、**タスクやジョブの失敗によりテーブルメタデータから参照されないファイルが残る**ことがあり、また通常のスナップショット期限切れではファイルが不要と判断できず削除できない場合がある」

Iceberg の書き込みは「先にデータファイルを書く → 最後にメタデータをコミットする」順序なので、**コミット前に落ちたジョブが書いたデータファイルは、どのメタデータからも参照されないまま物理的に残ります。** これは設計上不可避であり、だからこそ専用の掃除機構が必要です。

**公式が明記する危険性**（逐語）:

> **書き込みが完了するのに要すると見込まれる時間より短い保持間隔で orphan ファイルを削除するのは危険である。進行中のファイルが orphan とみなされて削除されると、テーブルを破壊する可能性があるからである。デフォルトの間隔は3日である。**

> **Iceberg はどのファイルを削除すべきか判断する際にパスの文字列表現を使う。一部のファイルシステムではパスが時間とともに変化しうるが、それでも同じファイルを表す。例えば HDFS クラスタの authority を変更した場合、作成時に使われた古いパス URL はどれも現在のリスティングに現れるものと一致しない。これは RemoveOrphanFiles を実行した際にデータ損失につながる。**

**実務結論**:
- **必ず `dry_run => true` で先に確認する**（公式の最初の例がこれです）
- **`older_than` をデフォルトの3日より短くしない。** 特に長時間バッチや Flink の長時間チェックポイントがある環境では、最長書き込み時間より確実に長く取る
- **`prefix_mismatch_mode` のデフォルトは `ERROR`（例外送出）であり、これは安全側の設計です。** これを `DELETE` にするのは、スキーム/authority の不一致が本当に同一ファイルを指すと確証がある場合のみ。**安易な `DELETE` 指定はまさに上記のデータ損失シナリオそのものです**
- `gc.enabled`（既定 true）を false にすると GC 操作自体が禁止されます。外部でファイルを共有している場合の防御策になります

| 引数 | デフォルト | 説明 |
|---|---|---|
| `older_than` | **3日前** | |
| `dry_run` | **false** | |
| `location` | テーブルの location | |
| `stream_results` | | **有効時、出力は最大 20,000 パスのサンプルを含む** |
| `equal_schemes` | **`map('s3a,s3n','s3')`** | 等価とみなすスキーム |
| `equal_authorities` | | |
| **`prefix_mismatch_mode`** | **ERROR** | ERROR（例外）/ IGNORE / DELETE |
| `prefix_listing` | false | |

**1.11.0 の関連改善**: 「Unique table locations（新カタログプロパティによりテーブルストレージパスに UUID を付与）は、**`DeleteOrphanFiles` がリネームされたテーブルのファイルを削除しうるデータ損失シナリオを防ぐ**」— orphan 削除のデータ損失リスクが実在の問題として認識され、構造的に対処された証左です。

### A-5. `rewrite_position_delete_files` と v3 deletion vector

**2つの目的**:
- **Minor Compaction**: 小さな position delete ファイルを大きなものに結合
- **Remove Dangling Deletes**: 「`rewrite_data_files` の後、書き換えられたデータファイルを指す position delete レコードは常に削除対象としてマークされるとは限らず、テーブルの生存スナップショットメタデータに追跡され続けることがある。**これが 'dangling delete' 問題として知られる**」

オプションは `rewrite_data_files` とほぼ同じですが、**`target-file-size-bytes` の既定が 67108864（64MB）**（データファイルの 512MB ではない）。

#### v3 でどう変わるか

[02-table-spec.md](02-table-spec.md#dv-が改善したこと) で見た通り、v3 では:
- position delete ファイルの新規追加が**禁止**
- 「1データファイル = 高々1つの DV」が spec レベルで保証
- DV は既存 position delete を置き換える

→ **`rewrite_position_delete_files` の存在意義が構造的に縮小します。** 小さな delete ファイルが際限なく積み上がるという v2 の主要な病理が消え、「minor compaction」の対象そのものが生まれません。

**ただし完全には消えません**:
1. **Puffin ファイル自体の書き直しは spec 上不要**なので、「参照されない DV blob を含む Puffin ファイル」が残りえます → `remove_orphan_files` の領分
2. **v2 テーブルには依然として必要**です。v2→v3 アップグレード後も既存の position delete ファイルは有効なまま残るため、移行期は両方の考慮が必要

> **【未確認】**: v3 の DV に対する専用の compaction procedure（DV 版 `rewrite_position_delete_files` に相当）は `spark-procedures.md` に**見つかりませんでした**。`rewrite_data_files` の `remove-dangling-deletes` は「position and equality deletes」を対象とする記述で、DV に対する挙動は docs から読み取れません。

### A-6. 古い metadata ファイルの削除 — 後戻りできない設定

**これは公式分類で "Recommended" です。**

> 各 metadata ファイルは `metadata-log` フィールドで古い metadata ファイルを追跡する。追跡される metadata ファイル数は `write.metadata.previous-versions-max` で定義される。

> `write.metadata.delete-after-commit.enabled=true` を設定すると、**追跡されている（tracked）** metadata ファイルを保持しつつ、新しいものが作られるたびに最古のものを削除する。**これは metadata log に追跡されている metadata ファイルのみを削除し、orphan 化した metadata ファイルは削除しない。**

**公式の具体例が罠の本質を示しています**（逐語）:

> `write.metadata.delete-after-commit.enabled=false` かつ `write.metadata.previous-versions-max=10` で100コミット後、**10個の tracked metadata ファイルと 90個の orphaned metadata ファイル**を持つことになる。**これら90個の orphaned metadata ファイルは、後から `write.metadata.delete-after-commit.enabled=true` に設定しても削除できない。既に untracked だからである。orphan file deletion procedure でしかクリーンできない。**

→ **`write.metadata.delete-after-commit.enabled` は既定 false であり、テーブル作成時に有効化しておかないと後戻りできません。** ストリーミング/高頻度コミットのテーブルでは作成時点で必ず有効化してください。既に肥大したテーブルでは `remove_orphan_files`（= A-4 の危険な操作）が唯一の手段になります。

---

## B. 重要なテーブルプロパティ

すべて `docs/docs/configuration.md`（main）から逐語確認。

### Write properties

| プロパティ | デフォルト | 説明 |
|---|---|---|
| `write.format.default` | `parquet` | parquet / avro / orc |
| **`write.target-file-size-bytes`** | **536870912（512MB）** | |
| `write.delete.target-file-size-bytes` | **67108864（64MB）** | |
| `write.parquet.row-group-size-bytes` | 134217728（128MB） | |
| **`write.parquet.compression-codec`** | **`zstd`** | zstd / brotli / lz4 / gzip / snappy / uncompressed |
| **`write.distribution-mode`** | **未設定**（エンジン依存） | `none` / `hash` / `range` |
| `write.delete.distribution-mode` 等 | 未設定 | delete/update/merge 用に**独立に存在** |
| **`write.metadata.metrics.default`** | **`truncate(16)`** | none / counts / truncate(length) / full |
| **`write.metadata.metrics.max-inferred-column-defaults`** | **100** | **メトリクスを収集する最大列数** |
| **`write.metadata.delete-after-commit.enabled`** | **false** | ← A-6 参照 |
| `write.metadata.previous-versions-max` | 100 | |
| `write.object-storage.enabled` | false | ファイルパスにハッシュ要素を加える |
| **`write.delete.mode`** / `write.update.mode` / `write.merge.mode` | **`copy-on-write`** | v2 以降で merge-on-read 可 |
| `write.*.isolation-level` | serializable | serializable / snapshot |
| `write.delete.granularity` | partition | partition / file |
| `write.spark.fanout.enabled` | false | **メモリ使用量が増える** |

**metrics モードの定義**:
- `none`: 永続化しない
- `counts`: カウントのみ
- `truncate(length)`: カウント + 切り詰めた境界値。**切り詰めは string と binary にのみ適用**
- `full`: 完全な境界値

### Table behavior properties

| プロパティ | デフォルト |
|---|---|
| `commit.retry.num-retries` | **4** |
| `commit.retry.min-wait-ms` | 100 |
| `commit.retry.max-wait-ms` | 60000（1分） |
| `commit.retry.total-timeout-ms` | **1800000（30分）** |
| `commit.status-check.num-retries` | 3 |
| `commit.manifest.target-size-bytes` | 8388608（8MB） |
| `commit.manifest.min-count-to-merge` | 100 |
| `commit.manifest-merge.enabled` | true |
| `history.expire.max-snapshot-age-ms` | **432000000（5日）** |
| `history.expire.min-snapshots-to-keep` | 1 |
| `history.expire.max-ref-age-ms` | **`Long.MAX_VALUE`（無期限）**。**`main` は決して expire しない** |
| `gc.enabled` | true |

### Read properties

| プロパティ | デフォルト |
|---|---|
| `format-version` | **2**（1.4.0 以降） |
| `read.split.target-size` | 134217728（128MB） |
| `read.split.open-file-cost` | 4194304（4MB） |
| `read.parquet.vectorization.enabled` | true |
| `read.orc.vectorization.enabled` | **false** |

> **矛盾の指摘**: `configuration.md` は `write.distribution-mode` を「not set, see engines for specific defaults」とする一方、`spark-writes.md` は「**Iceberg 1.2.0 以降、`hash` が新しいデフォルト**」と記述します。
>
> これは矛盾ではなく**階層の違い**です — テーブルプロパティとしては未設定で、**Spark エンジンが実行時に hash を要求する**という構造です。したがって**他エンジン（Flink 等）では挙動が異なりえます**。また「**Spark は 3.5.0 より前では CTAS/RTAS で distribution mode を尊重しない**」という重要な例外も明記されています。

---

## C. アンチパターン（仕様レベルの発生機序）

### 1. Over-partitioning

**なぜ小ファイルが生まれるのか（仕様上の根拠）**:

`spark-writes.md` が明記する通り「**ファイルは Iceberg のパーティション境界をまたげない**（a file cannot span an Iceberg partition boundary）」— これが over-partitioning が**必ず**小ファイルを生む理由です。パーティションを細かくすると、各パーティションのデータ量が 512MB を大きく下回り、パーティション境界がそのままファイル境界になります。

さらに `write.distribution-mode=hash`（Spark 既定）ではパーティション値でハッシュ分散されるため、パーティション数が多いほどタスクあたりのデータが薄くなり、**1パーティション×1タスクごとに小ファイルが1つ**生まれます。

> **公式な「パーティションあたり推奨サイズ」の数値は、`partitioning.md`・`performance.md`・`configuration.md` を確認した範囲で見つかりませんでした（未確認）。** 「1パーティション最低1GB」等の一般に流布する目安には公式の裏付けが確認できません。

### 2. 高頻度小コミットによるメタデータ肥大

**なぜ起きるか**: 「**Iceberg はテーブルメタデータを JSON ファイルで追跡する。テーブルへの各変更は、原子性を提供するために新しい metadata ファイルを生成する**」

つまり**コミット1回 = metadata JSON 1個 + スナップショット1個 + manifest list 1個**が確定的に生成されます。これは最適化ではなく**原子性のための構造的要件**です。

`write.metadata.delete-after-commit.enabled` が既定 false なので、**何も設定しなければ metadata JSON は無限に蓄積し、`previous-versions-max=100` を超えた分は untracked（＝後から自動削除不能）になります**（A-6）。

緩和策の `commit.manifest-merge.enabled`（既定 true）は manifest レベルの話であり、metadata JSON とスナップショットの蓄積は別途対処が必要です。

### 3. 複数ライタ競合と commit retry

**なぜ起きるか**: [01-architecture.md](01-architecture.md#acid-と楽観的並行制御) の通り、Iceberg は**楽観的並行制御**です。コミットは「現在のスナップショットを読む → 新スナップショットを作る → アトミックにスワップ」という CAS 的操作で、他のライタが先にスワップすると失敗し `commit.retry.*` に従いリトライします（既定4回、100ms〜60秒のバックオフ、合計30分）。

**実務上の帰結: compaction ジョブ自体が最も競合を起こしやすいライタです。** 大きなパーティションを書き換える compaction は長時間データファイルを保持し、その間の並行書き込みと衝突します。

対策:
- `partial-progress.enabled=true` + `partial-progress.max-commits` で小さく刻んでコミットし、1コミットあたりの競合窓を狭める
- `max-file-group-size-bytes`（既定 100GB）を下げ、`where` 句で書き込みが起きていないパーティションに限定する

`write.*.isolation-level` を `serializable` から `snapshot` に下げると競合検出が緩和されますが、**これは分離レベルを落とす判断**であり、正しさへの影響を理解した上でのみ行ってください。

### 4. Orphan files

2つの独立した機序があります:
- **タスク/ジョブ失敗**: 書き込み順序（データ先、メタデータ後）から構造的に不可避（A-4）
- **untracked metadata**: `previous-versions-max` を溢れた metadata JSON（A-6）

### 5. メタデータ JSON 肥大

上記 2 と 4 の合流点です。**設計時に決めるべき設定であり、運用開始後の是正はコストが高い**（唯一の手段が A-4 の危険な操作）というのが結論です。

---

## D. 性能

### D-1. 多段プルーニングと劣化条件

プルーニングの仕組み自体は [01-architecture.md](01-architecture.md#クエリプランニングの多段プルーニング) を参照してください。ここでは**劣化する条件**を扱います。

`performance.md`: 「プランニング時に上限・下限でデータファイルをフィルタすることにより、Iceberg はクラスタ化されたデータを使ってタスクを実行せずにスプリットを排除する。**場合によってはこれは10倍の性能改善になる**」（出典: [Strata NY 2018](https://conferences.oreilly.com/strata/strata-ny-2018/cdn.oreillystatic.com/en/assets/1/event/278/Introducing%20Iceberg_%20Tables%20designed%20for%20object%20stores%20Presentation.pdf)）

#### 劣化条件（仕様から導かれるもの）

1. **`field_summary` の範囲が広がる（段1の失効）**: manifest 内のデータファイルが多数のパーティション値にまたがると lower/upper bound が広範囲になり、どの述語にも「合致しうる」と判定されて manifest スキップが効かなくなります。**これがまさに `rewrite_manifests` の `sort_by` が対処する問題**です。書き込み順とクエリ述語がずれているテーブルで発生します。

2. **列メトリクスが存在しない（段3の失効）**: **`write.metadata.metrics.max-inferred-column-defaults` が 100 なので、101列目以降の列にはデフォルトでメトリクスが収集されません**（pre-order 走査順）。ワイドテーブルで後方の列に述語をかけても bounds プルーニングが効かず全ファイル読み込みになります。`write.metadata.metrics.column.<col>` で個別指定が必要です。

3. **`truncate(16)` による境界値の粗さ**: デフォルトは string/binary の境界値を16文字で切り詰めます。**長い共通プレフィックスを持つ文字列列（URL、UUID 文字列等）では境界値が実質同一になり、プルーニングが効きません。**

4. **未知の partition transform**: inclusive projection が `true` になるため、そのフィールドでの枝刈りが完全に無効化されます。

5. **小ファイル大量発生**: manifest エントリ数に比例してプランニングコストが増大します。

### D-2. メタデータ肥大とサーバサイド scan planning

`performance.md` の設計目標は「**マルチペタバイトのテーブルでも、テーブルメタデータをふるいにかける分散 SQL エンジンを必要とせず、単一ノードから読める**」です。

しかしこの前提は**メタデータが単一ノードのメモリ・I/O 帯域に収まる限り**で成立します。スナップショットが expire されず manifest が肥大すると前提が崩れ、Spark driver が全 manifest を読む際のボトルネック（および OOM）になります。

**`expire_snapshots` / `remove_orphan_files` の `stream_results` オプションが「Spark driver の OOM を防ぐため true 推奨」と明記されているのは、この問題が実在することの公式な証左です。**

**server-side scan planning はこれへのプロトコルレベルの解**です。仕様・実装ともに存在します（[03-rest-catalog.md](03-rest-catalog.md#7-サーバサイド-scan-planning) 参照）:
- 仕様: 1.7.0（2024-11-08、PR #9695）
- 実装: **1.11.0（2026-05-19、PR #13400 + Spark 統合 #14963）**

1.11.0 リリースブログ:
> **以前は、全てのクライアントがどのファイルを読むか判断するために manifest list と manifest を自分で取得しなければならなかった。server-side planning により、クライアントは関連する scan task のみを受け取り、driver のメモリ圧迫を軽減し、クエリエンジンに透過的なサーバサイド最適化を可能にする。**

ただし**カタログサーバ側の実装が必須**であり、その最適化の質はカタログ実装に依存します。

> **【未確認】**: Spark/Flink 等の各エンジン統合層がどのバージョンで remote scan planning を実際に使うようになるかについて、公式 docs 上の明確な記述は確認できませんでした。「Spark（Iceberg 1.11+）が Scan API をサポート」とする第三者ブログがありますが、**公式 docs で裏付けが取れなかったため採用しません**。

### D-3. ファイルサイズの指針（出典のある数値のみ）

| 数値 | 値 | 出典 |
|---|---|---|
| データファイル目標サイズ | **512MB** | `write.target-file-size-bytes` 既定 |
| delete ファイル目標サイズ | **64MB** | `write.delete.target-file-size-bytes` 既定 |
| Parquet row group | 128MB | `write.parquet.row-group-size-bytes` 既定 |
| 読み取りスプリット目標 | 128MB | `read.split.target-size` 既定 |
| ファイルオープン推定コスト | 4MB | `read.split.open-file-cost` 既定 |
| **compaction 書き換え下限** | **目標サイズの 75%** | `min-file-size-bytes` 既定 |
| **compaction 書き換え上限** | **目標サイズの 180%** | `max-file-size-bytes` 既定 |
| compaction 発火ファイル数 | 5 | `min-input-files` 既定 |
| manifest マージ目標サイズ | 8MB | `commit.manifest.target-size-bytes` 既定 |
| manifest マージ発火数 | 100 | `commit.manifest.min-count-to-merge` 既定 |
| compaction 例での明示値 | 500MB | `maintenance.md` の Java 例 |
| S3 Tables compaction 目標 | 512MB（設定範囲 64–512MB） | AWS S3 Tables docs |

#### 公式な推奨値が「存在しない」もの（未確認）

以下は `partitioning.md`、`performance.md`、`configuration.md` を確認しましたが**見つかりませんでした**:
- **1パーティションあたりの推奨データ量**
- **1テーブルあたりの推奨パーティション数上限**
- **manifest あたりの推奨エントリ数**
- **スナップショット保持数の推奨値**（デフォルト以外）

**出典のない数値目安を書かないため、ここは正直に「公式な推奨値は見つからなかった」と記します。** 代わりに使える公式由来の指針は上記の**「384MB〜922MB のヒステリシス帯」**です。

#### Spark 固有の重要な制約

`spark-writes.md`（逐語）:

> Spark で Iceberg にデータを書く際、**Spark は Spark タスクより大きいファイルを書けず、ファイルは Iceberg のパーティション境界をまたげない**点に注意することが重要である。これは、Iceberg は常に `write.target-file-size-bytes` に成長した時点でファイルをロールオーバーするが、**Spark タスクが十分に大きくない限りそれは起こらない**ことを意味する。**ディスク上に作られるファイルサイズは Spark タスクよりずっと小さくなる。**

→ **`write.target-file-size-bytes` は「上限（ロールオーバー閾値）」であって「保証値」ではありません。** 512MB に設定しても、Spark タスクが小さければ小さいファイルしかできません。**設定だけで解決しない、実務で最も頻繁に踏まれる誤解です。**

### D-4. `write.distribution-mode` の選択

**設計上の背景**（`spark-writes.md` 逐語）:

> Iceberg のデフォルト Spark writer は、**各 Spark タスク内のデータがパーティション値でクラスタ化されていることを要求する。この分散は、書き込み中に開いたまま保持されるファイルハンドルの数を最小化するために必要である。** Iceberg 1.2.0 以降、デフォルトで Iceberg は Spark にこの分散に合うようデータを事前ソートすることも要求する。

| モード | シャッフル | ファイル数への影響 | コスト | 位置づけ |
|---|---|---|---|---|
| `none` | なし | **最悪**。手動ソートしないとタスク×パーティションの組み合わせ数だけファイルが生成される | 最安 | 「Iceberg の**以前の**デフォルト」 |
| `hash` | ハッシュ交換 | 良好。1パーティションのデータが特定タスクに集約 | 中 | 「**新しいデフォルト**」（1.2.0〜） |
| `range` | レンジ交換（2段階） | 良好 + グローバルソート | **最高** | 「**テーブルが sort-order 付きで作られた場合にデフォルトで使われる**」 |

**実務判断のポイント**:

1. **`none` は「速い」のではなく「Spark に仕事をさせない」だけです。** データが既にパーティション値でクラスタ化されている場合にのみ最適。そうでなければ**小ファイルの温床**になり、**シャッフルコストを払わないぶん、compaction で払う**ことになります。

2. **`none` + fanout writer の罠**: 「ソートは `write.spark.fanout.enabled` で回避できるが、**これは各書き込みタスクが完了するまで全ファイルハンドルが開いたままになる**」。**「ソートを避ける」代償はメモリです。** パーティション数が多いと executor の OOM に直結します。

3. **`range` は sort-order 付きテーブルの暗黙のデフォルト**。「より高価だが、ソート列がクエリで使われる場合、グローバル順序は読み取り性能に有益になりうる」。**D-1 の段3（列 bounds プルーニング）を効かせたいなら、書き込みコストを払って読み取りの枝刈り効率を買う取引**です。

4. **AQE との相互作用**: `hash` と `range` の両方で「**Spark の Adaptive Query planning によりタスクのさらなる分割と結合が起こりうる**」。distribution-mode だけでファイル数は決まりません。

5. **delete/update/merge には別プロパティ**が独立に存在し、**すべて既定未設定**です。MoR で delete を多用する場合、これらが未設定のままだと delete ファイルの分散が制御されません。

### D-5. MoR と CoW のトレードオフ

| 観点 | CoW（デフォルト） | MoR（v2 position delete） | MoR（v3 deletion vector） |
|---|---|---|---|
| 書き込みコスト | **高**。ファイル全体を書き直す | **低**。delete ファイルを追加するだけ | **低**。DV を書くだけ |
| 読み取りコスト | **ゼロ** | **高**。合致する delete ファイル群を読みマージ | **中**。1データファイルにつき高々1つなので照合対象が確定的 |
| メタデータ増加 | スナップショット分のみ | **delete ファイルが際限なく蓄積**しうる | **蓄積しない**（1:1 の上限が spec で保証） |
| 追加メンテナンス | compaction のみ | **`rewrite_position_delete_files` が事実上必須** | 構造的に不要 |
| dangling delete | なし | **あり** | 緩和（ただし Puffin は残りうる） |

**equality delete が最も危険**: 「delete ファイルの partition spec が unpartitioned」の場合にも適用対象になるため、**グローバル equality delete は全データファイルに対して照合が必要**になります。MoR の最悪ケースです。しかも `remove-dangling-deletes` は公式注記の通り**グローバル equality delete には適用されない**ため、自動的な掃除も効きません。

**DV の最大の改善は「不変条件による予測可能性」**です。v2 では読み取りコストが「これまで何回 delete したか」に依存して**単調悪化**しました。v3 ではこれが構造的に不可能になります。定量的改善ではなく**漸近的な性質の変化**です → [02-table-spec.md](02-table-spec.md#dv-が改善したこと)

**v3 採用の前提**: `format-version` の既定は 2 のままで、**v3 にしても `write.delete.mode` の既定が CoW なので DV は自動では使われません。** エンジン側の v3 対応も前提です → [05-engine-support.md](05-engine-support.md)

---

## E. マネージドサービスの自動メンテナンス

### C-1. Amazon S3 Tables

「以下のオプションは**テーブルバケット内の全テーブルでデフォルトで有効**である」

| 操作 | プロパティ | バケット単位 | テーブル単位 | **デフォルト** | 最小 |
|---|---|---|---|---|---|
| Compaction | `targetFileSizeMB` | 不可 | 可 | **512MB** | 64MB |
| Snapshot management | `minimumSnapshots` | 不可 | 可 | **1** | 1 |
| Snapshot management | `maximumSnapshotAge` | 不可 | 可 | **120時間（5日）** | 1時間 |
| Unreferenced file removal | `unreferencedDays` | **可** | 不可 | **3日** | 1日 |
| Unreferenced file removal | `nonCurrentDays` | **可** | 不可 | **10日** | 1日 |

**compaction 戦略**（4種）: Auto（既定。sort order があれば `sort`、なければ `binpack`）/ Binpack / Sort / Z-order。「**`z-order` と `sort` は `binpack` より高いコストを発生させうる**」

「compaction はオブジェクトを結合する際、**テーブルの行レベル delete の効果も適用する**」

#### ※ 最重要の落とし穴: Snapshot management が fail-closed する

公式逐語:

> Snapshot management は、`metadata.json` ファイルまたは `ALTER TABLE SET TBLPROPERTIES` で設定した retention 値を**サポートしない**。以下のいずれかの条件が存在する場合、**snapshot management はテーブル全体で失敗し、Amazon S3 はスナップショットを一切 expire も削除もしない**:
>
> - **ユーザー定義のタグまたはブランチ** — テーブルにユーザー定義のタグやブランチが存在する場合、snapshot management はテーブル全体で失敗する。**これは、そのタグやブランチの retention 期間が短くても適用される。**
> - **Iceberg snapshot retention テーブルプロパティ** — `history.expire.max-snapshot-age-ms` または `history.expire.min-snapshots-to-keep` がテーブルプロパティとして設定されている場合、**設定値に関わらず** snapshot management はテーブル全体で失敗する。

**これは極めて重大です。** Iceberg のベストプラクティスに従って `history.expire.*` を設定する、あるいはリリースタグを打つといった**ごく自然な運用が、自動メンテナンスをサイレントに全面停止させます。** しかも失敗は**ストレージ課金の増加としてしか現れません**。

→ **[`GetTableMaintenanceJobStatus`](https://docs.aws.amazon.com/AmazonS3/latest/API/API_s3Buckets_GetTableMaintenanceJobStatus.html) API による能動的な監視が必須**です（失敗時は `FAILED` ステータスと原因メッセージが返ります）。CloudTrail でも追跡可能です。

#### その他の制約

- **削除は復旧不能**: 「**noncurrent オブジェクトの削除は永久的で、これらのオブジェクトを復旧する方法はない**」「閲覧・復旧には **AWS Support への問い合わせが必要**」
- **外部参照は保護にならない**: 「**テーブル外部からのこれらオブジェクトへの参照は、snapshot management による削除を妨げない**」
- **形式・型の制約**: compaction は Parquet/Avro/ORC 対応だが**既定で Parquet を書く**。**データ型 `Fixed` 非対応**。**圧縮 `brotli`、`lz4` 非対応**。**Parquet の row-group サイズ 128MB が強制される**
- **楽観的並行の競合は消えない**: 「楽観的並行では、**ユーザーと compaction のトランザクションが競合してトランザクションが失敗しうる**」「compaction ジョブは失敗時にリトライする。**パイプライン側でもリトライロジックを使うことを推奨する**」
- **【未確認】** `rewrite_manifests` に相当する自動操作は、確認した範囲の docs に存在しません。提供されるのは3種のみです。D-1 の manifest レイアウト起因の劣化は S3 Tables では自動的に解決されません

### C-2. Databricks Predictive Optimization

**自動実行**: OPTIMIZE / VACUUM / ANALYZE
**対象**: **Unity Catalog managed tables（Delta Lake および Iceberg）**

**限界**（公式に「サポートしない」と記載）:
- **外部テーブル** — 対象外
- **OpenSharing recipient としてロードされたテーブル** — 対象外
- **「Predictive Optimization が実行する OPTIMIZE は ZORDER 操作を実行しない」** — S3 Tables が z-order 戦略を提供するのと対照的

**保持期間**: VACUUM は `delta.deletedFileRetentionDuration` を尊重し、**既定の窓は7日**。

**有効化**: Premium プラン以上。「**2024年11月11日以降に作成されたアカウントではデフォルトで有効**」。既存アカウントへの段階的ロールアウトは **2026年8月完了予定**（調査時点で進行中）。

> **【未確認】**: `delta.deletedFileRetentionDuration` は Delta Lake のプロパティです。**UC managed Iceberg テーブルに対する VACUUM の保持期間が同じプロパティで制御されるのか、Iceberg の `history.expire.*` が尊重されるのかは、参照した docs から判別できませんでした。** Iceberg テーブルを Predictive Optimization に委ねる場合、この点は事前検証が必要です。

### C-3. マネージド自動メンテナンスの共通の限界

1. **「肩代わり」されるのは compaction と GC のみで、設計判断は肩代わりされません。** パーティション設計、sort order の選択、`write.metadata.delete-after-commit.enabled` の初期設定（A-6 の後戻り不能問題）はユーザーの責任のまま残ります。S3 Tables の `sort`/`z-order` が「`sort_order` の定義が必須」であることは、この境界を明確に示しています — **サービスは実行を代行するが、何でソートすべきかは決めてくれません。**

2. **楽観的並行の競合はマネージドでも消えません。** AWS が明示的に「パイプライン側でもリトライロジックを使うことを推奨」と書く通り、これは仕様に由来する本質的性質であり、サービス層で隠蔽できません。むしろ**自動 compaction が追加のライタとして競合を増やす**側面があります。

3. **自動化と Iceberg 標準機能が衝突しうる。** S3 Tables の snapshot management が fail-closed する仕様はその最も鋭い例です。**「Iceberg のベストプラクティスに従うこと」と「マネージドサービスの自動メンテナンスを機能させること」が両立しないケースが実在します。**

4. **監視は依然として必要。** 「サイレント失敗」を検出する手段を運用に組み込まない限り、課金増加として顕在化するまで気づけません。

5. **【未確認】** `rewrite_manifests` 相当は、確認した範囲ではどちらのサービスも自動提供していません。

---

## 出典

**Apache Iceberg 公式（生ソース）**
- Spark Procedures: https://raw.githubusercontent.com/apache/iceberg/main/docs/docs/spark-procedures.md
- Configuration: https://raw.githubusercontent.com/apache/iceberg/main/docs/docs/configuration.md
- Maintenance: https://raw.githubusercontent.com/apache/iceberg/main/docs/docs/maintenance.md
- Performance: https://raw.githubusercontent.com/apache/iceberg/main/docs/docs/performance.md
- Spark Writes: https://raw.githubusercontent.com/apache/iceberg/main/docs/docs/spark-writes.md
- Table Spec: https://raw.githubusercontent.com/apache/iceberg/main/format/spec.md
- 1.11.0 リリースブログ: https://raw.githubusercontent.com/apache/iceberg/main/site/docs/blog/posts/2026-05-19-iceberg-1.11.0-release.md
- Remote scan planning: [PR #13400](https://github.com/apache/iceberg/pull/13400)

**AWS**
- [Maintenance for tables (S3 Tables)](https://docs.aws.amazon.com/AmazonS3/latest/userguide/s3-tables-maintenance.html)
- [Considerations and limitations](https://docs.aws.amazon.com/AmazonS3/latest/userguide/s3-tables-considerations.html)
- [PutTableMaintenanceConfiguration API](https://docs.aws.amazon.com/AmazonS3/latest/API/API_s3Buckets_PutTableMaintenanceConfiguration.html)

**Databricks**
- [Predictive optimization](https://docs.databricks.com/aws/en/optimizations/predictive-optimization)

**採用しなかった情報**: 「Spark（Iceberg 1.11+）が Scan API をサポート」等の第三者ブログ（Medium/Dremio、DEV Community、Substack）の記述は、公式 docs で裏付けが取れなかったため採用していません。
