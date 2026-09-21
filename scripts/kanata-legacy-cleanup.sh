#!/usr/bin/env bash
#
# kanata-legacy-cleanup.sh
#
# One-time migration helper: removes artifacts from the OLD Kanata.spoon
# installation method (custom LaunchDaemon, non-Homebrew binaries, log dir).
#
# Safe to run on a machine that is already fully migrated — it will simply
# report "nothing found" for each item.
#
# What this script removes:
#   • /Library/LaunchDaemons/com.example.kanata.plist   (old spoon daemon)
#   • ~/Library/LaunchAgents/com.example.kanata.plist   (old user agent)
#   • /Library/Logs/Kanata/                             (old log directory)
#   • Non-Homebrew kanata binaries at known custom paths
#
# What this script deliberately leaves alone:
#   • ~/.config/kanata/                                 (your config files)
#   • /opt/homebrew/  and  /usr/local/  Homebrew paths  (current install)
#   • /Library/LaunchDaemons/homebrew.mxcl.kanata.plist (brew service)
#   • Karabiner-Elements
#
# Run directly in Terminal. Privileged operations use the normal sudo prompt.
#

set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=_admin.sh
source "$SCRIPT_DIR/_admin.sh"
# shellcheck source=_progress.sh
source "$SCRIPT_DIR/_progress.sh"

# ── colours ────────────────────────────────────────────────────────────────
RED=$'\033[0;31m'; YELLOW=$'\033[0;33m'; GREEN=$'\033[0;32m'
BOLD=$'\033[1m'; RESET=$'\033[0m'

info()    { echo "${BOLD}$1${RESET}"; }
success() { echo "${GREEN}✅ $1${RESET}"; }
warning() { echo "${YELLOW}⚠️  $1${RESET}"; }
removed() { echo "${GREEN}🗑  Removed: $1${RESET}"; }
skipped() { echo "   (not found — nothing to do)"; }

# ── header ─────────────────────────────────────────────────────────────────
echo
echo "${BOLD}╔══════════════════════════════════════════════════════════╗${RESET}"
echo "${BOLD}║         Kanata Legacy Installation Cleanup               ║${RESET}"
echo "${BOLD}╚══════════════════════════════════════════════════════════╝${RESET}"
echo
echo "This script removes artifacts from the OLD Kanata installation"
echo "that can conflict with the current Homebrew-based setup:"
echo
echo "  • /Library/LaunchDaemons/com.example.kanata.plist"
echo "  • ~/Library/LaunchAgents/com.example.kanata.plist"
echo "  • /Library/Logs/Kanata/"
echo "  • Non-Homebrew kanata binaries (/usr/local/bin, ~/.cargo/bin, /opt/kanata)"
echo
echo "Your Homebrew install and ${BOLD}~/.config/kanata/${RESET} are NOT touched."
echo

# ── confirmation ───────────────────────────────────────────────────────────
printf "${BOLD}Proceed? [y/N] ${RESET}"
read -r answer
case "$answer" in
  [Yy]|[Yy][Ee][Ss]) ;;
  *)
    echo "Aborted."
    exit 0
    ;;
esac
echo

# ── 1. system LaunchDaemon ─────────────────────────────────────────────────
progress 5 "Beginning legacy cleanup"
info "1/4  System LaunchDaemon (com.example.kanata)"
SYSTEM_PLIST="/Library/LaunchDaemons/com.example.kanata.plist"
if [ -f "$SYSTEM_PLIST" ]; then
    run_as_root launchctl bootout system "$SYSTEM_PLIST" 2>/dev/null || true
    run_as_root rm -f "$SYSTEM_PLIST"
    removed "$SYSTEM_PLIST"
else
    skipped
fi
progress 25 "Legacy system service checked"

# ── 2. user LaunchAgent ────────────────────────────────────────────────────
info "2/4  User LaunchAgent (com.example.kanata)"
USER_PLIST="${HOME}/Library/LaunchAgents/com.example.kanata.plist"
if [ -f "$USER_PLIST" ]; then
    launchctl bootout "gui/$(id -u)" "$USER_PLIST" 2>/dev/null || true
    rm -f "$USER_PLIST"
    removed "$USER_PLIST"
else
    skipped
fi
progress 50 "Legacy user service checked"

# ── 3. legacy log directory ────────────────────────────────────────────────
info "3/4  Legacy log directory (/Library/Logs/Kanata)"
if [ -d "/Library/Logs/Kanata" ]; then
    run_as_root rm -rf "/Library/Logs/Kanata"
    removed "/Library/Logs/Kanata"
else
    skipped
fi
progress 75 "Legacy logs checked"

# ── 4. non-Homebrew kanata binaries ───────────────────────────────────────
info "4/4  Non-Homebrew kanata binaries"

# Detect the current Homebrew prefix so we can skip those paths
BREW_PREFIX=""
for candidate in /opt/homebrew /usr/local; do
    [ -d "$candidate/Cellar" ] && BREW_PREFIX="$candidate" && break
done

found_any_binary=false
for bin_path in \
    "/usr/local/bin/kanata" \
    "/usr/bin/kanata" \
    "/opt/kanata/kanata" \
    "${HOME}/.cargo/bin/kanata"
do
    [ -f "$bin_path" ] || continue

    # Skip anything that lives under the Homebrew prefix
    if [ -n "$BREW_PREFIX" ] && [[ "$bin_path" == "$BREW_PREFIX"* ]]; then
        warning "Skipping Homebrew-managed binary: $bin_path"
        continue
    fi

    # Also skip if the file is a symlink pointing into a Homebrew Cellar
    real_path=$(readlink -f "$bin_path" 2>/dev/null || true)
    if [ -n "$BREW_PREFIX" ] && [[ "$real_path" == "$BREW_PREFIX"* ]]; then
        warning "Skipping symlink into Homebrew: $bin_path → $real_path"
        continue
    fi

    run_as_root rm -f "$bin_path" 2>/dev/null || rm -f "$bin_path" 2>/dev/null || true
    removed "$bin_path"
    found_any_binary=true
done

if [ "$found_any_binary" = false ]; then
    skipped
fi
progress 100 "Legacy cleanup complete"

# ── done ───────────────────────────────────────────────────────────────────
echo
echo "${GREEN}${BOLD}Done.${RESET}"
echo
echo "If a stray kanata process was running from the old setup, kill it with:"
echo "  ${BOLD}sudo pkill -x kanata${RESET}"
echo "Then restart the current service:"
echo "  ${BOLD}sudo brew services restart kanata${RESET}"
echo
echo "You may also want to remove old TCC entries from System Settings if"
echo "you granted permissions to a non-Homebrew kanata binary:"
echo "  System Settings → Privacy & Security → Input Monitoring"
echo "  System Settings → Privacy & Security → Accessibility"
