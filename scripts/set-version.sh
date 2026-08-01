#!/usr/bin/env bash
# 報告書の版（VERSION の中身）を各設定ファイルに反映する。
#
# 版は日付（YYYY-MM-DD）で、報告書を発行した日を指す。調査基準日とは別物。
# 版は次の7箇所に入る。手で直すと必ずどこかを取りこぼすので、書き換えはここに寄せてある。
#
#   _quarto.yml            ナビの PDF リンク / ページフッタの Version
#   scripts/quarto-pdf.yml 表紙の日付 / PDF のファイル名 / 全ページのフッタ
#   index.md               冒頭の Version 表記 / 本文中の PDF リンク
#
#   scripts/set-version.sh          VERSION の値を上記へ書き込む
#   scripts/set-version.sh --check  ずれていたら非ゼロで終わる（書き換えない）
#
# --check は scripts/build-pdf.sh の冒頭で呼んでいる。ナビのリンクだけ古い版を
# 指したまま公開すると、サイトの PDF リンクが 404 になるため。
#
# 版を上げる手順:
#   1. VERSION を新しい日付に書き換える
#   2. scripts/set-version.sh を実行する
#   3. VERSION と書き換わった設定ファイルをまとめてコミットする
set -euo pipefail

cd "$(dirname "$0")/.."

CHECK=false
[[ "${1-}" == "--check" ]] && CHECK=true

VERSION="$(tr -d '[:space:]' <VERSION)"
if [[ ! "$VERSION" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}$ ]]; then
	echo "エラー: VERSION は YYYY-MM-DD で書く（実際の中身: '$VERSION'）" >&2
	exit 1
fi

D='[0-9]{4}-[0-9]{2}-[0-9]{2}'

# 設定ファイルには版以外の日付（調査基準日など）も書いてあるので、
# 版の行だけを狙って置き換える。想定した箇所数に届かなければ後段で止める。
stamp() {
	case "$1" in
	_quarto.yml)
		sed -E \
			-e "s|(href: /iceberg-research)-$D(\.pdf)|\1-$VERSION\2|" \
			-e "s/(Version: )$D/\1$VERSION/" \
			"$1"
		;;
	scripts/quarto-pdf.yml)
		sed -E \
			-e "s/^(  date: )\"$D\"/\1\"$VERSION\"/" \
			-e "s/^(  output-file: \"iceberg-research)-$D\"/\1-$VERSION\"/" \
			-e "s/(\\\\ofoot\*\{\\\\footnotesize Version )$D\}/\1$VERSION}/" \
			"$1"
		;;
	index.md)
		sed -E \
			-e "s/(\*\*Version: )$D\*\*/\1$VERSION**/" \
			-e "s|(\]\(/iceberg-research)-$D(\.pdf\))|\1-$VERSION\2|" \
			"$1"
		;;
	esac
}

# ファイルごとに「版が入っているはずの箇所数」。書式を変えて置換が空振りしたら気付ける。
declare -A EXPECTED=(
	[_quarto.yml]=2
	[scripts/quarto-pdf.yml]=3
	[index.md]=2
)

failed=false
for f in _quarto.yml scripts/quarto-pdf.yml index.md; do
	stamped="$(stamp "$f")"

	hits="$(grep -c -- "$VERSION" <<<"$stamped" || true)"
	if [[ "$hits" -ne "${EXPECTED[$f]}" ]]; then
		echo "エラー: $f 内で版を差し込む箇所が ${EXPECTED[$f]} つ見つからない（見つかったのは $hits 箇所）。" >&2
		echo "       書式を変えたなら scripts/set-version.sh も直すこと。" >&2
		exit 1
	fi

	if [[ "$CHECK" == true ]]; then
		if ! diff -q <(printf '%s\n' "$stamped") "$f" >/dev/null; then
			echo "エラー: $f の版が VERSION（$VERSION）と食い違っている。" >&2
			diff -u "$f" <(printf '%s\n' "$stamped") || true
			failed=true
		fi
	else
		printf '%s\n' "$stamped" >"$f"
	fi
done

if [[ "$CHECK" == true ]]; then
	if [[ "$failed" == true ]]; then
		echo "scripts/set-version.sh を実行して差分をコミットすること。" >&2
		exit 1
	fi
	echo "版は一致している: $VERSION"
else
	echo "版 $VERSION を反映した。"
fi
