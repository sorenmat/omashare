#!/usr/bin/env bash
# Smoke test for helpers/omashare-helper using the fake qs. Run: bash test/helper.test.sh
set -u

HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$HERE/.." && pwd)"
FAKEHOME="$(mktemp -d /tmp/omashare-fake.XXXXXX)"
OUTDIR="$FAKEHOME/out"
trap 'rm -rf "$FAKEHOME"' EXIT

mkdir -p "$FAKEHOME/.local/bin" "$OUTDIR"
cp "$HERE/fakeqs" "$FAKEHOME/.local/bin/qs"
chmod +x "$FAKEHOME/.local/bin/qs"

LOG="$FAKEHOME/events.jsonl"

# Run the helper with a HOME that only contains the fake qs, and shut it down
# after the scripted transfer has been observed. The timeout is a hang guard:
# a well-behaved run finishes in under 10s.
( sleep 7; printf '{"command":"shutdown"}\n' ) |
  HOME="$FAKEHOME" timeout 25 bash "$ROOT/helpers/omashare-helper" --out "$OUTDIR" --name TestBox \
  >"$LOG" 2>"$FAKEHOME/err.log"
CODE=$?

fail=0
CUR=0
check() { # $1 description, then fixed patterns that must all occur at/after CUR
  local desc="$1"; shift
  for pat in "$@"; do
    local num
    num="$(awk -v p="$pat" -v after="$CUR" \
      'NR > after || (NR == after && index($0, p)) { if (index($0, p)) { print NR; exit } }' "$LOG")"
    if [[ -z $num ]]; then
      echo "FAIL: $desc — missing event after line $CUR: $pat"
      fail=1
      return
    fi
    CUR=$num
  done
  echo "ok - $desc"
}

check "ready event with settings" \
  '{"event":"ready"' '"deviceName":"TestBox"' '"outDir":"'$OUTDIR'"' '"qsVersion":"qs 0.9.9"'

check "listening after startup" \
  '{"event":"listening"}'

check "transfer starting with unquoted sender" \
  '{"event":"transfer_starting"' '"sender":"Pixel 9"'

check "file received with saved path" \
  '{"event":"file_received"' '"path":"'$OUTDIR'/photo.jpg"'

check "transfer done with file count" \
  '{"event":"transfer_done"' '"fileCount":1'

check "stopped after shutdown command" \
  '{"event":"stopped"}'

if [[ $CODE -ne 0 ]]; then
  echo "FAIL: helper exited with $CODE (expected 0)"
  fail=1
else
  echo "ok - helper exit code 0"
fi

if [[ -f "$OUTDIR/photo.jpg" ]]; then
  echo "ok - file actually written to out dir"
else
  echo "FAIL: expected $OUTDIR/photo.jpg"
  fail=1
fi

# Every stdout line must be valid JSON.
while IFS= read -r line; do
  jq -e . >/dev/null 2>&1 <<<"$line" || { echo "FAIL: non-JSON stdout line: $line"; fail=1; }
done <"$LOG"

echo
if [[ $fail -eq 0 ]]; then
  echo "PASS ($(wc -l <"$LOG") events captured)"
  cat "$LOG" | sed 's/^/  /'
  exit 0
fi
echo "events captured:"
cat "$LOG" | sed 's/^/  /'
echo "stderr:"
cat "$FAKEHOME/err.log" | sed 's/^/  /'
exit 1
