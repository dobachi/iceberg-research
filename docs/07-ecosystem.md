# 07. エコシステムと業界動向

**調査基準日: 2026-07-17** / **リリース日・コミット数・contributor 数は GitHub API および ASF 配布サイト（dlcdn.apache.org）で実測**

> **測定方法の注記**: contributor 数は過去365日のコミットの GitHub ログインをユニーク集計したものです。**GitHub アカウント紐付けのないコミットは脱落する**ため、下限値として読んでください。

---

## A. 他フォーマットとの比較

### A-1. 最新リリース（実測）

| プロジェクト | 最新版 | リリース日 | ソース |
|---|---|---|---|
| Apache Iceberg | 1.11.0 | **2026-05-19** | 公式サイト「released on May 19, 2026」/ git tag の tagger date |
| Delta Lake | 4.3.1 | 2026-07-08 | GitHub Releases |
| Apache Hudi | 1.2.0 | 2026-05-23 | GitHub Releases |
| Apache Paimon | 1.4.2 | 2026-06-23/24 | git タグ / ASF dist |
| **Apache XTable** | **0.3.0-incubating** | **2025-06-04** | GitHub Releases |
| Apache Polaris | 1.6.0 | 2026-07-09 | GitHub Releases |

補足:
- **Paimon は GitHub Releases を作成しない**運用（タグと ASF dist のみ）
- **Hudi は 1.2.0 の後に 0.x 系の保守リリースを継続**: 0.15.1（2026-05-21）、0.14.2（**2026-06-08**）。1.0.0 GA から1年半経った2026年に 0.14 系の保守が必要 = **旧バージョン残留ユーザーが相当数いる**ことの示唆
- **Iceberg のマイナー間隔は伸長傾向**: 1.8.0（2025-02-13）→ 1.9.0（+約2.5ヶ月）→ 1.10.0（+約4.5ヶ月）→ 1.11.0（**+約8.3ヶ月**）

### A-2. 健全性シグナル（2026-07-17 実測）

> **※ 生のコミット数を横並びで比較してはいけません。** ボット比率が **0.4%〜85%** と2桁違います。本節はボット除外値を併記します。この注意を無視すると結論が逆転します（下記）。

| | Iceberg | Delta Lake | Hudi | Paimon | Nessie | Polaris | XTable |
|---|---|---|---|---|---|---|---|
| コミット（過去365日、**生**） | 1,696 | 1,203 | 1,141 | **2,278** | 1,652 | 2,100 | 42 |
| うち**ボット** | 309（18.2%） | 0 | 4（0.4%） | 13（0.6%） | **1,407（85.2%）** | 744（35.4%） | 6 |
| **人間のコミット** | **1,387** | 1,203 | 1,137 | **2,265** | **245** | 1,356 | 36 |
| ユニーク作者（過去365日） | **270** | 140 | 78 | 166 | **22** | 106 | 17 |
| 全期間 contributor | 407 | 391 | 382 | 363 | 79 | 156 | 47 |
| Stars | 9,054 | 8,911 | 6,188 | 3,340 | — | 2,014 | 1,194 |
| Open issues（PR含む） | 851 | 1,560 | **3,017** | 677 | — | — | 162 |

ボットの内訳: Iceberg は全て `dependabot[bot]`、Nessie と Polaris は `renovate[bot]`（Nessie はさらにリリース自動化ボットを含む）。

読み取れること（事実として）:

- **Paimon の開発速度が最も速い。** 人間コミットで **2,265 vs Iceberg 1,387 = 1.63倍**。生の数字（1.34倍）より**差は大きい**です。Iceberg のコミットの 18% が dependabot だからです。
- **Iceberg は直近1年のユニーク作者数で突出**（270人、2位 Paimon 166人の1.63倍）。「特定ベンダー依存度が相対的に低い」ことを示す指標の一つです。
  > **ただしこの結論は指標定義に依存する脆いものです。** **全期間 contributor で測ると Iceberg 407 / Delta 391 / Hudi 382 / Paimon 363 とほぼ横並び（1.12倍）で、「突出」とは言えません。** 「直近1年の活動」を見るか「累積の関与者」を見るかで結論が変わります。所属組織の分布も**未確認**です（下記）。
