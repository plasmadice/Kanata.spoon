#!/usr/bin/env bash

# Required parameters:
# @raycast.schemaVersion 1
# @raycast.title Stop Kanata
# @raycast.mode inline

# Optional parameters:
# @raycast.icon 🤖

# Documentation:
# @raycast.author plasmadice
# @raycast.authorURL https://github.com/plasmadice

set -euo pipefail

# Resolve brew regardless of which Homebrew is active in PATH
BREW=""
for candidate in "$(command -v brew 2>/dev/null)" /opt/homebrew/bin/brew /usr/local/bin/brew; do
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

echo "$cli_password" | sudo -S "$BREW" services stop kanata
echo "✅ Kanata stopped"
