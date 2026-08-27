#!/usr/bin/env bash
# `check-firewall` reads ufw's world-readable config and reports one JSON
# line: whether the receiver port is allowed, and the exact pkexec command
# that would fix it (empty when nothing is needed). Run: bash test/firewall.test.sh
set -u

HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$HERE/.." && pwd)"
HELPER="$ROOT/helpers/omashare-helper"

fail=0

# Fixture: a ufw config dir with ENABLED=yes and optional port rules.
mkfw() {
  local dir
  dir="$(mktemp -d /tmp/omashare-fw.XXXXXX)"
  printf 'ENABLED=yes\n' >"$dir/ufw.conf"
  {
    echo '*filter'
    echo ':ufw-user-input - [0:0]'
    if [[ ${1-} == rule ]]; then
      echo "-A ufw-user-input -p tcp --dport ${2-35353} -j ACCEPT"
    fi
    echo 'COMMIT'
  } >"$dir/user.rules"
  printf '%s' "$dir"
}

check() { # name expected-open expected-fix-nonempty json
  local name=$1 want_open=$2 want_fix=$3 json=$4
  local open fix
  open="$(jq -r '.portOpen' <<<"$json")"
  fix="$(jq -r 'if .fixCommand == "" then "empty" else "nonempty" end' <<<"$json")"
  if [[ $open == "$want_open" && $fix == "$want_fix" ]]; then
    echo "ok - $name"
  else
    echo "FAIL: $name (portOpen=$open fixCommand=$fix): $json"
    fail=1
  fi
}

# 1. ufw enabled, no allow rule: blocked, with the fix command.
D="$(mkfw norule)"
J="$(UFW_DIR="$D" "$HELPER" check-firewall)"
check "blocked without rule reports fix" false nonempty "$J"
jq -e '.event == "firewall" and .port == 35353 and (.fixCommand | test("ufw allow in 35353/tcp"))' \
  <<<"$J" >/dev/null || { echo "FAIL: fields: $J"; fail=1; }
rm -rf "$D"

# 2. ufw enabled, rule for the port: open, nothing offered.
D="$(mkfw rule)"
J="$(UFW_DIR="$D" "$HELPER" check-firewall)"
check "open with rule" true empty "$J"
rm -rf "$D"

# 3. Rule for a different port does not count; --port is honored.
D="$(mkfw rule 35352)"
J="$(UFW_DIR="$D" "$HELPER" check-firewall)"
check "other port's rule does not match" false nonempty "$J"
rm -rf "$D"

# 4. ufw installed but disabled: nothing to fix.
D="$(mktemp -d /tmp/omashare-fw.XXXXXX)"
printf 'ENABLED=no\n' >"$D/ufw.conf"
J="$(UFW_DIR="$D" "$HELPER" check-firewall)"
check "disabled ufw is not blocking" true empty "$J"
rm -rf "$D"

if (( fail )); then
  echo "FAIL"
  exit 1
fi
echo "PASS"
