# 99. 調査方法論と未確認事項

**この報告書を更新する人、および Iceberg 周辺で同種の調査を行う人は、まずここを読むことを勧めます。**

この調査は複数の調査エージェントによる並列調査として実施し、エージェント間で食い違った主張は専任の検証で一次情報に当たって決着させました。その過程で**再現性のある罠**がいくつも見つかりました。以下はその記録です。

---

## A. 証跡の優先順位

```
公式ドキュメント
  > リポジトリの実ファイル / ソースコード
    > 公式ブログ・プレスリリース
      > 技術ブログ
```

**上位と下位が矛盾したら上位を採用し、矛盾の存在自体を記録します。**

### なぜこの順序なのか — 実例

**Dremio の v3 対応**で、この順序が決定的でした。

| ソース | 主張 |
|---|---|
| プレスリリース（2026-04-06） | 「ships the latest V3 spec **at GA**」「full read and write support」 |
| **docs** | 見出しに **"Iceberg v3 Preview"** |

**マーケティング文書は "GA" と書きたがります。** docs を採用して **Preview** と判定しました。ある調査エージェントはプレスリリースのみを根拠に GA と報告しており、これが本調査で見つかった**唯一の実質的な誤り**でした。

---

## B. この調査で踏んだ罠

### B-1. リリースノートは遡及更新されない ★最重要

**Snowflake の外部エンジンからの v3 書き込み**で、エージェント間の主張が食い違いました。

- 2026-05-07 の GA リリースノート: 「Writes from external engines to Snowflake-managed Iceberg v3 tables through Horizon Catalog **aren't supported yet**」
- 現行 docs: 「read and write to Snowflake-managed Iceberg **v2 and v3** tables」

**矛盾ではありませんでした。** 2026-05-26 に外部エンジン write が GA 化して制約が解消され、**リリースノートは当時の記述のまま残っていた**だけです。

> **教訓: リリースノートを「現在の状態」の根拠に使わないこと。** 仕様上、後から更新されません。点時記述として読み、**現況は必ず現行 docs で確認する**こと。

### B-2. 「マージ済み ≠ リリース済み ≠ サポート対象」★頻出

この罠は **Trino・Presto・Spark で繰り返し**現れました。

| 事例 | 実態 |
|---|---|
| **Trino の v3** | v3 の PR は**すべてマージ済み**（#27786〜#27893）。しかし **docs は今も「Support for format version 3 is experimental」** とし、row-level updates/deletes/OPTIMIZE を非対応と宣言。**default values も #27837 がマージされているのに docs は非対応と書く** |
| **Spark の geometry/geography** | PR #17073 は 2026-07-08 マージ済み。しかし **milestone は 1.12.0 = 未リリース**。今日使えない |
| **Presto の v3** | DV + UPDATE/MERGE（#28058/#27943）はトランクにマージ済みだが、**どのリリースにも入っていない** |

> **教訓: マージ済み PR のリストを「サポート済み」と読まないこと。** リリースタグとマイルストーンを確認し、最終的には docs を authoritative とすること。

### B-3. リリースノートの要約が誤読を誘う

**Spark の default values** が典型例です。

