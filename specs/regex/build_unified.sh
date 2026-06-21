#!/usr/bin/env bash
# =============================================================================
# build_unified.sh — Generates run_all.js from individual suite files
#
# Extracts the test body (everything above the STANDALONE MODE marker) from
# each suite file and assembles them into a single unified runner with
# beginSuite/endSuite wrappers.
#
# Run:  bash build_unified.sh
# Then: lou run run_all.js
# =============================================================================
set -euo pipefail

DIR="$(cd "$(dirname "$0")" && pwd)"
OUT="$DIR/run_all.js"
FMWK="$DIR/test-framework.js"

# Start with framework
cp "$FMWK" "$OUT"

# Suite definitions: (name, file)
SUITES=(
  "01-basic:$DIR/01-basic.js"
  "02-advanced:$DIR/02-advanced.js"
  "03-exec-basic:$DIR/03-exec-basic.js"
  "04-exec-named:$DIR/04-exec-named-groups.js"
  "05-exec-edge:$DIR/05-exec-edge.js"
  "06-lookaround-boundary:$DIR/06-lookaround-boundary.js"
  "07-unicode-escapes:$DIR/07-unicode-escapes.js"
)

for entry in "${SUITES[@]}"; do
  name="${entry%%:*}"
  file="${entry#*:}"

  echo >> "$OUT"

  # Extract test body: everything from first line up to (but not including)
  # the STANDALONE MODE marker
  awk '
    /STANDALONE MODE/ { exit }
    { print }
  ' "$file" | sed '/^[[:space:]]*$/d' > /tmp/_suite_body.js

  # Count lines of test body
  BODY_LINES=$(wc -l < /tmp/_suite_body.js)
  if [ "$BODY_LINES" -le 2 ]; then
    echo "WARNING: $file has no test body (empty or only header). Skipping."
    continue
  fi

  # Extract short numeric prefix for registerSuite call (e.g., "01" from "01-basic")
  short="${name%%-*}"

  echo "beginSuite(\"$name\");" >> "$OUT"
  cat /tmp/_suite_body.js >> "$OUT"
  echo "registerSuite_$short();" >> "$OUT"
  echo "endSuite();" >> "$OUT"
done

# Add final report
echo "" >> "$OUT"
echo "reportResults();" >> "$OUT"

rm -f /tmp/_suite_body.js
echo "Generated: $OUT"
