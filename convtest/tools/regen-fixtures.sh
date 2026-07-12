#!/bin/zsh
# Regenerates every fixture in convtest/samples from scratch.
# The generated files are committed; this script exists so they can be
# rebuilt or extended deterministically. Requirements: macOS (textutil,
# sips, cupsfilter), python3, node with `npm i -g pptxgenjs`, Xcode
# (DEVELOPER_DIR for the swift fixture generator).
set -euo pipefail
cd "$(dirname "$0")/.."
SAMPLES="$PWD/samples"
TOOLS="$PWD/tools"
BUILD="$(mktemp -d)"
trap 'rm -rf "$BUILD"' EXIT
mkdir -p "$SAMPLES"

# ---------- plain text / csv / tsv / html ----------
printf 'First line with trailing spaces   \r\nSecond line\r\n\r\n\r\n\r\nAfter three blanks\r\nDone\r\n' > "$SAMPLES/sample.txt"

printf 'city\tpop\tnote\nParis\t2.1M\t"Left bank\tright bank"\nLyon\t0.5M\tfood capital\n' > "$SAMPLES/sample.tsv"

cat > "$SAMPLES/sample.csv" <<'EOF'
name,role,notes
Alice,"Engineer, Senior","Likes ""clean"" code
and short meetings"
Bob,Designer,Plain note
Carol,PM
EOF

cat > "$SAMPLES/sample.html" <<'EOF'
<!DOCTYPE html>
<html>
<head>
  <title>Should never appear</title>
  <style>body { color: red; }</style>
  <script>console.log("nor this");</script>
</head>
<body>
  <h1>Quarterly Report &amp; Outlook</h1>
  <p>Revenue grew <strong>18%</strong> year-over-year — see the <a href="https://example.com/q3">full Q3 numbers</a>.
     Costs were <em>flat</em>&nbsp;overall.</p>

  <h2>Highlights</h2>
  <ul>
    <li>Shipped v2.0 with <code>async/await</code> support</li>
    <li>Opened offices in:
      <ol>
        <li>Berlin</li>
        <li>Tokyo</li>
      </ol>
    </li>
    <li>Churn below 2&#37;</li>
  </ul>

  <h2>Numbers</h2>
  <table>
    <tr><th>Region</th><th>Revenue</th><th>Change</th></tr>
    <tr><td>EMEA</td><td>$4.2M</td><td>+22%</td></tr>
    <tr><td>APAC</td><td>$3.1M</td><td>+9%</td></tr>
    <tr><td>Missing cell row</td><td>$0.9M</td></tr>
  </table>

  <blockquote>
    <p>The best quarter in the company&rsquo;s history.</p>
  </blockquote>

  <pre><code>let total = regions.map(\.revenue).reduce(0, +)
print("Total: \(total)")</code></pre>

  <p>Math check: 5 &lt; 6 &amp;&amp; 7 &gt; 2. Unclosed bold next: <b>bold text.
  <hr>
  <p>Image: <img src="chart.png" alt="Revenue chart"> and an anchor with no href: <a name="x">plain</a>.</p>
</body>
</html>
EOF

# ---------- PDFs ----------
cupsfilter "$SAMPLES/sample.txt" > "$SAMPLES/sample.pdf" 2>/dev/null
# image-only "scan" of the text pdf (no font objects => OCR path)
sips -s format png -s dpiHeight 200 -s dpiWidth 200 --resampleWidth 1700 \
  "$SAMPLES/sample.pdf" --out "$BUILD/scan-page.png" >/dev/null 2>&1
sips -s format pdf "$BUILD/scan-page.png" --out "$SAMPLES/scanned.pdf" >/dev/null 2>&1
# a JPEG-bearing PDF for image extraction
sips -s format jpeg "$BUILD/scan-page.png" --out "$BUILD/photo.jpg" >/dev/null 2>&1
cupsfilter "$BUILD/photo.jpg" > "$SAMPLES/photo.pdf" 2>/dev/null
# multi-column fixtures
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift "$TOOLS/gen2col.swift" "$SAMPLES"

# ---------- textutil-generated office files ----------
cat > "$BUILD/office-src.html" <<'EOF'
<html><body>
<h1>Annual Report</h1>
<p>This year was <b>excellent</b> with <i>strong</i> growth.</p>
<h2>Details</h2>
<ul><li>Revenue up</li><li>Costs down</li></ul>
<ol><li>First step</li><li>Second step</li></ol>
<table><tr><th>Q</th><th>Value</th></tr><tr><td>Q1</td><td>10</td></tr><tr><td>Q2</td><td>20</td></tr></table>
<p>Closing remarks here.</p>
</body></html>
EOF
textutil -convert docx -output "$SAMPLES/sample.docx" "$BUILD/office-src.html"
textutil -convert doc  -output "$SAMPLES/sample.doc"  "$BUILD/office-src.html"
textutil -convert rtf  -output "$SAMPLES/sample.rtf"  "$BUILD/office-src.html"

# ---------- hand-crafted OOXML fixtures ----------
python3 "$TOOLS/build-ooxml-fixtures.py" "$SAMPLES"

# ---------- pptxgenjs real-world deck ----------
NODE_PATH="$(npm root -g)" node "$TOOLS/make-real-pptx.cjs" "$SAMPLES"

echo "fixtures regenerated into $SAMPLES"
