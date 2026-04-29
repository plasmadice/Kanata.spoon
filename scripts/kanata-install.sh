#!/usr/bin/env bash

# Required parameters:
# @raycast.schemaVersion 1
# @raycast.title Install/Start Kanata
# @raycast.mode fullOutput

# Optional parameters:
# @raycast.icon 🎹

# Documentation:
# @raycast.author plasmadice
# @raycast.authorURL https://github.com/plasmadice

set -euo pipefail

success() { echo "✅ $1"; }
warning() { echo "⚠️  $1"; }
error_exit() { echo "❌ ERROR: $1" >&2; exit 1; }

# Resolve brew regardless of which Homebrew is active in PATH
BREW=""
for candidate in /opt/homebrew/bin/brew /usr/local/bin/brew "$(command -v brew 2>/dev/null)"; do
    [ -x "$candidate" ] && BREW="$candidate" && break
done
[ -z "$BREW" ] && error_exit "Homebrew not found"

# Retrieve sudo password from keychain
pw_name="supa"
pw_account=$(id -un)
if ! cli_password=$(security find-generic-password -w -s "$pw_name" -a "$pw_account" 2>&1); then
    error_exit "Could not get password from keychain. Add it with:\n  security add-generic-password -s 'supa' -a '$(id -un)' -w 'YOUR_PASSWORD'"
fi

# 1. Karabiner-Elements (virtual HID driver)
if "$BREW" list --cask karabiner-elements >/dev/null 2>&1; then
    success "Karabiner-Elements already installed"
else
    echo "Installing Karabiner-Elements..."
    "$BREW" install --cask karabiner-elements
    success "Karabiner-Elements installed"
fi
echo "ℹ️  Quit Karabiner-Elements from the menu bar if it is running — only the virtual HID driver is needed."

# 2. Kanata
if "$BREW" list kanata >/dev/null 2>&1; then
    success "Kanata already installed"
else
    echo "Installing Kanata..."
    "$BREW" install kanata
    success "Kanata installed"
fi

# The brew formula ships --no-wait (skips interactive "press Enter" prompt) but omits
# --nodelay (removes the 2-second startup sleep). Without --nodelay, the virtual mouse
# device doesn't initialize correctly. Patch the formula plist once; brew services stop
# removes the system plist and start recreates it from the formula, so the fix persists.
FORMULA_PLIST="$("$BREW" --prefix kanata 2>/dev/null)/homebrew.mxcl.kanata.plist"
python3 - "$FORMULA_PLIST" <<'PYEOF' 2>/dev/null || true
import plistlib, sys
path = sys.argv[1]
with open(path, "rb") as f:
    p = plistlib.load(f)
args = p["ProgramArguments"]
if "--nodelay" not in args:
    args.insert(1, "--nodelay")
    with open(path, "wb") as f:
        plistlib.dump(p, f)
PYEOF

# 3. Stop any running instance so start recreates the plist from our patched formula.
echo "$cli_password" | sudo -S "$BREW" services stop kanata 2>/dev/null || true
sleep 1

echo "Starting Kanata service..."
echo "$cli_password" | sudo -S "$BREW" services start kanata
success "Kanata service started"

echo
echo "ℹ️  Make sure Kanata has the required macOS permissions:"
echo "   System Settings → Privacy & Security → Input Monitoring"
echo "   System Settings → Privacy & Security → Accessibility"
