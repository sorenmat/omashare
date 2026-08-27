#!/usr/bin/env bash
# When the supervisor's stdin pipe hits EOF without an explicit shutdown
# (the shell process exited, or the service was unloaded), the helper must
# tear itself and its qs child down instead of running on. Run: bash test/eof.test.sh
set -u

HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$HERE/.." && pwd)"
FAKEHOME="$(mktemp -d /tmp/omashare-eof.XXXXXX)"
OUTDIR="$FAKEHOME/out"
trap 'rm -rf "$FAKEHOME"' EXIT

mkdir -p "$FAKEHOME/.local/bin" "$OUTDIR"
cp "$HERE/fakeqs" "$FAKEHOME/.local/bin/qs"
chmod +x "$FAKEHOME/.local/bin/qs"

LOG="$FAKEHOME/events.jsonl"

# `(:)` closes its end of the pipe immediately: the helper's stdin reaches
# EOF the moment it starts, with no shutdown command ever sent.
START=$SECONDS
( : ) | HOME="$FAKEHOME" timeout 15 bash "$ROOT/helpers/omashare-helper" --out "$OUTDIR" \
  >"$LOG" 2>"$FAKEHOME/err.log"
CODE=$?
ELAPSED=$(( SECONDS - START ))

fail=0

if [[ $CODE -ne 0 ]]; then
  echo "FAIL: helper exited with $CODE (expected 0)"
  fail=1
else
  echo "ok - helper exit code 0"
fi

if [[ $ELAPSED -ge 10 ]]; then
  echo "FAIL: helper took ${ELAPSED}s to exit after stdin EOF (expected well under 10s)"
  fail=1
else
  echo "ok - exited after ${ELAPSED}s"
fi

grep -q '"event":"stopped"' "$LOG" \
  && echo "ok - stopped event emitted" \
  || { echo "FAIL: no stopped event on EOF"; fail=1; }

if ps -eo args | grep -F "$FAKEHOME/.local/bin/qs" | grep -v grep >/dev/null; then
  echo "FAIL: qs child survived supervisor EOF"
  ps -eo pid,args | grep -F "$FAKEHOME/.local/bin/qs" | grep -v grep | sed 's/^/  /'
  fail=1
else
  echo "ok - no qs child left behind"
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
