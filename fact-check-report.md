# ファクトチェック報告書

**対象**: 本リポジトリの調査報告書（README.md + docs/*.md、3,357行、106 URL）
**実施日**: 2026-07-17
**手法**: 全 URL の一括取得（Puppeteer）+ 独立した3系統の主張検証（一次情報ベース）+ GitHub API / PyPI API による実測のやり直し
**方針**: **報告書の主張を追認せず、反証を探す立場**で検証

---

## サマリ

| 判定 | 件数 |
|---|---|
| 検証済み（一次情報と一致） | 大多数（デフォルト値11件、v3 リリース経緯、ベンダー GA/Preview 判定4件など） |
| **不正確 — 修正済み** | **2件（うち1件は結論に影響）** |
| **誤解を招く — 修正済み** | **4件** |
| リンク切れ — 修正済み | 2件 |
| 陳腐化 — 更新済み | 3件 |

**結論: 報告書の大枠の論旨は維持されましたが、2つの実質的な誤りが見つかり修正しました。** いずれも一次情報には当たっていたものの、記述の解釈が不十分だったことによるものです。

---

## 重大な誤り（修正済み）

### 1. 「`format-version=4` は設定できない」— **誤り**

**初版の記述**:

> 2026年7月時点で `format-version=4` は設定できません。

**実際**（`TableMetadata.java` をリリースタグごとに実測）:

| タグ | `SUPPORTED_TABLE_FORMAT_VERSION` |
|---|---|
| apache-iceberg-1.8.0 | 3 |
| apache-iceberg-1.9.0 | 3 |
| **apache-iceberg-1.10.0**（2025-09-11） | **4** |
| apache-iceberg-1.11.0 | 4 |

バリデーションは `formatVersion <= SUPPORTED_TABLE_FORMAT_VERSION` なので、**Iceberg Java 1.10.0 以降 `format-version=4` は通過します**。さらに main には v4 機能のゲートが存在します:

```java
static final int MIN_FORMAT_VERSION_PARQUET_MANIFESTS = 4;
static final int MIN_FORMAT_VERSION_OPTIONAL_LOCATION = 4;
```

一方 **PyIceberg 0.11.1 は `TableVersion = Literal[1, 2, 3]` で受理しません**。

**誤りの構造**: 仕様の「未採択」という記述から、実装も同様に拒否するという**推論**が入っていた。仕様と実装は別のものであり、実装の挙動を述べるには実装側の証拠が必要になる。

**実務上の含意も逆転します**: 「作れないから安全」ではなく、**「作れてしまうので、仕様変更のリスクを自分で避ける必要がある」**。

**修正**: [02-table-spec.md](docs/02-table-spec.md#v4-metadata-structure-and-representation--未採択ただし実装は先行している) を全面改稿。README・07 の波及箇所も修正。方法論に [B-13](docs/99-methodology.md) として記録。

### 2. 健全性シグナルのボット混入 — **結論に影響**

**初版の記述**:

> Nessie は直近52週 1,630 コミット、contributor 79名で**活発に開発継続中**

**実際**（GitHub API で内訳を実測）:

| プロジェクト | 総コミット（365日） | ボット | **人間** |
|---|---|---|---|
| Iceberg | 1,696 | 309（18.2%、dependabot） | 1,387 |
| Paimon | 2,278 | 13（0.6%） | **2,265** |
| Hudi | 1,141 | 4（0.4%） | 1,137 |
| Delta Lake | 1,203 | **0** | 1,203 |
| **Nessie** | 1,652 | **1,407（85.2%、renovate）** | **245** |
| **Polaris** | 2,100 | 744（35.4%、renovate） | 1,356 |

**ボット比率が 0.4%〜85% と2桁違うため、生コミット数の横並び比較が成立していませんでした。**

壊れていた結論:

1. **Nessie の「活発」は幻**。人間コミット 245 件、しかも実質1人（`snazy` が 212、残り全員で 33）。ユニーク作者 22人（Iceberg 270 の 1/12）
2. **Polaris と Iceberg の順位が逆転**。生 2,100 > 1,696 だが、人間 1,356 < 1,387
3. **Paimon の優位を過小評価**。生 1.34倍 → 人間 **1.63倍**

**加えて指標定義の混在**: 「Iceberg 267 / Paimon 164」は直近365日のユニーク作者、「Polaris 156 / Nessie 79」は全期間 contributor で、同じ表に並べていた。しかも「Iceberg は contributor 数で突出」は**直近365日でのみ成立**し、全期間では Iceberg 407 / Delta 391 / Hudi 382 / Paimon 363 と**ほぼ横並び**。

**修正**: [07-ecosystem.md](docs/07-ecosystem.md#a-2-健全性シグナル2026-07-17-実測) の表にボット除外値を併記。[04](docs/04-catalog-implementations.md) の Nessie 評価を「活発」→「retire はされていないが実質は少数保守モード」に修正。方法論に [B-12](docs/99-methodology.md) として記録。

---

## 誤解を招く記述（修正済み）

| # | 初版 | 実際 | 対応 |
|---|---|---|---|
| 3 | Polaris 卒業日の食い違いは「2026-02-15 vs 02-19 の2つ」。incubator ページは「projected 扱いで stale」 | **公式ソース3つが3つとも違う**（ブログ 02-19 / ステータスページ 02-15 / プロジェクト一覧 **02-18**）。後者2つは同一ドメイン内の自己矛盾。**「projected」の語はページ全文に0件**で、確定形で書かれている | 3つ巴として記載、日付を断定しない方針に。「projected」の記述を削除 |
| 4 | Iceberg 1.11.0 = **2026-05-20** | **2026-05-19**（公式サイト「released on May 19, 2026」、git tag の tagger date）。05-20 は GitHub 上でリリースノートを公開した操作時刻に過ぎない | 2026-05-19 に統一 |
| 5 | v4 節に相対パスと `content_stats` が書かれている | v4 概要節と Appendix E が挙げるのは**相対パスのみ**。`content_stats` は別の「Content Stats」節とマニフェストスキーマに記述 | 記載場所を訂正 |
| 6 | Open Catalog の「Billing will begin in the first half of 2026」を引用 | 記述は実在するが、**現在7月で H1 は経過済み。docs が更新されていない**（同ページは今も "free to use" とも述べる） | 「決着つかず」として注記済み（初版から記載あり） |

---

## リンク切れ（修正済み）

106 URL を一括取得した結果:

| ステータス | 件数 |
|---|---|
| 200 | 95 |
| 304（キャッシュ） | 1 |
| 403（ボット遮断） | 2 |
| **404** | **7** |
| タイムアウト | 1 |

**404 のうち5件は本報告書の URL 抽出時のバッククォート混入**（Markdown のコードスパン内 URL）で、実際のリンクは生きていました（再テストで全て 200）。

**本物の問題は2件**:

| URL | 問題 | 修正 |
|---|---|---|
| `docs.aws.amazon.com/.../API_s3tables_PutTableMaintenanceConfiguration.html` | **404**（API 索引にリダイレクト）。**正しくは `API_s3Buckets_...`** | 修正済み。`GetTableMaintenanceJobStatus` のリンクも追加 |
| `paimon.apache.org/docs/master/iceberg/overview/` | **404**。`docs/1.4/` なら 200 | バージョン固定 URL に変更 |

**その他**:

- `prestodb.io`（403）: 適切な UA なら 200。ボット遮断であり生きている
- `bigdatawire.com`（403 + リダイレクト）: **ドメインが `hpcwire.com/bigdatawire/` に移転**。移転先に更新済み（ニュースサイトのため 403 は継続）
- oreilly conferences PDF: Puppeteer ではタイムアウトしたが curl では 200（低速なだけ）

---

## 陳腐化（更新済み）

| 項目 | 初版 | 実測（2026-07-17） |
|---|---|---|
| Nessie 最新版 | 0.108.1（2026-06-24） | **0.108.2（2026-07-17、検証当日にリリース）** |
| RustFS 最新版 | 1.0.0-beta.10-preview.4（2026-07-16） | **1.0.0-beta.10（2026-07-17）**。preview.5 と beta.10 が後続。**数時間おきにリリースされており、特定版の記載は公開時点で必ず古くなる** |
| Hudi「最新リリース」 | 1.2.0（2026-05-23） | 正しいが、**その後 0.14.2（2026-06-08）が公開**。`published_at` 順では 0.14.2 が最新（旧系列の保守リリース） |

---

## 検証済み（一次情報と一致）

以下は独立した検証で**一次情報と逐語レベルで一致**しました。

### 仕様
- 「Version 4 is under active development and has not been formally adopted.」が `format/spec.md` に現存
- 「Versions 1, 2 and 3 ... complete and adopted by the community」も同様
- **V4 マイルストーン #58 は Open 2 / Closed 0、期日なし**（#13153 Column Stats Improvements、#13141 Relative Path Support）— GitHub API で確認、件数の変化なし
- 「File System Tables は v4 で削除予定」

### デフォルト値（`configuration.md` の11項目すべて）
`format-version`=2 / `write.{delete,update,merge}.mode`=copy-on-write / `write.target-file-size-bytes`=536870912 / `write.delete.target-file-size-bytes`=67108864 / `write.parquet.compression-codec`=zstd / `write.metadata.metrics.default`=truncate(16) / `max-inferred-column-defaults`=100 / `delete-after-commit.enabled`=false / `previous-versions-max`=100 / `history.expire.max-snapshot-age-ms`=432000000 / `commit.retry.num-retries`=4

### v3 のリリース経緯
1.8.0 / 1.9.0 / 1.10.0 / 1.11.0 の各項目が `releases.md` の記述と一致

### 「Apache は v3 を GA と宣言していない」
リポジトリを clone し `format/`・`site/docs/`（全ブログ記事含む）・`docs/docs/` を全文検索。**"generally available" / "general availability" / "GA" のヒット 0 件**。公式表現は一貫して "complete and adopted by the community"。

> **補足を追加すべき点**: ASF はそもそも "GA" をリリース区分に用いない慣行があるため、「GA 宣言がない = v3 が未成熟」と読ませる論法には注意が必要です。

### ベンダーの GA/Preview 判定（4件すべて）
- **Databricks v3 = GA**: 2026-04-09 Preview → **2026-05-28 GA**。GA ブログに「**Iceberg v3 (GA)**」の逐語あり。docs に Preview バナーなし。非対応リスト（defaults / unknown 型 / ns timestamp / multi-arg transforms）も逐語一致
- **Snowflake v3 = GA + 外部エンジン write 対応**: **2026-05-26 のリリースノートが実在**し「read and write to Snowflake-managed Iceberg **v2 and v3** tables」と明記。5/7 の制約記述は当時正しく、5/26 に解消
- **Dremio v3 = Preview**: docs に **"Iceberg v3 Preview"** の見出しが現存。「v2 remains the default format version in Dremio」も逐語一致。Software 側 docs に v3 の記述なし
- **Open Catalog は新規顧客にクローズ**: 逐語4点すべて存在

### プロジェクトの状態
- XTable はまだ incubating（2024-02-11 incubation 入り、卒業記載なし）
- Nessie は `archived: false`
- **Hive は Attic に入っていない**（`attic.apache.org/projects.html` 全文検索でヒットは Beehive / HiveMind のみ）。Hive 4.2.0 = 2025-11-23 も公式表記と一致
- **minio/minio は 2026-04-25 アーカイブ**（GraphQL `archivedAt` で確認）、**ライセンスは AGPLv3 のまま**
  > **注**: REST API の `archived_at` は null を返すため、**GraphQL でなければアーカイブ日時を取得できません**。初版が示した検証手順は不完全でした
- PyIceberg 0.11.1 = 2026-03-03（PyPI `upload_time_iso_8601`）
- iceberg-python#1551 / iceberg#14638 / prestodb/presto#27198 すべて Open

### 健全性の数値（ボット問題を除く）
実測とのずれは全て +1〜+20 程度で、測定日差の増分として整合。桁も順位も動かず。

---

## 方法論への反映

この検証で見つかった2つの失敗パターンを、[99-methodology.md](docs/99-methodology.md) に追加しました。

- **B-12: 実測値も、指標の定義を疑わないと嘘になる** — 「測った」で終わらせず、内訳を見る
- **B-13: 「未採択」と「実装が受け付けない」は別物** — 仕様から実装の挙動を推論しない

チェックリストにも追加:

- [ ] 実測値の内訳を見たか？（ボット比率、指標定義の統一）
- [ ] 仕様の記述から実装の挙動を推論していないか？

---

## この検証の限界

- **エンジン対応状況（Spark / Flink / Trino / Presto）の個別主張は再検証していません。** 初版の調査時に一次情報で確認済みですが、今回のファクトチェックの対象外です
- **Onehouse（競合ベンダー）が指摘する Databricks の制限事項**は独立検証していません
- **URL の死活は確認しましたが、106 件すべての内容一致（D-CONTENT）は検証していません。** 高優先の主張に絞っています
- 検証は 2026-07-17 時点のスナップショットです