- **Nessie の「1,652 コミット」は健全性の証拠になりません。** **85.2% が renovate ボットで、人間のコミットは 245 件**。しかも実質1人に集中しています（`snazy` が 212、残り全員で 33）。ユニーク作者は **22人**（Iceberg 270 の 1/12）。リリース頻度が高いのは、依存更新を自動リリースしている構造の反映です。→ [04-catalog-implementations.md](04-catalog-implementations.md#project-nessie--polaris-に統合されて廃止は実現していない)
- **Polaris の 2,100 も 35% がボット。** 人間換算では **1,356 < Iceberg 1,387** で逆転します。
- **Hudi は直近1年のユニーク作者 78人と最少**（XTable 除く）。Open issues 3,017 は突出。
- **主要プロジェクトはいずれも最終 push が測定日近辺 = どれも死んでいません。**

> **方法論上の教訓**: 「コミット数が多い＝活発」は、**ボットを除外しない限り成立しません**。この報告書は初版でその罠を踏み、Nessie を過大評価していました。→ [99-methodology.md](99-methodology.md)

#### なぜ「所属組織の分布」を出さないのか

「特定ベンダーへの依存度」を語るなら、本来は contributor の所属組織を見るべきです。実際に GitHub API から取得を試みましたが、**報告に耐える精度が出ないため、本報告書では出しません**。理由は2つの手法それぞれの限界にあります。

**手法1: コミットメールのドメイン集計**（Iceberg・直近365日の実測）

| ドメイン | 件数 | 所属が分かるか |
|---|---|---|
| `users.noreply.github.com` | 42 | × 匿名化（GitHub の既定設定） |
| `gmail.com` | 32 | × フリーメール |
| `apache.org` | 17 | × **ASF のコミッタ用アドレス。雇用主を示さない** |
| `qq.com` | 3 | × フリーメール |
| `nvidia.com` / `amazon.com` 等 | 数件 | ○ |

**約9割が判定不能**でした。とくに `apache.org` は「ASF のコミッタである」ことしか示さず、所属企業とは無関係です。

**手法2: GitHub プロフィールの `company` フィールド**

直近365日の上位コミッタ10名で試すと、**所属が読めたのは4名だけ**（残る6名は未設定）。しかもこのフィールドは**自己申告で、転職しても更新されない**ことが多く、表記も揺れます（`Databricks` と `Databricks, @databricks`、コミュニティ名の `@apache` など）。

**結論**: どちらの手法も、**所属を公開している一部の人だけが母集団になる**という偏りを避けられません。その偏った標本で「ベンダー中立性」を定量的に語れば、[B-12](99-methodology.md) で自ら戒めた「実測したから正しい」という罠を繰り返すことになります。また、匿名化されたメールから所属を推定する行為は、本人が公開していない属性の推測にあたります。**この指標は「調べていない」のではなく「この方法では信頼できる値が出せない」**という理解が正確です。

### A-3. 設計思想の違い

4つのフォーマットは「同じ問題を別の設計で解いている」ため、まず要点を横並びで示します。

| | Iceberg | Paimon | Hudi | Delta Lake |
|---|---|---|---|---|
| **中核データ構造** | 不変スナップショット + マニフェストツリー | bucket ごとに独立した **LSM-tree** | **timeline**（アクション履歴）+ インデックス | トランザクションログ |
| **前提ワークロード** | **バッチ** | **連続 upsert**（ストリーミング） | upsert + インデックス活用 | Spark 中心（4.0 で他エンジンへ拡張） |
| **エンジンとの関係** | エンジン非依存を志向 | **Flink と密結合**（Flink Table Store 由来） | 複数エンジン対応 | **Delta Kernel** で非 Spark エンジンも単一実装で読み書き |
| **他フォーマットとの相互運用** | — | Iceberg 互換メタデータを生成可（`metadata.iceberg.storage`） | — | **UniForm** で Iceberg メタデータを自動生成（GA） |
| **注目すべき方向性** | v4 でメタデータ構造を刷新中 | Iceberg V3 の deletion vector が互換の基盤に | **AI/ML へ軸足**（VECTOR/BLOB 型、Lance 統合） | Delta 5.0 で Iceberg v4 のメタデータ構造採用を提案 |

以下、それぞれの詳細です。

**Iceberg**: 不変スナップショット + マニフェストツリー。OCC で、コミットはメタデータポインタのアトミックな CAS。**バッチ前提の設計**。

**Paimon**: パーティションを bucket に分割し、**各 bucket が独立した LSM-tree**（LevelDB/RocksDB と同系統）。Flink Table Store 由来のため設計前提が Flink と密結合。**連続 upsert に最適化**。Iceberg 互換メタデータの生成も可能（`metadata.iceberg.storage` 設定）で、**Iceberg V3 の deletion vector が互換の技術的基盤**になりました。

**Hudi**: timeline（アクション履歴）+ インデックス中心。1.2.0（2026-05-23）は table version 9 を 1.1.1 から維持（アップグレード不要）。**1.2.0 の方向性は AI/ML**: VECTOR・VARIANT・BLOB の3論理型、`read_blob()` / `hudi_vector_search()` の Spark SQL 関数、**Lance フォーマットのネイティブ統合**、Flink での Record-Level Index フルサポート。

> **Hudi は「テーブルフォーマット競争」から降りて AI/ML データレイクへ軸足を移している**ように読めます。ただしこれは筆者の**評価**であり、Hudi PMC の公式表明ではありません。

**Delta Lake**: Delta 4.0 で **Delta Kernel** を導入（Trino/Flink など非 Spark エンジンが単一のコア実装で読み書き）。UniForm は GA で、Delta テーブルから Iceberg メタデータを自動生成し、Iceberg クライアントがファイル書き換えなしに読めます。

> **UniForm の Hudi 対応は long-standing の "coming soon" のまま**で、2026年7月時点の提供状況は未確認です。

### A-4. 相互運用 — XTable は実測で停滞

ベンダー中立の相互運用を担う唯一のプロジェクトである XTable の実測値:

- 最新リリース **0.3.0-incubating = 2025-06-04**（**13ヶ月以上リリースなし**）
- コミット: 直近90日 **10件** / 365日 **41件** / 2024-07-17 以降の2年間で 148件 → **明確な減速カーブ**
- Incubation 入りは **2024-02-11**、**2026年7月時点でまだ incubating**（約2年5ヶ月）
- 直近コミットは Onehouse 関係者と dependabot が大きな比率

**評価**: 上記の実測値は、「XTable は停滞している」という判断を裏付けます。ただし**プロジェクトは放棄されていません**（最終 push 2026-07-14）。Incubator ステータスページに活動への懸念の明記は**確認できませんでした**。

**対照的に、ベンダー主導の相互運用の方が実際に動いています**:
- Databricks UniForm（GA）
- Microsoft OneLake のメタデータ仮想化（双方向）
- Fivetran: Parquet を1回書いて **Iceberg と Delta のメタデータを同時に維持**

> **これはロックインの観点で重要な指摘です。** 相互運用が「ベンダーの善意」に依存しており、中立の仕組みは動いていません。

---

## B. 「Iceberg は事実上の標準になったのか」

「Iceberg が勝った」という言説は多いものの、根拠として挙がる事実と、それに反する事実の両方があります。まず優位を支持する事実、次に反証を並べ、最後に整理します。

### B-1. Iceberg 優位を支持する事実

#### Databricks（Tabular 買収 2024 の「その後」）

- **2025-06-12**: 「Announcing full Apache Iceberg support in Databricks」。UC の IRC API 経由で Managed Iceberg テーブルの読み書き。「Virtually any Iceberg client compatible with the REST spec, such as Apache Spark, Apache Flink, or Trino can read and write to Unity Catalog」
- **2026-05-28**: Managed Iceberg **GA**、Iceberg v3 **GA**、Foreign Iceberg **GA**、Iceberg クライアントへの External Sharing **GA**
- **最も重い事実**: 同ブログで Databricks は「**With Iceberg v4, we are rethinking the core metadata structure from the ground up**」と述べ、**Delta 5.0 が Iceberg v4 と同じ adaptive metadata tree 構造を採用することを提案**しています。

> **つまり Delta の作者自身が、Delta の次期メジャーを Iceberg v4 のメタデータ設計に寄せる提案をしています。** これは「競争」ではなく「統合」としてフレーミングされています。

#### Apache Polaris

- Snowflake と Dremio が共同作成し **2024年8月 ASF へ寄贈**
- **TLP 卒業**（2026-02-19 公式アナウンス）。**卒業投票は +1 が27票、反対0**
- PMC に Dremio, Snowflake, Google, Microsoft, Confluent, LanceDB のエンジニアが参加（**ASF 公式名簿での照合は未実施**）
- 健全: 1.6.0（2026-07-09）、過去365日で 2,084 コミット

#### 各クラウド

- **AWS**: S3 Tables（Iceberg 専用のマネージドストレージ）。2026年も拡張継続（GovCloud 2026-02-23、Taipei/New Zealand 2026-05-29）。**Iceberg V3 対応済み**
- **GCP**: **2026-04-20 に BigLake を「Lakehouse for Apache Iceberg」へ改称**。**製品名に Iceberg を冠しました**。Managed Iceberg tables **GA**、BigLake Metastore（IRC）**GA**
- **Azure/Microsoft**: OneLake は **Delta Lake がネイティブ既定フォーマット**。Iceberg は**メタデータ仮想化**で対応。**Iceberg V3 互換は「今後の重点」= 未完了**

#### Snowflake

Iceberg v3 GA（2026-05-07）、Snowflake ストレージ for Iceberg GA（2026-06-01）、**Databricks Unity Catalog への Iceberg 書き込み対応 GA on Azure（2026-04-06）** — つまり**競合のカタログへ書きに行くことまでやっています**。

#### 周辺エコシステム

Confluent Tableflow、Fivetran Managed Data Lake Service（**既定で Apache Polaris ベースの self-hosted Iceberg REST カタログを同梱**）。

### B-2. 反証 — 「事実上の標準」と言い切れない事実

1. **Confluent Tableflow は Iceberg 専用ではありません。** Delta Lake + Databricks Unity Catalog 統合が **2025-10-29 に GA** し、**Iceberg と Delta を1トピックで同時有効化できます**。エコシステムは Iceberg に**収斂しておらず、両対応に張っています**。

2. **Fivetran も両対応。** Iceberg *または* Delta に変換し、Parquet を1回書いて**両方のメタデータを同時維持**する設計。「Iceberg を選んだ」のではなく「**選ばせない**」戦略です。

3. **Microsoft Fabric が標準で使うのは依然 Delta です。** Iceberg 対応は仮想化レイヤー経由で、V3 互換は未完了。Azure スタックでは Delta が本命の座を保っています。

4. **Databricks の Iceberg 対応には条件が付きます。** Onehouse の Kyle Weller 氏（VP of Product、**Iceberg 競合ベンダー = 利害関係者である点に留意**）が 2026-06-11 に指摘した内容のうち、Databricks 公式ドキュメントの引用に基づくものは重いです:
    - **Unity Catalog が必須** → Polaris や Nessie を代替カタログとして使えない
    - **非対称な相互運用**: 外部エンジンは UC に IRC で繋げるが、**Databricks から他の IRC 準拠カタログへは繋ぎに行けない**
    - Foreign Iceberg テーブルは **"read-only in Databricks and have limited platform support"**、**credential vending 非対応**
    - Managed Iceberg でも partition transforms / branching / tagging / streaming が欠落し、独自機能（Liquid Clustering 等）で代替
    - Databricks 自身の Lakeflow / Zerobus Ingest / AI Search は主に Delta 対応

    → **「Iceberg 対応」は「Iceberg 仕様のフルサポート」を意味しません。** ただし個別の制限事項の現時点での正確性は**未確認**（docs は頻繁に更新されるため）。

5. **Paimon が最速で開発されています**（コミット 2,271/年、Iceberg の 1.35倍）。Iceberg に吸収される兆候はありません。

6. **Hudi は AI/ML 領域へ差別化**（VECTOR/BLOB 型、Lance 統合）。Iceberg にない機能軸です。

7. **新規参入があります**: **DuckLake v1.0 が 2026-04-13 にリリース**（production-ready 仕様 + DuckDB 拡張、後方互換保証）。**メタデータを全て SQL データベース（SQLite/PostgreSQL/DuckDB）に置く**という、Iceberg と根本的に異なる設計。v1.1 は2026年9月予定。**フォーマット戦争は終結していません。**

8. **Iceberg v4 は仕様として未採択です** → [02-table-spec.md](02-table-spec.md#v4-metadata-structure-and-representation--未採択ただし実装は先行している)。（ただし Java 実装は 1.10.0 以降 `format-version=4` を受理します。「未採択」＝「作れない」ではありません。）Iceberg 自身が「バッチ前提のメタデータ設計」という積み残しを抱えたままです。

### B-3. 結論

**「デファクト標準になった」と単純に言うのは不正確です。** より事実に忠実な整理:

#### (a) カタログ・インターチェンジ層としては、IRC 仕様が事実上の共通語になりつつある

根拠がここに集中しています:
- Databricks が UC に IRC API を実装（2025-06）
- GCP の BigLake Metastore が IRC で GA
- Fivetran が Polaris を既定同梱
- Polaris が**反対0で TLP 卒業**し PMC が6社超に分散
- Snowflake が競合の UC へ Iceberg 書き込みを GA

**「相互接続の合意点」としては Iceberg が勝っている**と言えます。

#### (b) しかし「単一の実装フォーマット」としては勝っていない

Fabric のネイティブは Delta、Confluent と Fivetran は両対応、Paimon は Iceberg の1.35倍の開発速度、DuckLake が2026年に v1.0 到達。

#### (c) 最も重要な事実は「統合」の方向

**Databricks が Delta 5.0 に Iceberg v4 のメタデータ構造を採用提案**（2026-05-28、公式ブログ）。これが実現すれば「Iceberg が勝った/Delta が負けた」ではなく**両者が同一メタデータを共有する**世界になります。ただし**提案段階であり、Delta 5.0 も Iceberg v4 もリリースされていません**。

---

## C. Iceberg を使うべきでない場面

**ここは報告書の価値を決めるセクションです。Iceberg の宣伝にならないよう、正直に書きます。**

### C-1. 低レイテンシ・高頻度コミットのストリーミング

**なぜ不向きか（仕様レベル）**: Iceberg は OCC で、コミットごとに新しいメタデータツリーを書き、ポインタを atomic CAS で入れ替えます。競合すると**負けた書き手は新しい state に基づきメタデータツリーを書き直してリトライ**します。つまり**コミット頻度に対して書き込み増幅（write amplification）が効き、並行書き手が増えるほど衝突リトライが増えます**。

**これは推測ではありません。** Snowflake の公式エンジニアリングブログ（2026-06-04、Iceberg Summit 2026 recap）自身がこう述べています:

> **Iceberg's metadata tree was built for batch workloads, and its write amplification creates commit latencies that streaming can't tolerate.**

そして v4 の adaptive metadata tree と single-file commit がこれを直接狙うと説明しています。**Iceberg の主要推進企業が制約を公式に認めている**、というのが最も強い根拠です。

**代替**: **Paimon**（bucket ごとの独立 LSM-tree で連続 upsert に最適化）。あるいはストリーミング層（Kafka/Flink state）で保持し、Iceberg へはマイクロバッチで落とす。

> **未確認**: 「Paimon 1〜5分 vs Iceberg 1時間以上」といった具体的レイテンシ比較はベンダー/個人ブログ由来で、**一次情報での裏取りができていません**。自環境でのベンチマークを推奨します。

### C-2. 頻繁な小規模更新 / 高チャーンな CDC

**なぜ不向きか**: CoW では小さな更新でもファイル全体を書き直します。MoR では delete file / DV が compaction 間に累積し、読み取り時のマージコストが増え続けます。結果として**compaction を運用し続けることが前提**になります。

さらに [02-table-spec.md](02-table-spec.md#row-lineage-の重大な制約-equality-delete-では追跡されない) の通り、**CDC 目的で v3 の row lineage を当てにしても、equality delete を使うエンジン（Flink upsert 等）では追跡されません。**

**代替**: Paimon（LSM の compaction がアーキテクチャに内包）、Hudi（MoR + Record-Level Index）。

### C-3. 小規模データ

**なぜ不向きか**: Iceberg の利点（パーティション進化、スナップショット分離、大規模メタデータのプルーニング）は**大規模テーブル・複数エンジンでこそ効きます**。数GB規模では、カタログ運用・compaction・スナップショット期限切れ・孤児ファイル削除といった**保守ジョブの運用コストが利得を上回ります**（[06-operations.md](06-operations.md) の作業量を見てください）。

**代替**: DuckDB + Parquet、**DuckLake**（メタデータを SQL DB に置くためカタログサーバーの運用が不要。v1.0 が 2026-04-13 に production-ready 宣言）、通常の RDBMS。

### C-4. 単一エンジンしか使わない

**なぜ不向きか**: **Iceberg の存在理由はエンジン非依存の共有です。** Databricks だけ / Snowflake だけ / BigQuery だけなら、そのプラットフォームのネイティブ形式の方が最適化（Liquid Clustering、Predictive Optimization 等）を享受できます。

実際 Databricks は Managed Iceberg でも **partition transforms / branching / tagging / streaming が使えず独自機能で代替**しているという指摘があり（Onehouse、2026-06-11、**要独立検証**）、**「Iceberg を選んだのに Iceberg の機能が使えない」**状態が起こりえます。

**代替**: そのプラットフォームのネイティブ形式。将来の可搬性が欲しいなら UniForm / OneLake メタデータ仮想化で「後から出す」方が合理的な場合があります。

### C-5. Flink 中心のストリーミング特化

**なぜ不向きか**: Paimon は Flink Table Store 由来で**設計前提が Flink と密結合**です。Iceberg の Flink コネクタはチェックポイント間隔でコミットするため、**パーティション数 × チェックポイント頻度で小ファイルが機械的に量産されます**。

さらに [05-engine-support.md](05-engine-support.md#apache-flink) の通り、**Flink の Iceberg 書き込みは INSERT/UPSERT のみで MERGE/UPDATE/DELETE の SQL がありません。**

**代替**: Paimon。ただし Paimon は Iceberg 互換メタデータを生成できるので、**Paimon で書いて Iceberg として読ませる**構成が取れます。

### C-6. Azure/Fabric 中心の環境

**なぜ不向きか**: OneLake のネイティブは Delta。Iceberg は仮想化経由で、**Iceberg V3 互換は Microsoft 自身が「今後の重点」と位置づけており未完了**です。V3 の DV / VARIANT を前提にした設計は現時点で成立しない可能性があります。

**代替**: Delta Lake（ネイティブ）+ 必要に応じてメタデータ仮想化で Iceberg 公開。

### C-7. AI/ML の非構造データを同居させたい

**なぜ不向きか**: Iceberg 1.11.0 時点で VECTOR/BLOB 相当のネイティブ型やベクトル検索は**確認できませんでした**（1.11.0 の中身の完全な確認は未実施）。

**代替**: **Hudi 1.2.0**（VECTOR/VARIANT/BLOB 型、`hudi_vector_search()`、Lance フォーマット統合）。

### C-8. PyIceberg だけで完結させたい

**なぜ不向きか**: [05-engine-support.md](05-engine-support.md#pyiceberg) の通り、PyIceberg は **v3 テーブルを書けず、equality delete を読めず、MoR も使えず、compaction もありません**。「Python だけで Iceberg を運用する」は現時点で成立しません。

**代替**: PyIceberg は読み取りと軽量な書き込みに使い、メンテナンスと重い DML は Spark に任せる。

---

## D. 実務上の含意

1. **フォーマット選択は以前ほど不可逆ではありません。** UniForm / OneLake 仮想化 / Paimon の Iceberg 互換 / Fivetran の二重メタデータにより、「主要ワークロードに最適な形式で書き、他形式は公開で賄う」が現実的です。ただし**この相互運用はベンダー実装が担っており、ベンダー中立の XTable は実測上停滞している**ことは、ロックインの観点でリスクとして認識すべきです。

2. **カタログ選択の方がフォーマット選択より重い可能性があります。** Databricks が UC 必須・外向き IRC 非対応であるなら、**フォーマットが Iceberg でもカタログでロックされます**。Polaris が反対0で TLP 卒業し PMC が分散していることは、中立カタログの選択肢として意味を持ちます → [04-catalog-implementations.md](04-catalog-implementations.md)

3. **2026年後半〜2027年の最大の変数は Iceberg v4 と Delta 5.0 です。** Databricks の統合提案が実現するか、dev ML で分岐するかで絵が変わります。**現時点で v4 前提の設計判断をすべきではありません。** ただし理由は「作れないから」ではありません — **Iceberg Java 1.10.0+ は `format-version=4` を受理してしまいます**（[02](02-table-spec.md#v4-metadata-structure-and-representation--未採択ただし実装は先行している)）。**仕様が未採択のまま変わりうる**ことが理由です。作れてしまう分、むしろ注意が必要です。

---

## 未確認事項

- **Polaris の TLP 卒業日**: Incubator ステータスページは 2026-02-15、公式ブログ/プレスは 2026-02-19。理事会決議日と公表日の差と推測されるが**未確定**
- **Paimon / Iceberg の contributor 所属組織の分布**（ベンダー集中度）— 未測定
- **Paimon vs Iceberg の具体的レイテンシ数値** — 一次情報での裏取り不可
- **Onehouse が指摘する Databricks の個別制限事項の現時点での正確性** — 独立検証未実施（同社は利害関係者）
- **UniForm の Hudi 対応**の2026年7月時点の提供状況
- **Iceberg 1.11.0 の機能詳細**（VECTOR 型等の有無を含む）— リリースノート全文の確認は未実施
- **Delta 4.1.0 のリリース日**: GitHub タグは 2026-02-26 だが、一部二次情報は「2026年3月」と記載。**GitHub 実測値を採用**

---

## 出典

- [Apache Iceberg Releases](https://iceberg.apache.org/releases/) / [Reliability docs](https://iceberg.apache.org/docs/1.6.0/reliability/)
- [Databricks: Unity Catalog and the Next Era of Apache Iceberg (2026-05-28)](https://www.databricks.com/blog/unity-catalog-and-next-era-apache-icebergtm)
- [Databricks: Announcing full Apache Iceberg support (2025-06-12)](https://www.databricks.com/blog/announcing-full-apache-iceberg-support-databricks)
- [Databricks: UniForm GA](https://www.databricks.com/blog/delta-lake-universal-format-uniform-iceberg-compatibility-now-ga) / [UniForm docs](https://docs.databricks.com/aws/en/delta/uniform)
- [Apache Polaris: TLP 卒業 (2026-02-19)](https://polaris.apache.org/blog/2026/02/19/apache-polaris-graduates-to-top-level-project/) / [Incubator status](https://incubator.apache.org/projects/polaris.html)
- [Snowflake: Iceberg Summit 2026 Recap — V4 spec (2026-06-04)](https://www.snowflake.com/en/blog/engineering/iceberg-summit-2026-recap-v4-spec/)
- [Apache XTable Incubator status](https://incubator.apache.org/projects/xtable.html) / [GitHub](https://github.com/apache/incubator-xtable)
- [Apache Hudi 1.2 release notes](https://hudi.apache.org/releases/release-1.2/)
- [Apache Paimon Iceberg compatibility](https://paimon.apache.org/docs/1.4/iceberg/overview/)
- [AWS S3 Tables](https://aws.amazon.com/s3/features/tables/)
- [Google Cloud: Iceberg managed tables in BigQuery](https://docs.cloud.google.com/bigquery/docs/biglake-iceberg-tables-in-bigquery)
- [Microsoft: Use Iceberg tables with OneLake](https://learn.microsoft.com/en-us/fabric/onelake/onelake-iceberg-tables)
- [Confluent: Tableflow Delta Lake + Unity Catalog (2025-10-29)](https://www.confluent.io/blog/tableflow-delta-lake-unity-catalog-azure/)
- [Fivetran Managed Data Lake Service](https://www.fivetran.com/docs/managed-data-lake-service)
- [DuckLake v1.0 (2026-04-13)](https://duckdb.org/2026/04/13/ducklake-10)
- [Onehouse: Databricks Iceberg Support Has a Catch (2026-06-11)](https://www.onehouse.ai/blog/databricks-iceberg-support-has-a-catch-its-called-unity-catalog) ※**競合ベンダー発**
