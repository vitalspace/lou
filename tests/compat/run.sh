#!/usr/bin/env bash
set -u
set -o pipefail
cd "$(dirname "$0")/../.."

PASS=0
FAIL=0
SKIP=0
RESULTS=()

for lou in tests/compat/*.lou; do
  js="${lou%.lou}.js"
  name="$(basename "$lou")"

  if [ ! -f "$js" ]; then
    RESULTS+=("SKIP  $name  (no .js counterpart)")
    SKIP=$((SKIP+1))
    continue
  fi

  # Normalize: collapse multi-line node array printing to a single line and
  # remove cosmetic whitespace so formatting differences don't mask real bugs.
  normalize() {
    python3 -c '
import sys, re
text = sys.stdin.read()
# console.time/timeEnd output is nondeterministic; never compare its value.
text = re.sub(r"(?m)^[^\n]*:\s*[0-9]+(?:\.[0-9]+)?\s*(?:ns|µs|us|ms|s)\s*$", "", text)
def collapse(m):
    inner = m.group(1)
    items = []
    for tok in re.findall(r"[^,\s][^,]*[^,\s]|[^,\s]", inner):
        items.append(tok.strip())
    return "[" + ",".join(items) + "]"
text = re.sub(r"\[\s*\n([^\]]*?)\n\s*\]", collapse, text, flags=re.S)
# collapse ", " -> "," and "[ " -> "[" in array literals for comparison
text = re.sub(r",\s+", ",", text)
text = re.sub(r"\[\s+", "[", text)
text = re.sub(r"\s+\]", "]", text)
print(text, end="")
'
  }
  lou_out=$(./zig-out/bin/lou run "$lou" 2>&1 | sed -E 's/\x1b\[[0-9;]*m//g' | normalize)
  lou_exit=$?
  js_out=$(node "$js" 2>&1 | sed -E 's/\x1b\[[0-9;]*m//g' | normalize)
  js_exit=$?

  if [ "$lou_out" = "$js_out" ] && [ "$lou_exit" = "$js_exit" ]; then
    RESULTS+=("PASS  $name")
    PASS=$((PASS+1))
  else
    RESULTS+=("FAIL  $name")
    FAIL=$((FAIL+1))
    diff_out=$(diff <(echo "$lou_out") <(echo "$js_out") || true)
    RESULTS+=("$diff_out")
  fi
done

printf '%s\n' "${RESULTS[@]}"
echo "---"
echo "PASS=$PASS  FAIL=$FAIL  SKIP=$SKIP"
