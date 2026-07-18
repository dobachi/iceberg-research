# 90. 用語集

**調査基準日: 2026-07-17**

本報告書で使う用語の一覧です。各項目に**出典**を付けています。

出典の種別:

- **仕様** — [Apache Iceberg Table Spec](https://iceberg.apache.org/spec/)（生ソース: [`format/spec.md`](https://github.com/apache/iceberg/blob/main/format/spec.md)）
- **IRC 仕様** — [REST Catalog OpenAPI](https://github.com/apache/iceberg/blob/main/open-api/rest-catalog-open-api.yaml)
- **公式ドキュメント** — `iceberg.apache.org` 配下の各ドキュメント（生ソースは `apache/iceberg` の `docs/docs/`）
- **本報告書の整理** — 仕様に定義された語ではなく、本報告書が説明のために用いている表現。**引用の際は注意してください**

---

## メタデータ構造

### snapshot（スナップショット）

ある時点のテーブルの状態。そのスナップショットに属する全データファイルの集合を表します。仕様は「The data in a snapshot is the **union of all files in its manifests**」と定義しています。

**出典**: 仕様 / → [01](01-architecture.md#三層のメタデータ構造)

### metadata file（`*.metadata.json`）

テーブルの状態を記録した JSON ファイル。スキーマ、パーティション仕様、sort order、スナップショット一覧、テーブルプロパティを含みます。**カタログが保持するのは、この「現在の metadata ファイルへのポインタ」1つだけ**です。

**出典**: 仕様 / → [01](01-architecture.md#三層のメタデータ構造)

### manifest list（`snap-*.avro`）

1スナップショットにつき1つ作られる Avro ファイル。そのスナップショットに属する manifest の一覧と、各 manifest のパーティション要約統計（`field_summary`）を持ちます。

**出典**: 仕様 / → [01](01-architecture.md#三層のメタデータ構造)

### manifest（`*-m0.avro`）

データファイル（または削除ファイル）の一覧を記録した Avro ファイル。各ファイルのパーティション値と列統計を含みます。

仕様上の重要な性質が2つあります。**マニフェストはパーティションに紐づきません**（「Manifests can track data files with **any subset of a table and are not associated with partitions**」）。また**データ用と削除用は同一 manifest に混在できません**（削除ファイルはジョブプランニング時に先に読む必要があるため）。

**出典**: 仕様 / → [01](01-architecture.md#マニフェストの制約)

### Puffin

統計とインデックスを格納する blob コンテナ形式。現在2つの blob 型が定義されています（`apache-datasketches-theta-v1`、`deletion-vector-v1`）。

**出典**: [Puffin Spec](https://iceberg.apache.org/puffin-spec/) / → [01](01-architecture.md#puffin-と統計情報)

### sequence number（シーケンス番号）

コミット成功ごとに単調増加する番号。削除ファイルをどのデータファイルに適用するかの判定に使われます。v2 で導入されました。

`sequence_number`（データシーケンス番号 = 内容の相対的な古さ）と `file_sequence_number`（追加時のスナップショット番号）は別物で、仕様は「**The file sequence number can't be used for pruning delete files**」と明記しています。

**出典**: 仕様 / → [01](01-architecture.md#シーケンス番号と継承)

---

## テーブル仕様とバージョン

### format version（フォーマットバージョン）

テーブルのメタデータがどの仕様に従って書かれているかを示すバージョン。**既定は 2**（1.4.0 以降）。前方互換性が壊れる変更が入るときにだけ上がります。

**出典**: 仕様 / 公式ドキュメント（`configuration.md`）/ → [02](02-table-spec.md#最初に-バージョンの現況)

### schema evolution（スキーマ進化）

列の追加・削除・改名・型変更を、既存データファイルを書き換えずに行うこと。**列は名前ではなく field ID で解決される**ため、改名しても既存ファイルはそのまま読めます。

**出典**: 仕様 / → [02](02-table-spec.md#スキーマ進化)

### field ID

各列に割り当てられる不変の識別子。仕様は「Columns in Iceberg data files are **selected by field id**」「Renaming an existing field must change the name, **but not the field ID**」と定めています。

**出典**: 仕様 / → [02](02-table-spec.md#field-id-ベース)

### partition spec（パーティション仕様）

どの列をどの transform（`identity` / `bucket[N]` / `truncate[W]` / `year` / `month` / `day` / `hour` / `void`）でパーティションするかの定義。

**出典**: 仕様 / → [02](02-table-spec.md#partition-transform)

### partition evolution（パーティション進化）

パーティションの切り方を後から変更すること。**既存データは書き換えられず**、新旧の spec が同一テーブル内に共存します。読み取り時、各 manifest は「それを書いた時点の spec」で解釈されます。

**出典**: 仕様 / → [02](02-table-spec.md#進化の規則)

### hidden partitioning

クエリにパーティション列を書かなくてよい仕組み。エンジンが論理列への述語（`ts > X`）を inclusive projection でパーティション述語（`ts_day >= day(X)`）に自動変換します。

> **注**: 「hidden partitioning」は公式ドキュメントでも使われる呼称ですが、**仕様本文が定義する用語ではありません**。仕様が定めているのは inclusive projection の規則です。

**出典**: 公式ドキュメント / 仕様（inclusive projection）/ → [01](01-architecture.md#inclusive-projection-とは)

### inclusive projection

スキャン述語をパーティション述語に変換する規則。**ある行が元の述語を満たすなら、その行のパーティションは必ず変換後の述語を満たす**という保証を持ちます。対偶により、変換後の述語を満たさないパーティションは丸ごとスキップできます。

意図的に緩く作られており、**false positive（該当行が無いパーティションを読む）は許容、false negative（該当行があるパーティションを飛ばす）は不可**という非対称な保証です。

**出典**: 仕様 / → [01](01-architecture.md#inclusive-projection-とは)

### strict projection

inclusive projection の対。**そのファイルの全行が確実に述語を満たすときだけ**マッチする、厳しい側に倒した変換。residual predicate（読んだファイル内で行ごとに再評価すべき条件）の計算に使われます。

**出典**: 仕様 / → [01](01-architecture.md#inclusive-projection-とは)

---

## 更新と削除

### copy-on-write（CoW）

変更が及ぶデータファイルを丸ごと書き直す方式。書き込みは重いが、読み取り側は特別な処理が不要です。**`write.{delete,update,merge}.mode` の既定値**。

**出典**: 公式ドキュメント（`configuration.md`）/ → [02](02-table-spec.md#copy-on-write-と-merge-on-read)

### merge-on-read（MoR）

元のデータファイルは変更せず、「この行は削除された」という情報を別ファイルに追記する方式。書き込みは軽いが、読み取り時にマージのコストがかかります。

**出典**: 公式ドキュメント（`configuration.md`）/ → [02](02-table-spec.md#copy-on-write-と-merge-on-read)

### position delete file

「どのデータファイルの何行目を削除したか」を記録するファイル（v2 で導入）。**v3 テーブルへの新規追加は禁止**されました（既存のものは有効なまま）。

**出典**: 仕様 / → [02](02-table-spec.md#position-delete-file)

### equality delete file

「この列がこの値の行を削除する」という条件を記録するファイル（v2 で導入）。読み取り時に全データファイルと照合が必要になりえます。

**注意すべき制約が2つあります。** unpartitioned spec で書かれた equality delete は**グローバル削除**として全データファイルに適用されます。また **v3 の row lineage は equality delete では追跡されません**。

**出典**: 仕様 / → [02](02-table-spec.md#equality-delete-file)

### deletion vector（DV）

v3 で導入された削除の記録形式。単一データファイル内の削除位置を Roaring bitmap で表し、Puffin ファイルに格納します。

**スナップショット内で1データファイルにつき DV は最大1つ**という不変条件が仕様で保証されており、これが v2 の position delete（際限なく積み上がりうる）との決定的な違いです。

**出典**: 仕様 / [Puffin Spec](https://iceberg.apache.org/puffin-spec/) / → [02](02-table-spec.md#deletion-vector-dv)

### row lineage

v3 で導入された行の来歴追跡。`_row_id` と `_last_updated_sequence_number` の2フィールドを持ちます。**v3 では必須で、オプトインではありません。**

**出典**: 仕様 / → [02](02-table-spec.md#row-lineage)

---

## トランザクションと並行制御

### 楽観的並行制御（OCC: Optimistic Concurrency Control）

ロックを取らず、「他の書き手が先に変更していないこと」をコミット時に検証する方式。競合したら、負けた側が最新の状態を土台に載せ直してリトライします。

**出典**: 仕様（「Writers create table metadata files **optimistically**」）/ → [01](01-architecture.md#acid-と楽観的並行制御)

### atomic swap / check-and-put

コミットの実体。新しい metadata ファイルを書いたうえで、カタログに対し「現在が期待どおりなら、これに差し替えて」と要求する操作です。

> **注**: 仕様は commit の atomic 操作そのものを標準化していません（「The atomic operation used to commit metadata depends on how tables are tracked and **is not standardized by this spec**」）。**カタログ実装に依存します。**

**出典**: 仕様 / → [01](01-architecture.md#コミットの実装)

### snapshot-log

「いつ、どのスナップショットが current になったか」を時刻つきで並べた時系列のログ。**時刻指定のタイムトラベルはこれを使わないと正しく答えられません**（親子系譜とは別物で、ロールバック時に両者は食い違います）。

**出典**: 仕様 / → [01](01-architecture.md#タイムトラベルと2つの履歴)

### branch / tag

スナップショットを指す名前つきの参照（snapshot reference）。**tag** は動かない名札、**branch** は本流と別に書き込める枝です。`main` ブランチは常に存在し、期限切れで消えることはありません。

**出典**: 仕様 / → [01](01-architecture.md#branch--tag-と-wap)

### WAP（Write-Audit-Publish）

監査用ブランチに書き込み → データ品質を検証 → 問題なければ `main` に取り込んで公開、という手順。バッチごとに「ステージング → 検証 → 本番反映」のゲートを設ける運用です。

**出典**: 公式ドキュメント（`branching.md`）/ → [01](01-architecture.md#write-audit-publishwap)

---

## REST Catalog

### IRC（Iceberg REST Catalog）

カタログを HTTP/JSON の単一の OpenAPI 契約に統一する仕様。0.14.0 で導入されました。

**仕様に意味のあるバージョン番号はありません**（`info.version` は `0.0.1` のまま）。機能の有無は Iceberg のリリース番号と、実行時の `GET /v1/config` の `endpoints` フィールドで判断します。

**出典**: IRC 仕様 / 公式ドキュメント（`terms.md`）/ → [03](03-rest-catalog.md)

### prefix

IRC のパスに含まれるパスパラメータ。仕様上の定義は「An optional prefix in the path」のみです。

> **注**: マルチテナントの実現手段として使われますが、**仕様は prefix の意味論を定義しておらず、サーバ実装に委ねています**。「prefix はマルチテナント用」と断定する公式記述は確認できていません。

**出典**: IRC 仕様 / → [03](03-rest-catalog.md#prefix-とマルチテナント)

### warehouse

カタログ内の格納先を指す識別子。`GET /v1/config?warehouse=` で指定します。

> **注**: 値の意味は実装依存です。Apache Polaris では**カタログ名**であり、S3 パスではありません。

**出典**: IRC 仕様 / 本報告書の実測 / → [03](03-rest-catalog.md#6-get-v1config--ケイパビリティネゴシエーション)

### credential vending

カタログが**テーブル単位・prefix 単位・短命**のストレージ認証情報をクライアントへ払い出す仕組み。エンジンに長命かつ広範な認証情報を配らずに済みます。

複数の認証情報が返る場合、クライアントは**最長 prefix のもの**を選びます（longest-prefix-wins）。

**出典**: IRC 仕様 / → [03](03-rest-catalog.md#5-credential-vending--remote-signing)

### remote signing

クライアントがストレージへのリクエストの署名をカタログに依頼する方式。**クライアントは認証情報をそもそも保持しません**。

**出典**: IRC 仕様 / → [03](03-rest-catalog.md#5-credential-vending--remote-signing)

### server-side scan planning

「どのファイルを読むか」の計画をカタログサーバ側で行う仕組み。クライアントが manifest を自分で読む必要がなくなります。仕様は 1.7.0、クライアント実装は 1.11.0 で入りました。

**出典**: IRC 仕様 / 公式リリースノート / → [03](03-rest-catalog.md#7-サーバサイド-scan-planning)

---

## 運用

### compaction

小さなデータファイルを結合して適切なサイズにまとめる操作（`rewrite_data_files`）。戦略は bin-pack（既定）/ sort / z-order。

**公式は compaction を "Optional" に分類しています。** また **`expire_snapshots` を回さない限り容量は解放されません**（古いファイルがスナップショットから参照され続けるため）。

**出典**: 公式ドキュメント（`maintenance.md`, `spark-procedures.md`）/ → [06](06-operations.md#a-1-compaction--rewrite_data_files)

### expire_snapshots

古いスナップショットを期限切れにし、参照されなくなったファイルを削除する操作。**公式分類は "Recommended"**（compaction より優先度が高い）。

**branch / tag から参照されているスナップショットは削除されません。** タグを1つ付けるだけで、そのスナップショットと依存ファイルが無期限に残ります。

**出典**: 公式ドキュメント（`maintenance.md`, `spark-procedures.md`）/ → [06](06-operations.md#a-3-expire_snapshots)

### orphan file（孤児ファイル）

どのメタデータからも参照されていないファイル。ジョブ失敗などで発生します（データを先に書き、メタデータを後でコミットする順序のため構造的に避けられません）。

`remove_orphan_files` で削除できますが、**本報告書で最も危険と位置づけている操作**です。進行中の書き込みを誤って削除するとテーブルが壊れます。

**出典**: 公式ドキュメント（`maintenance.md`, `spark-procedures.md`）/ → [06](06-operations.md#a-4-remove_orphan_files--最も危険な操作)

### fail-closed

失敗時に処理を止める設計。本報告書では Amazon S3 Tables の自動スナップショット管理について使っています。**タグやブランチを1つ作るだけで、テーブル全体の自動メンテナンスが停止します**（しかも失敗は課金増加としてしか現れません）。

**出典**: [AWS S3 Tables ドキュメント](https://docs.aws.amazon.com/AmazonS3/latest/userguide/s3-tables-considerations.html) / → [06](06-operations.md#c-1-amazon-s3-tables)

---

## エコシステム

### UniForm

Delta Lake の機能。Delta テーブルから Iceberg のメタデータを自動生成し、Iceberg クライアントがファイルを書き換えずに読めるようにします。

**出典**: [Databricks ドキュメント](https://docs.databricks.com/aws/en/delta/uniform) / → [07](07-ecosystem.md#a-3-設計思想の違い)

### LSM-tree（Log-Structured Merge-tree）

書き込みを追記で受けて後からマージする木構造（LevelDB / RocksDB と同系統）。Apache Paimon が bucket ごとに採用しており、連続 upsert に向く理由です。

> **注**: Iceberg の用語ではありません。Paimon の設計を説明するために用いています。

**出典**: 本報告書の整理 / [Paimon ドキュメント](https://paimon.apache.org/docs/1.4/iceberg/overview/) / → [07](07-ecosystem.md#a-3-設計思想の違い)

### エグレス費用（egress cost）

クラウドから**データを外部へ持ち出すとき**にかかる通信料金。同一クラウド内の読み取りは安価でも、他社クラウドやインターネットへ出すと GB 単位で課金されます。複数クラウドで同じテーブルを共有する構成では総コストを左右します。

**出典**: 本報告書の整理 / → [08](08-decision-guide.md#段階2-カタログを選ぶ)

### TLP（Top-Level Project）

Apache Software Foundation の正式プロジェクト。Incubator を卒業すると TLP になります。Apache Polaris は 2026年2月に卒業しました（**公式ソース3つで日付が食い違っている**点は [04](04-catalog-implementations.md#apache-polaris--tlp-卒業済み最大の変化) を参照）。

**出典**: [ASF](https://incubator.apache.org/) / → [04](04-catalog-implementations.md)

### GA / Preview

製品の提供段階を示す**ベンダー用語**です。

> **重要**: **Apache Iceberg 公式には「v3 が GA」という宣言は存在しません。** 公式ステータスは仕様冒頭の「complete and adopted by the community」までです。GA / Preview はベンダー側（Snowflake / Databricks / Dremio など）の製品提供状況を指します。両者を混同すると「v3 は GA なのに Trino では experimental」といった混乱が生じます。

**出典**: 仕様 / 各ベンダーのドキュメント / → [02](02-table-spec.md#v3-の策定リリース状況), [99](99-methodology.md)

---

## 本報告書が判定に使う語

以下は本報告書がエンジン対応状況を記述するために定めた区分です。**仕様や公式の用語ではありません。**

| 区分 | 意味 |
|---|---|
| **【確認】** | 公式ソースで対応と確認できたもの |
| **【明示的非対応】** | **公式ソースが非対応と明記している**もの |
| **【未確認】** | **ソースが見つからなかった**もの。「非対応」ではない |

**「マージ済み ≠ リリース済み ≠ サポート対象」**も同様に、本報告書が繰り返し用いる区別です。PR がマージされていても、リリースに含まれるとは限らず、公式ドキュメントがサポートを認めているとも限りません。

**出典**: 本報告書の整理 / → [05](05-engine-support.md#読み方重要), [99](99-methodology.md)
