#!/usr/bin/env bash

# Required parameters:
# @raycast.schemaVersion 1
# @raycast.title Cleanup Kanata & Karabiner
# @raycast.mode fullOutput

# Optional parameters:
# @raycast.icon 🧹

# Documentation:
# @raycast.author plasmadice
# @raycast.authorURL https://github.com/plasmadice

set -euo pipefail

success() { echo "✅ $1"; }
warning() { echo "⚠️  $1"; }

# Resolve brew regardless of which Homebrew is active in PATH
BREW=""
for candidate in "$(command -v brew 2>/dev/null)" /opt/homebrew/bin/brew /usr/local/bin/brew; do
    [ -x "$candidate" ] && BREW="$candidate" && break
done

# Retrieve sudo password from keychain
pw_name="supa"
pw_account=$(id -un)
if ! cli_password=$(security find-generic-password -w -s "$pw_name" -a "$pw_account" 2>&1); then
    echo "❌ Could not get password from keychain"
    exit 1
fi

echo "🧹 Uninstalling Kanata..."

# 1. Kill any stray kanata processes first (running two instances breaks mouse/keyboard)
pkill -x kanata 2>/dev/null || true
sleep 1

# 2. Stop and unregister the brew service
if [ -n "$BREW" ] && "$BREW" list kanata >/dev/null 2>&1; then
    echo "$cli_password" | sudo -S "$BREW" services stop kanata 2>/dev/null || true
    success "Kanata service stopped"
    "$BREW" uninstall kanata
    success "Kanata uninstalled from Homebrew"
else
    warning "Kanata not found in Homebrew — skipping"
fi

# 3. Clean up any legacy LaunchDaemon / LaunchAgent plist files from old setup.
# The old scripts used com.example.kanata; brew services uses homebrew.mxcl.kanata.
for plist in \
    "/Library/LaunchDaemons/com.example.kanata.plist" \
    "/Library/LaunchDaemons/homebrew.mxcl.kanata.plist" \
    "${HOME}/Library/LaunchAgents/com.example.kanata.plist"
do
    if [ -f "$plist" ]; then
        echo "$cli_password" | sudo -S launchctl bootout system "$plist" 2>/dev/null || \
            launchctl bootout "gui/$(id -u)" "$plist" 2>/dev/null || true
        echo "$cli_password" | sudo -S rm -f "$plist" 2>/dev/null || rm -f "$plist" 2>/dev/null || true
        success "Removed plist: $plist"
    fi
done

# 3. Remove legacy log directory (old LaunchDaemon setup wrote here)
if [ -d "/Library/Logs/Kanata" ]; then
    echo "$cli_password" | sudo -S rm -rf "/Library/Logs/Kanata"
    success "Removed /Library/Logs/Kanata"
fi

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
echo
echo "ℹ️  Karabiner-Elements was left installed (uninstall manually if not needed)."
echo "ℹ️  You may also remove Kanata from:"
echo "   System Settings → Privacy & Security → Input Monitoring"
echo "   System Settings → Privacy & Security → Accessibility"