1.11.0 のリリースノートに「Add schema conversion support for default values (#14407)」とあります。しかし:
- 実タイトルは **"Spark 4.0: Add schema conversion support for default values"**
- 変更は `TypeToSparkType.java` のみ = **スキーマ変換だけ**
- 同じ 1.11.0 タグのコードに `throw new UnsupportedOperationException("Cannot add column %s since setting default values in Spark is currently unsupported")` が**実在**

> **教訓: リリースノートの要約タイトルではなく、PR の実タイトルと変更ファイルを見ること。**

### B-4. ドキュメントサイトがバージョンに追従していない

**PyIceberg** の `py.iceberg.apache.org` には**バージョンセレクタ/バナーがなく**、どのバージョンに対応するか明示されません（＝ `main` 追従の可能性）。

そこで本調査は**リリースタグ `pyiceberg-0.11.1` のソースを直接取得して照合**しました。結果、docs だけでは分からない精度で確定できました:
- `table.maintenance` の実在（`table/__init__.py` L1129、`table/maintenance.py`）
- **v3 は「型定義は存在するが `model_dump_json` が `NotImplementedError` を投げる＝書き込み不可」**

> **教訓: docs が信用できないときは、リリースタグのソースを直接読むこと。**

### B-5. 公式ソース同士が矛盾する

**Flink の VARIANT**:

| ソース | 主張 |
|---|---|
| `flink.md` 型表（1.11.0 タグ・main 双方） | `variant \| \| Not supported` |
| 1.11.0 リリースノート | 「Support Variant to Flink 2.1 (#15265)」 |
| 1.11.0 タグの実コード | `flink/v2.1/.../TypeToFlinkType.java` に variant 参照3件を実測。テストも存在 |

実装は入っており、**型対応表が未更新**と判断しました。**ただし公式ソースが「Not supported」と書いている事実は残る**ため、両方を記載しています。

### B-6. `iceberg.apache.org` は JS レンダリングで本文が取れない

これは**技術的な障害**ですが、対処法が確立しました。

| 取れないページ | 代わりに取るもの |
|---|---|
| `iceberg.apache.org/spec/` | `https://raw.githubusercontent.com/apache/iceberg/main/format/spec.md`（2137行） |
| `iceberg.apache.org/rest-catalog-spec/`（Swagger UI） | `https://raw.githubusercontent.com/apache/iceberg/main/open-api/rest-catalog-open-api.yaml`（5822行） |
| `iceberg.apache.org/docs/latest/*` | `https://raw.githubusercontent.com/apache/iceberg/main/docs/docs/*.md` |

**Databricks の docs も同様**です。`curl` で HTTP 200・約50KB が返りますが、JS レンダリングのシェルのみで本文は含まれません。**「curl して grep したら Preview が出ない＝GA」という推論は成立しません。**

> **教訓: 生ソース（raw.githubusercontent.com）を第一の取得先にすること。**

### B-7. 「GA」はベンダー用語であって Apache の宣言ではない

**Apache Iceberg 公式には「v3 が GA」という宣言が存在しません。** 公式ステータスは仕様冒頭の「complete and adopted by the community」までです。

「GA」は Snowflake / Databricks / Dremio といった**ベンダー側の製品提供状況**を指します。両者を混同すると、「v3 は GA なのに Trino では experimental」といった混乱が生じます。

### B-8. 「未確認」と「非対応」は別物 ★

**これが最も重要な区別です。**

| 例 | 判定 |
|---|---|
| Trino の v3 row-level updates | **【明示的非対応】** — docs が「are not supported」と**明言している** |
| Flink の row lineage 生成 | **【未確認】** — **ソースが見つからなかった**だけ |
| Redshift の Iceberg 書き込み | **【未確認】** — AWS の docs に**肯定も否定も見つからない** |

**「見つからなかった」を「非対応」と書くのは捏造です。** 本報告書では3値で厳密に区別しています。

### B-9. 上流の前提が古いことがある

調査依頼の前提自体が一次情報で否定された例:

| 依頼中の前提 | 実際 |
|---|---|
| `s3.path-style-access` を設定する | **PyIceberg にこのキーは存在しない**。実在するのは `s3.force-virtual-addressing`。しかも `s3.endpoint` を設定すれば自動で path-style になるので**何も設定しなくてよい** |
| MinIO を使う | **`minio/minio` は 2026-04-25 にリポジトリごとアーカイブ済み** |
| Polaris は incubating | **2026-02 に TLP 卒業済み** |
| Polaris の `getting-started/eclipselink/` | **撤去済み（404）**。`jdbc` に置換 |

> **教訓: 依頼者の前提も検証対象に含めること。**

### B-10. 二次情報が「事実」として流通している

| 流通している主張 | 実際 |
|---|---|
| 「Nessie は Polaris に統合されて廃止」 | **2024年の Dremio CMO 発言に基づく報道**。2026年7月時点で Nessie は **archived ではなくリリースも継続中**（0.108.2、2026-07-17）。ただし「活発」も過大評価で、**人間のコミットは年間245件・実質1人**（[B-12](#b-12-実測値も指標の定義を疑わないと嘘になる-実際にやらかした)）。正確には**「retire はされていないが、実質は少数保守モード」** |
| 「`iceberg-rest-fixture` は公式が本番使用を禁止している」 | **README にそのような明示的免責文は存在しない（未確認）**。よく引用される警告は RCK 側のもの。ただし命名・ソース配置（`testFixtures`）・既定値（インメモリ SQLite）が**すべてテスト用途を示す**のは事実 |
| 「Polaris が MinIO をやめたのは AGPL 化のため」 | **Polaris の一次情報（PR #3482 / 公式 docs）にライセンスを理由とする記述はない**。公式が一貫して挙げる理由は「**maintenance mode / セキュリティ修正が来ない**」。しかも **MinIO のライセンスは AGPLv3 のままで変わっていない** |
| 「Hive は死んだ」 | **Attic に入っていない**（実際に attic.apache.org を取得して確認）。4.2.0（2025-11-23）リリース済み、4.3.0 の議論で Iceberg v3 が最優先スコープ |

> **教訓: 「みんなが言っていること」ほど一次情報に当たること。**

### B-11. 動かすと、読むだけでは絶対に出ない事実が出る

[`iceberg-rest-lab`](../../iceberg-rest-lab) を実際に構築・実行したところ、**ドキュメントを読むだけでは決して分からなかった罠**が出ました。

**症状**: PyIceberg でコミットすると

```
pyiceberg.exceptions.CommitStateUnknownException:
  StsException: (Service: Sts, Status Code: 400, Request ID: null)
```

**原因**: Polaris のカタログ storage config に `roleArn` を設定していたため、Polaris が credential vending のために **STS AssumeRole** を呼びに行った。RustFS も MinIO も **STS に対応していない**。

**なぜ読んでも分からなかったか**: Polaris の公式ガイドは `roleArn` を**書いていない**だけで、「S3 互換ストレージでは書いてはいけない」とは**どこにも書いていません**。「AWS の例に `roleArn` があるから付けておこう」という自然な発想が罠になります。**公式サンプルの「無いもの」に意味があるケース**は、差分を取らないと気づけません。

**副次的な発見**: このエラーメッセージは誤解を招きます。`CommitStateUnknownException` は仕様上「コミットが成功したか失敗したか分からない」という**最も危険な状態**を意味しますが（[03-rest-catalog.md](03-rest-catalog.md#500-commitstateunknownexception--最重要の落とし穴) 参照）、実態は単なる設定ミスでした。仕様上の意味と実装のエラー分類が一致しないことがあります。

> **教訓: 動かせるものは動かすこと。** 「公式サンプルをコピーして少し足す」は、その「少し」が事故になります。足したものは疑ってください。

なお実際に動かしたことで、**報告書の主張11件が実測で裏付けられた**（既定 v2、CoW 既定、V3 書き込み不可、MoR フォールバック、`s3.path-style-access` 不在、field ID 不変、credential vending の prefix スコープ、409 の再現、`prefix` が overrides で配られること、など）ことも成果です。読んだだけの主張と、動かして確かめた主張は、報告書の中で区別する価値があります。

### B-12. 実測値も、指標の定義を疑わないと嘘になる ★実際にやらかした

**この報告書は初版でこの罠を踏み、公開前のファクトチェックで発覚しました。** 実測したから正しい、とはなりません。

初版は「Nessie は直近52週 **1,630 コミット**で活発に開発継続中」と書いていました。数字自体は正確でした。**内訳を見なかったのが誤りです。**

| プロジェクト | 総コミット（365日） | ボット | **人間** |
|---|---|---|---|
| Iceberg | 1,696 | 309（18.2%、全て dependabot） | 1,387 |
| Paimon | 2,278 | 13（0.6%） | **2,265** |
| Hudi | 1,141 | 4（0.4%） | 1,137 |
| Delta Lake | 1,203 | **0** | 1,203 |
| **Nessie** | 1,652 | **1,407（85.2%、renovate）** | **245** |
| **Polaris** | 2,100 | 744（35.4%、renovate） | 1,356 |

**ボット比率が 0.4% 〜 85% と2桁違うため、生のコミット数を横並びにした表は指標として成立していませんでした。** 具体的に何が壊れたか:

1. **Nessie の「活発」は幻**。人間のコミットは 245 件で、しかも実質1人（`snazy` が 212）。「1,630 コミット」で Hudi（1,141）や Delta（1,203）より上位に見せていたのは、**renovate の依存更新を数えていただけ**です。
2. **Polaris と Iceberg の順位が逆転**。生では Polaris 2,100 > Iceberg 1,696 ですが、人間では 1,356 < 1,387 です。
3. **Paimon の優位を過小評価していた**。生では Iceberg の 1.34倍ですが、人間では **1.63倍**。Iceberg の 18% が dependabot だからです。

**さらに指標定義の混在もありました。** 「Iceberg 267 / Paimon 164」は**直近365日のユニーク作者**、「Polaris 156 / Nessie 79」は**全期間 contributor** で、同じ表に並べていました。しかも「Iceberg は contributor 数で突出」という結論は**直近365日ベースでのみ成立**し、全期間で測ると Iceberg 407 / Delta 391 / Hudi 382 / Paimon 363 で**ほぼ横並び**です。

> **教訓1: 「コミット数が多い＝活発」は、ボットを除外しない限り成立しません。**
> **教訓2: 複数プロジェクトを比較する表では、全セルが同じ指標定義であることを確認してください。**
> **教訓3: 実測は「測った」で終わりではありません。何を測ったかを疑ってください。** 数字はそれ自体では嘘をつきませんが、**内訳を見ないと嘘の結論を支えます**。

### B-13. 「未採択」と「実装が受け付けない」は別物 ★これもやらかした

初版は「**2026年7月時点で `format-version=4` は設定できません**」と書いていました。**誤りです。**

- **仕様**: 「Version 4 is under active development and **has not been formally adopted**」← これは正しい
- **Iceberg Java 1.10.0+（2025-09-11〜）**: `SUPPORTED_TABLE_FORMAT_VERSION = 4`。バリデーションは `formatVersion <= SUPPORTED_TABLE_FORMAT_VERSION` なので **v4 は通過する**
- **PyIceberg 0.11.1**: `TableVersion = Literal[1, 2, 3]` で **受理しない**

リリースタグ実測: 1.8.0 → 3、1.9.0 → 3、**1.10.0 → 4**、1.11.0 → 4。

**「仕様が未採択」から「実装が拒否する」を推論したのが誤りでした。** 実際には Java は既に v4 テーブルを作れます。しかも `MIN_FORMAT_VERSION_PARQUET_MANIFESTS = 4` / `MIN_FORMAT_VERSION_OPTIONAL_LOCATION = 4` と、v4 機能のゲートがコードに入っています。

> **教訓: 仕様と実装は別のものです。** 「仕様がこう書いてあるから実装もこうだろう」は推論であって事実ではありません。**実装の主張をするなら実装を読んでください。** この誤りは、仕様書だけを読んで実装を確認しなかったことに起因します。

**実務上の含意も逆になります。** 「作れないから安全」ではなく、**「作れてしまうので、仕様が変わるリスクを自分で避ける必要がある」**のです。

### B-14. 実測できるものは実測する

プロジェクトの健全性は、印象ではなく GitHub API で測れます。

```
XTable: 最新リリース 2025-06-04（13ヶ月前）、直近90日 10 コミット、2年5ヶ月 incubating のまま
Iceberg: 直近365日 1,680 コミット、contributor 267名
Paimon: 直近365日 2,271 コミット（Iceberg の1.35倍）
```

「XTable は停滞している」「Paimon は Iceberg に吸収されていない」といった判断は、**この実測値が支持します**。

---

## C. エージェント間の食い違いをどう扱ったか

本調査では、独立した調査エージェントの報告が4つの論点で食い違いました。専任エージェントを立てて一次情報で決着させた結果:

| 論点 | 結果 |
|---|---|
| Databricks の v3 は GA か Preview か | **どちらも正しかった**（2026-04-09 Preview → 2026-05-28 GA。見ていた時点が違った） |
| Snowflake の外部エンジン v3 書き込み | **どちらも正しかった**（5/7 時点の制約が 5/26 に解消。リリースノートが古い） |
| Dremio の v3 は GA か Preview か | **一方が誤り**（プレスリリースを採り、docs と突き合わせていなかった） |
| Snowflake Open Catalog は新規顧客にクローズか | **主張は公式 docs で裏取りできた**（ただし課金開始時期のみ決着つかず） |

**食い違い4件中3件が「時系列の異なる時点を切り取った」ことによるもの**でした。

> **教訓: 食い違いを見たら、まず「両方が別の時点で正しい可能性」を疑うこと。** 日付を押さえれば大半は解決します。

### 調査プロセス上の事故についての注記

調査エージェントの1つが、**調査途中で事実を捏造する事故**を自己申告しました（「Redshift の書き込みが 2026-04-23 に GA」「Athena は v2 のみ」の2件）。本人は撤回し最終報告には含めていないと述べています。

専任エージェントによる検証の結果、**この2件が本報告書に混入している形跡は見つかりませんでした**。また4論点の範囲では、どちらのエージェントにも明確な捏造は検出されませんでした。

**この事故を記録に残すのは、それがまさにこの調査が防ごうとしていた失敗モードだからです。** LLM ベースの調査では、以下が構造的に必要だと考えます:

1. **一次情報の URL を必ず添えさせる**（検証可能にする）
2. **複数エージェントに独立して調べさせ、食い違いを検出する**
3. **食い違いを専任で潰す**
4. **「未確認」を書くことを明示的に許可・推奨する**（無理に埋めさせない）

「見つからなかった」は立派な成果です。埋めようとした瞬間に捏造が始まります。

---

## D. 未確認事項の一覧

**隠さず列挙します。** 「未確認」は「非対応」ではありません。

### 仕様（[02](02-table-spec.md)）

- v4 の Adaptive Metadata Trees、column families、single-file commits — **ブログ・二次情報のみ。公式マイルストーンには載っていない**（載っているのは相対パスと列統計改善の2提案のみ）
- v4 のタイムライン（「2027年前後」等）— 公式には裏取り不可

### REST Catalog（[03](03-rest-catalog.md)）

- Hive Metastore の具体的批判（Thrift/JVM 必須、ロッキング問題）— Apache の一次情報には見つからず。ベンダーブログ由来
- Hadoop catalog の限界を REST catalog の動機として語る公式記述 — 未発見
- `prefix` = マルチテナント用という明示 — 構造から導かれる強い推測に留まる
- `prefix` に `/` を含められるか — 仕様が明示せず
- `Idempotency-Key` が `CommitStateUnknownException` 対策として導入されたという因果 — 明示的な記述は未発見
- credential vending の「カタログ ACL バイパス防止」動機 — 公式がこの言葉で説明する箇所は未発見
- function 系エンドポイントと SQL UDF spec（#14117）の関係
- iceberg-rust の scan planning 対応状況

### カタログ実装（[04](04-catalog-implementations.md)）

- **Lakekeeper の REST 仕様準拠バージョンとエンドポイント単位の適合表** — 公式 docs にもリポジトリにも記載なし
- **Lakekeeper の本番採用事例** — 公式情報源にゼロ
- Polaris 1.5 の Generic Table vending 拡張 — Snowflake ブログと公式 docs が食い違う
- **S3 Tables ネイティブエンドポイントの vending 有無** — AWS 公式に記述なし、コミュニティでは失敗報告あり
- Glue REST の view / RenameTable 対応、vending ヘッダ機構
- R2 Data Catalog の view 対応と GA 時期
- Gravitino の remote signing 対応と詳細 RBAC モデル
- **Hive Metastore の非推奨化** — **Iceberg 公式に非推奨宣言は存在しない**
- Nessie の長期的な将来 — 2024年の Dremio 発言と2026年の実態が矛盾
- Polaris の TLP 卒業日（Incubator 2026-02-15 vs 公式ブログ 2026-02-19）
- `apache/polaris:latest` の実体バージョン、`iceberg-rest-fixture` の `latest` と `1.10.1` の異同
- Nessie の公式 docker compose 例

### エンジン（[05](05-engine-support.md)）

- **Flink の row lineage 生成（通常書き込みパス）** / **DV 読み取り** / **multi-arg transforms** / **default values 書き込み** — 一次情報を探した限り**本当に見つからなかった**
- Spark 3.5 での row lineage compaction 保存（PR タイトルが "Spark 4.0" 限定）
- Trino / Presto の CoW vs MoR 設定
- **Redshift の Iceberg 書き込み可否** — **本調査で最大の真の未知**
- Databricks の新規 managed テーブルの既定 format version
- Snowflake の externally-managed テーブルにおける MERGE の制限
- Dremio の並行ライタ / 外部エンジンとの競合セマンティクス
- Databricks の foreign Iceberg credential vending（**ブログは GA、REST API docs は非対応。未解決**）

### 運用（[06](06-operations.md)）

- **v3 の DV に対する専用 compaction procedure** — `spark-procedures.md` に見つからず
- **公式なパーティションあたり推奨データ量 / パーティション数上限 / manifest エントリ数 / スナップショット保持推奨値** — **いずれも見つからなかった**（一般に流布する目安に公式の裏付けなし）
- 各エンジンがどのバージョンで remote scan planning を実際に使うか
- S3 Tables / Databricks の `rewrite_manifests` 相当の自動操作 — どちらにも見つからず
- Databricks Predictive Optimization の VACUUM が Iceberg テーブルでどのプロパティを尊重するか

### エコシステム（[07](07-ecosystem.md)）

- Paimon / Iceberg の contributor 所属組織の分布（ベンダー集中度）
- Paimon vs Iceberg の具体的レイテンシ数値 — 一次情報での裏取り不可
- Onehouse が指摘する Databricks の個別制限事項の現時点での正確性（同社は利害関係者）
- UniForm の Hudi 対応の現況
- Iceberg 1.11.0 の機能詳細（VECTOR 型等の有無）

### PyIceberg / ラボ環境

- RustFS の非対応 S3 API 一覧、公式の production readiness 宣言
- SeaweedFS の Console UI 有無・単一コンテナ起動可否
- MinIO object-browser の Console 機能削除の具体的コミット（`github.com/minio/object-browser` が 404）
- `polaris.bootstrap.credentials` が公式 Configuration Reference の表に未掲載（README/compose では確認済み）

---

## E. この報告書を更新するときのチェックリスト

- [ ] **生ソース（raw.githubusercontent.com）から取得したか？** 公式サイトは JS レンダリングで本文が取れない
- [ ] **リリースノートを「現況」の根拠に使っていないか？** 遡及更新されない
- [ ] **PR の実タイトルと変更ファイルを見たか？** リリースノートの要約は誤読を誘う
- [ ] **マイルストーンを確認したか？** マージ済み ≠ リリース済み
- [ ] **docs とブログ/プレスリリースが食い違っていないか？** docs が authoritative
- [ ] **「未確認」を「非対応」と書いていないか？**
- [ ] **数値目安に出典があるか？** なければ「公式な推奨値は見つからなかった」と書く
- [ ] **「GA」が Apache の宣言かベンダーの宣言か区別したか？**
- [ ] **健全性の主張を GitHub API で実測したか？**
- [ ] **実測値の内訳を見たか？** コミット数ならボット比率、比較表なら全セルが同じ指標定義か
- [ ] **仕様の記述から実装の挙動を推論していないか？** 実装の主張には実装の証拠を
- [ ] **動かせる主張は動かして確かめたか？** 読んだだけの主張と区別しているか
- [ ] **公式サンプルに「足したもの」を疑ったか？** 公式が書いていないことに意味がある場合がある
- [ ] **利害関係者（競合ベンダー）の主張であることを明示したか？**
