#!/usr/bin/env bash
# 報告書全体を1つの PDF に組んで _site/ に置く。ファイル名は
# iceberg-research-<版>.pdf で、版は VERSION から来る（scripts/set-version.sh 参照）。
#
# サイト本体は website 型で、website は複数ページを1つの PDF にまとめられない。
# そのため本文を .pdf-build/ にコピーし、book 型（scripts/quarto-pdf.yml）で組み直す。
# コピーしてから加工するのは、HTML 側の出力を一切変えないため。
#
# 必要なもの: quarto / lualatex + luatexja / Noto CJK フォント / Chrome（mermaid の描画）
set -euo pipefail

cd "$(dirname "$0")/.."

BUILD_DIR=.pdf-build
SITE_DIR=_site

# 版がずれていると、ナビの PDF リンクだけ存在しないファイルを指す（404 になる）。
# レンダリングに時間をかける前に止める。
scripts/set-version.sh --check
VERSION="$(tr -d '[:space:]' <VERSION)"

rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR"

cp index.md fact-check-report.md "$BUILD_DIR/"
cp -r docs "$BUILD_DIR/"
cp scripts/quarto-pdf.yml "$BUILD_DIR/_quarto.yml"

# Quarto は実行セルを含むファイルに .qmd を要求するので、コピーを .qmd に改名し、
# 本文中の相対リンクも合わせて張り替える（http(s) の外部リンクは触らない）。
find "$BUILD_DIR" -name '*.md' -print0 | while IFS= read -r -d '' f; do
	mv "$f" "${f%.md}.qmd"
done
find "$BUILD_DIR" -name '*.qmd' -print0 |
	xargs -0 perl -pi -e 's/\]\((?!\w+:)([^)#]+)\.md([)#])/](\1.qmd\2/g'

# HTML では ```mermaid をブラウザ側で描いている（_includes-mermaid.html）が、
# PDF ではそれが使えないので Quarto の実行セルに変換して画像に落とす。
find "$BUILD_DIR" -name '*.qmd' -print0 |
	xargs -0 sed -i -E 's/^```[[:space:]]*mermaid[[:space:]]*$/```{mermaid}/'

# mermaid は "…" で囲んだラベルを markdown として解釈するため、「10. 接続…」のような
# 書き出しが箇条書きと誤認され、図のラベルが "Unsupported markdown: list" に化ける。
# mermaid ブロック内のラベル先頭に限ってピリオドを退避する（本文の箇条書きには触らない）。
find "$BUILD_DIR" -name '*.qmd' -print0 |
	xargs -0 perl -0777 -pi -e 's{(```\{mermaid\}\n)(.*?\n)(```)}{
		my ($open, $body, $close) = ($1, $2, $3);
		$body =~ s/(?<=")(\d+)\. /$1\\. /g;
		$body =~ s{(<br/>)(\d+)\. }{$1$2\\. }g;
		"$open$body$close"
	}gse'

quarto render "$BUILD_DIR" --to pdf

mkdir -p "$SITE_DIR"
# 手元で版を上げながら組み直すと古い版が _site/ に残るので、置く前に掃除する
# （CI は quarto render が _site/ を作り直すため、そちらでは元から残らない）。
rm -f "$SITE_DIR"/iceberg-research-*.pdf
cp "$BUILD_DIR/_pdf/iceberg-research-$VERSION.pdf" "$SITE_DIR/"

echo "PDF を $SITE_DIR/ に配置した:"
ls -la "$SITE_DIR"/*.pdf
