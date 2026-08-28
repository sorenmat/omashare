#!/usr/bin/env bash
# Install the omaShare Omarchy plugin from this folder and enable it in the bar.
#
#   ./install.sh            install this folder into ~/.config/omarchy/plugins
#   ./install.sh --git URL  install from a git remote instead (omarchy plugin add)
#
# Requires the qs CLI (Quick Share client). Use the omaShare fork: upstream
# advertises mDNS records phones cannot resolve, so sends fail or crawl over
# Bluetooth. The fork also pins the receiver to TCP 35353 for firewalls.
#   cargo install --git https://github.com/sorenmat/qs --rev 7a5409bce9ea74140b688598ccc0ddf1730e5c54 --bin qs --root "$HOME/.local/share/omashare"
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
PLUGIN_ID="smo.omashare"
PLUGINS_DIR="$HOME/.config/omarchy/plugins"

have_qs() {
  local p
  for p in "$HOME/.local/share/omashare/bin/qs" "$HOME/.cargo/bin/qs" "$HOME/.local/bin/qs" "$(command -v qs 2>/dev/null || true)"; do
    [[ -n $p && -x $p ]] || continue
    case "$("$p" --version 2>/dev/null | head -n1)" in
      qs\ [0-9]*) printf '%s' "$p"; return 0 ;;
    esac
  done
  return 1
}

if QS_BIN="$(have_qs)"; then
  echo "Found qs: $QS_BIN ($("$QS_BIN" --version 2>/dev/null | head -n1))"
else
  echo "WARNING: the qs CLI (Quick Share client) is not installed:"
  echo '  cargo install --git https://github.com/sorenmat/qs --rev 7a5409bce9ea74140b688598ccc0ddf1730e5c54 --bin qs --root "$HOME/.local/share/omashare"'
  echo "The plugin will install, but show an install hint in the bar until then."
fi

command -v omarchy >/dev/null 2>&1 || { echo "omarchy CLI not found — is Omarchy installed?"; exit 1; }

omarchy plugin validate "$HERE"

if [[ ${1:-} == "--git" && -n ${2:-} ]]; then
  echo "Installing from git: $2"
  omarchy plugin add "$2" --enable
else
  DEST="$PLUGINS_DIR/$PLUGIN_ID"
  mkdir -p "$PLUGINS_DIR"
  if [[ -e $DEST ]]; then
    echo "Refreshing existing install at $DEST"
    rm -rf "$DEST"
  fi
  cp -a "$HERE" "$DEST"
  echo "Installed to $DEST"
  omarchy plugin enable "$PLUGIN_ID" --section right
fi

echo
echo "Done. Restart the shell to load the plugin:"
echo "  omarchy restart shell"
echo "Then open Quick Share on your phone — this machine should appear as a device."
