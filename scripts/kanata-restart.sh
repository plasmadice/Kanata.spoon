#!/usr/bin/env bash

# Required parameters:
# @raycast.schemaVersion 1
# @raycast.title Restart Kanata
# @raycast.mode inline

# Optional parameters:
# @raycast.icon 🤖

# Documentation:
# @raycast.author plasmadice
# @raycast.authorURL https://github.com/plasmadice

set -euo pipefail

# Resolve brew regardless of which Homebrew is active in PATH
BREW=""
for candidate in /opt/homebrew/bin/brew /usr/local/bin/brew "$(command -v brew 2>/dev/null)"; do
    [ -x "$candidate" ] && BREW="$candidate" && break
done
[ -z "$BREW" ] && echo "❌ Homebrew not found" && exit 1

# Retrieve sudo password from keychain
pw_name="supa"
pw_account=$(id -un)
if ! cli_password=$(security find-generic-password -w -s "$pw_name" -a "$pw_account" 2>&1); then
    echo "❌ Could not get password from keychain"
    exit 1
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

# Stop (removes system plist), then start (recreates from patched formula plist)
echo "$cli_password" | sudo -S "$BREW" services stop kanata 2>/dev/null || true
sleep 1
echo "$cli_password" | sudo -S "$BREW" services start kanata && echo "✅ Kanata restarted"
