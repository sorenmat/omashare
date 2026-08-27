#!/usr/bin/env bash
# Verify the helper exits promptly when its process group receives TERM
# (which is what happens when the shell kills the helper's process group).
# Run: bash test/term.test.sh
set -u

HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$HERE/.." && pwd)"
FAKEHOME="$(mktemp -d /tmp/omashare-term.XXXXXX)"
trap 'rm -rf "$FAKEHOME"' EXIT

mkdir -p "$FAKEHOME/.local/bin"
cat > "$FAKEHOME/.local/bin/qs" <<'EOF'
#!/usr/bin/env bash
case "${1-}" in
  --version) echo "qs 0.9.9"; exit 0 ;;
  receive)
    echo "Receiving as \"Termed\" — send a file…" >&2
    trap 'exit 0' TERM
    while :; do sleep 1; done
    ;;
esac
EOF
chmod +x "$FAKEHOME/.local/bin/qs"

LOG="$FAKEHOME/events.jsonl"

# setsid gives the helper its own process group, matching how a Quickshell
# Process is supervised; TERM to the group leader takes everyone down.
HOME="$FAKEHOME" setsid bash "$ROOT/helpers/omashare-helper" --out "$FAKEHOME/out" \
  >"$LOG" 2>/dev/null &

sleep 1
HPID="$(ps -eo pid,pgid,args | awk -v p="$ROOT/helpers/omashare-helper" \
  '$2 == $1 && index($0, p) { print $1; exit }')"
if [[ -z $HPID ]]; then
  echo "FAIL: could not find the helper process"
  exit 1
fi
echo "helper (group leader): $HPID"

kill -TERM -- -"$HPID" 2>/dev/null

DEAD=0
for i in $(seq 1 20); do
  if ! kill -0 -- -"$HPID" 2>/dev/null; then DEAD=1; break; fi
  sleep 0.5
done

fail=0
if [[ $DEAD -eq 1 ]]; then
  echo "ok - process group gone within 10s of TERM"
else
  echo "FAIL: process group still alive 10s after TERM"
  kill -9 -- -"$HPID" 2>/dev/null
  fail=1
fi

if grep -q '{"event":"stopped"}' "$LOG"; then
  echo "ok - stopped event emitted on TERM"
else
  echo "FAIL: no stopped event after TERM"
  fail=1
fi

echo
echo "events captured:"
cat "$LOG" | sed 's/^/  /'
exit $(( fail != 0 ))
