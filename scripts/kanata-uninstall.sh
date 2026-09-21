#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=_admin.sh
source "$SCRIPT_DIR/_admin.sh"
# shellcheck source=_progress.sh
source "$SCRIPT_DIR/_progress.sh"

success() { echo "✅ $1"; }
warning() { echo "⚠️  $1"; }

# Resolve brew regardless of which Homebrew is active in PATH
BREW=""
for candidate in "$(command -v brew 2>/dev/null)" /opt/homebrew/bin/brew /usr/local/bin/brew; do
    [ -x "$candidate" ] && BREW="$candidate" && break
done

echo "🧹 Uninstalling Kanata..."
progress 5 "Beginning uninstall"

# 1. Kill any stray kanata processes first (running two instances breaks mouse/keyboard)
pkill -x kanata 2>/dev/null || true
sleep 1
if pgrep -x kanata >/dev/null 2>&1; then
    echo "❌ Kanata is still running" >&2
    exit 1
fi
progress 20 "Kanata process stopped"

# 2. Stop and unregister the brew service
if [ -n "$BREW" ] && "$BREW" list kanata >/dev/null 2>&1; then
    run_as_root "$BREW" services stop kanata 2>/dev/null || true
    success "Kanata service stopped"
    if ! "$BREW" uninstall kanata; then
        # Running brew services as root can leave the keg and opt symlink
        # root-owned, preventing a normal user-level Homebrew uninstall.
        warning "Normal uninstall failed — removing root-owned Kanata paths"
        kanata_cellar=$("$BREW" --cellar kanata 2>/dev/null || true)
        [ -n "$kanata_cellar" ] && run_as_root rm -rf "$kanata_cellar"
        run_as_root rm -f \
            "$("$BREW" --prefix)/opt/kanata" \
            "$("$BREW" --prefix)/bin/kanata" \
            "$("$BREW" --prefix)/var/homebrew/linked/kanata"
        "$BREW" uninstall --force kanata 2>/dev/null || true
    fi
    success "Kanata uninstalled from Homebrew"
else
    warning "Kanata not found in Homebrew — skipping"
fi

if [ -n "$BREW" ] && "$BREW" list kanata >/dev/null 2>&1; then
    echo "❌ Kanata remains installed in Homebrew" >&2
    exit 1
fi
if launchctl print system/homebrew.mxcl.kanata >/dev/null 2>&1 ||
   launchctl print system/sh.brew.kanata >/dev/null 2>&1; then
    echo "❌ Kanata service remains loaded" >&2
    exit 1
fi
progress 50 "Homebrew service and package removed"

# 3. Clean up any legacy LaunchDaemon / LaunchAgent plist files from old setup.
# The old scripts used com.example.kanata; brew services uses homebrew.mxcl.kanata.
for plist in \
    "/Library/LaunchDaemons/sh.brew.kanata.plist" \
    "/Library/LaunchDaemons/com.example.kanata.plist" \
    "/Library/LaunchDaemons/homebrew.mxcl.kanata.plist" \
    "${HOME}/Library/LaunchAgents/com.example.kanata.plist" \
    "${HOME}/Library/LaunchAgents/sh.brew.kanata.plist"
do
    if [ -f "$plist" ]; then
        run_as_root launchctl bootout system "$plist" 2>/dev/null || \
            launchctl bootout "gui/$(id -u)" "$plist" 2>/dev/null || true
        run_as_root rm -f "$plist" 2>/dev/null || rm -f "$plist" 2>/dev/null || true
        success "Removed plist: $plist"
    fi
done
progress 75 "Service registrations removed"

# 3. Remove legacy log directory (old LaunchDaemon setup wrote here)
if [ -d "/Library/Logs/Kanata" ]; then
    run_as_root rm -rf "/Library/Logs/Kanata"
    success "Removed /Library/Logs/Kanata"
fi

# Remove current Homebrew service log and stale tray configuration.
if [ -n "$BREW" ]; then
    run_as_root rm -f "$("$BREW" --prefix)/var/log/kanata.log" 2>/dev/null || true
fi
rm -rf "${HOME}/Library/Application Support/kanata-tray"
run_as_root rm -rf "/Library/Application Support/kanata-tray"
progress 90 "Support files removed"

# 4. Keep kanata config (~/.config/kanata) unless it is empty
if [ -d "${HOME}/.config/kanata" ]; then
    if [ -z "$(ls -A "${HOME}/.config/kanata" 2>/dev/null)" ]; then
        rm -rf "${HOME}/.config/kanata"
        success "Removed empty ~/.config/kanata"
    else
        warning "~/.config/kanata has files — leaving it in place"
    fi
fi

echo
echo "🎉 Done!"
progress 100 "Kanata uninstall complete"
echo
echo "ℹ️  Karabiner-Elements was left installed (uninstall manually if not needed)."
echo "ℹ️  You may also remove Kanata from:"
echo "   System Settings → Privacy & Security → Input Monitoring"
echo "   System Settings → Privacy & Security → Accessibility"
