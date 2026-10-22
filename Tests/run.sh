#!/bin/bash
# Renders every sample with the extension's renderer (built with Address and
# UndefinedBehavior sanitizers) and checks the output.
set -euo pipefail
cd "$(dirname "$0")/.."
ROOT="$PWD"
S="$ROOT/Tests/samples"
CMARK="$ROOT/Vendor/cmark-gfm"
OUT="$(mktemp -d)"
trap 'rm -rf "$OUT"' EXIT

SAN=(-fsanitize=address,undefined -fno-sanitize-recover=undefined -g -O1)
echo "==> Building test harness (ASan + UBSan)"
for f in "$CMARK"/src/*.c "$CMARK"/extensions/*.c; do
  xcrun clang "${SAN[@]}" -std=c99 -w -I"$CMARK/src" -I"$CMARK/extensions" -c "$f" \
    -o "$OUT/$(basename "$(dirname "$f")")_$(basename "${f%.c}").o" &
done
wait
xcrun clang "${SAN[@]}" -fobjc-arc -Wall -Wextra -Werror -I"$CMARK/src" -I"$CMARK/extensions" -ISources/Extension \
  Sources/Extension/MDRender.m Tests/mdrender.m "$OUT"/*.o \
  -framework Foundation -framework UniformTypeIdentifiers -o "$OUT/mdrender"
R="$OUT/mdrender"

fails=0
render() { "$R" "$S/$1" 2>"$OUT/stderr" > "$OUT/out.html"; }
has()    { if grep -qF -- "$1" "$OUT/out.html"; then :; else echo "  FAIL [$CASE] missing: $1"; fails=$((fails+1)); fi; }
hasnt()  { if grep -qF -- "$1" "$OUT/out.html"; then echo "  FAIL [$CASE] unexpected: $1"; fails=$((fails+1)); fi; }
count()  { local n; n=$(grep -oF -- "$1" "$OUT/out.html" | wc -l | tr -d ' '); [ "$n" = "$2" ] || { echo "  FAIL [$CASE] '$1' x$n, want $2"; fails=$((fails+1)); }; }

echo "==> Checking samples"
CASE=kitchen-sink; render kitchen-sink.md
has '<h1>Markdown Preview</h1>'
has '<del>no</del>'
has '<code>code</code>'
has '<kbd>⌘</kbd>'
has '<a href="https://github.com">https://github.com</a>'
has '<a href="http://www.apple.com">www.apple.com</a>'
has '<input type="checkbox" disabled="" /> Task to do'
has '<input type="checkbox" checked="" disabled="" /> Task done'
has '<pre><code class="language-swift">let greeting = &quot;Hello, &lt;world&gt; &amp; \&quot;friends\&quot;&quot;'
has '<pre><code>indented code block'
has '<th align="center">Center</th>'
has '<td align="right">42</td>'
has '<blockquote>
<p>A plain blockquote'
count 'class="alert alert-' 5
has '<blockquote class="alert alert-note">
<p class="alert-title">Note</p>
<p>Useful information.</p>'
has '<p class="alert-title">Caution</p>'
has '<p>[!NOTE] this is not an alert'
has '<section class="footnotes" data-footnotes>'
has 'href="#fn-note"'
count 'src="data:image/png;base64,' 4
has 'src="images/nope.png"'
has 'src="https://example.com/badge.svg"'
has 'alt="raw html image"'
has '<summary>Click to expand</summary>'
has '&lt;script>alert'
hasnt '<script>'
has '&lt;style>body'
has '<mark>highlight</mark>'
has 'AT&amp;T'
has '<br />'
has '<h6>Small heading</h6>'
has "img-src cid: data:"
grep -q "image: $S/images/my dot.png" "$OUT/stderr" || { echo "  FAIL [$CASE] space path not resolved"; fails=$((fails+1)); }

CASE=front-matter; render front-matter.md
has '<pre class="front-matter"><code>title: &quot;Front &lt;matter&gt;&quot;
tags: [a, b]
</code></pre>'
has '<h1>Body heading</h1>'
hasnt '<hr />'

CASE=front-matter-toml; render front-matter-toml.md
has '<pre class="front-matter"><code>title = &quot;TOML&quot;'
has '<h1>TOML body</h1>'

CASE=starts-with-rule; render starts-with-rule.md
hasnt 'front-matter"'
count '<hr />' 2

CASE=setext-not-frontmatter; render setext-not-frontmatter.md
hasnt 'front-matter"'
has '<h2>Title</h2>'

CASE=unclosed-frontmatter; render unclosed-frontmatter.md
hasnt 'front-matter"'
has 'no closing fence'

CASE=empty; render empty.md
has '<article class="markdown-body">
</article>'

CASE=utf8-bom; render utf8-bom.md
has '<h1>UTF-8 BOM heading</h1>'
has 'Café'

CASE=latin1; render latin1.md
has 'Café crème brûlée “quoted”'

CASE=utf16; render utf16.md
has '<h1>UTF-16 heading</h1>'
has 'Café ✅'

CASE=crlf; render crlf.md
has '<h1>Windows line endings</h1>'
has '<li>one</li>'

CASE=nul; render nul.md
has $'nul byte -&gt; \xEF\xBF\xBD &lt;- here'

echo "==> Fuzzing with random input"
for i in $(seq 1 300); do
  head -c $((RANDOM % 4096 + 1)) /dev/urandom > "$OUT/fuzz.md"
  # Mix in Markdown syntax so the parser takes interesting paths.
  printf -- '---\na: b\n> [!NOTE]\n| a | b |\n|---|---|\n![x](y.png "t")<img src=z.png>[^1]\n' >> "$OUT/fuzz.md"
  head -c $((RANDOM % 512 + 1)) /dev/urandom >> "$OUT/fuzz.md"
  "$R" "$OUT/fuzz.md" > /dev/null 2>"$OUT/fuzz.err" || { echo "  FAIL fuzz input crashed"; cat "$OUT/fuzz.err"; cp "$OUT/fuzz.md" "$ROOT/Tests/crash.md"; fails=$((fails+1)); break; }
done

echo "==> Timing (optimised build)"
for f in "$CMARK"/src/*.c "$CMARK"/extensions/*.c; do
  xcrun clang -Os -std=c99 -w -I"$CMARK/src" -I"$CMARK/extensions" -c "$f" \
    -o "$OUT/opt_$(basename "$(dirname "$f")")_$(basename "${f%.c}").o" &
done
wait
xcrun clang -Os -fobjc-arc -I"$CMARK/src" -I"$CMARK/extensions" -ISources/Extension \
  Sources/Extension/MDRender.m Tests/mdrender.m "$OUT"/opt_*.o \
  -framework Foundation -framework UniformTypeIdentifiers -o "$OUT/mdrender-opt"
"$OUT/mdrender-opt" "$S/kitchen-sink.md" --bench 2000
for i in $(seq 1 500); do cat "$S/kitchen-sink.md"; done > "$OUT/big.md"
"$OUT/mdrender-opt" "$OUT/big.md" --bench 20

if [ "$fails" -eq 0 ]; then echo "ALL TESTS PASSED"; else echo "$fails FAILURE(S)"; exit 1; fi
