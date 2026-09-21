#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=_admin.sh
source "$SCRIPT_DIR/_admin.sh"
# shellcheck source=_driverkit.sh
source "$SCRIPT_DIR/_driverkit.sh"
# shellcheck source=_progress.sh
source "$SCRIPT_DIR/_progress.sh"

success() { echo "✅ $1"; }
warning() { echo "⚠️  $1"; }
error_exit() { echo "❌ ERROR: $1" >&2; exit 1; }

# Kanata binary version targeted by this Spoon release.
KANATA_VERSION="1.12.0"
FORCE_RESTART=false
STOP_ONLY=false

for argument in "$@"; do
    case "$argument" in
        --force-restart) FORCE_RESTART=true ;;
        --stop) STOP_ONLY=true ;;
        --quiet) ;;
        *) error_exit "Unknown option: $argument" ;;
    esac
done

progress 5 "Checking prerequisites"

# Resolve brew regardless of which Homebrew is active in PATH
BREW=""
for candidate in /opt/homebrew/bin/brew /usr/local/bin/brew "$(command -v brew 2>/dev/null)"; do
    [ -x "$candidate" ] && BREW="$candidate" && break
done
[ -z "$BREW" ] && error_exit "Homebrew not found"

kanata_service_loaded() {
    launchctl print system/homebrew.mxcl.kanata >/dev/null 2>&1 ||
        launchctl print system/sh.brew.kanata >/dev/null 2>&1
}

kanata_service_healthy() {
    kanata_service_loaded && pgrep -x kanata >/dev/null 2>&1
}

wait_for_kanata_service() {
    local attempt
    for attempt in {1..10}; do
        kanata_service_healthy && return 0
        sleep 1
    done
    return 1
}

if [ "$STOP_ONLY" = true ]; then
    progress 40 "Checking Kanata service"
    if kanata_service_loaded || pgrep -x kanata >/dev/null 2>&1; then
        run_as_root "$BREW" services stop kanata
    else
        echo "✅ Kanata service already stopped"
    fi

    if kanata_service_loaded || pgrep -x kanata >/dev/null 2>&1; then
        error_exit "Kanata service is still running"
    fi

    progress 75 "Resetting VirtualHID keyboard state"
    reset_driverkit_after_kanata_stop
    progress 100 "Kanata stopped; keyboards restored to passthrough"
    exit 0
fi

SERVICE_RESTART_REQUIRED="$FORCE_RESTART"

# 1. Install the standalone VirtualHID DriverKit bundled with this Spoon.
# This mirrors KeyPath's package-install, activate, and LaunchDaemon workflow
# without installing the full Karabiner-Elements application.
ensure_driverkit "$(dirname "$SCRIPT_DIR")"
[ "$DRIVERKIT_CHANGED" = true ] && SERVICE_RESTART_REQUIRED=true
success "Karabiner VirtualHID DriverKit is ready"
progress 25 "VirtualHID DriverKit ready"

# 2. Kanata
if "$BREW" list kanata >/dev/null 2>&1; then
    KANATA_BIN="$("$BREW" --prefix kanata)/bin/kanata"
    installed_version=$("$KANATA_BIN" --version | awk '{print $2}')
    if [ "$installed_version" = "$KANATA_VERSION" ]; then
        success "Kanata $KANATA_VERSION already installed"
    else
        echo "Upgrading Kanata $installed_version → $KANATA_VERSION..."
        "$BREW" upgrade kanata
        SERVICE_RESTART_REQUIRED=true
    fi
else
    echo "Installing Kanata $KANATA_VERSION..."
    "$BREW" install kanata
    SERVICE_RESTART_REQUIRED=true
fi

KANATA_BIN="$("$BREW" --prefix kanata)/bin/kanata"
installed_version=$("$KANATA_BIN" --version | awk '{print $2}')
[ "$installed_version" = "$KANATA_VERSION" ] ||
    error_exit "Homebrew installed Kanata $installed_version; this Spoon targets $KANATA_VERSION"
success "Kanata $KANATA_VERSION installed"
progress 50 "Kanata binary ready"

# The brew formula ships --no-wait (skips interactive "press Enter" prompt) but omits
# --nodelay (removes the 2-second startup sleep). Without --nodelay, the virtual mouse
# device doesn't initialize correctly. Patch the formula plist once; brew services stop
# removes the system plist and start recreates it from the formula, so the fix persists.
# Bottled formulae can also retain the bottle builder's home in --cfg; normalize it.
FORMULA_PLIST="$("$BREW" --prefix kanata 2>/dev/null)/homebrew.mxcl.kanata.plist"
KANATA_CONFIG="${HOME}/.config/kanata/kanata.kbd"
[ -f "$KANATA_CONFIG" ] || error_exit "Kanata config not found: $KANATA_CONFIG"
plist_status=$(python3 - "$FORMULA_PLIST" "$KANATA_CONFIG" <<'PYEOF'
import plistlib, sys
path, config_path = sys.argv[1:3]
with open(path, "rb") as f:
    p = plistlib.load(f)
args = p["ProgramArguments"]
changed = False
if "--nodelay" not in args:
    args.insert(1, "--nodelay")
    changed = True
for flag in ("--cfg", "-c"):
    if flag in args:
        config_index = args.index(flag) + 1
        if args[config_index] != config_path:
            args[config_index] = config_path
            changed = True
        break
if changed:
    with open(path, "wb") as f:
        plistlib.dump(p, f)
print("changed" if changed else "unchanged")
PYEOF
)
[ "$plist_status" = "changed" ] && SERVICE_RESTART_REQUIRED=true
progress 70 "Service configuration ready"

# 3. Preserve a healthy service unless an installation or caller requires restart.
if kanata_service_healthy && [ "$SERVICE_RESTART_REQUIRED" = false ]; then
    progress 85 "Kanata service health confirmed"
    success "Kanata service is healthy; restart skipped"
    progress 100 "Kanata service already healthy"
else
    if kanata_service_loaded || pgrep -x kanata >/dev/null 2>&1; then
        run_as_root "$BREW" services stop kanata 2>/dev/null || true
        sleep 1
        progress 85 "Previous service stopped"
    else
        progress 85 "Kanata service needs to start"
    fi

    echo "Starting Kanata service..."
    run_as_root "$BREW" services start kanata
    wait_for_kanata_service || error_exit "Kanata service failed its health check"
    success "Kanata service started"
    progress 100 "Kanata service running"
fi

echo
echo "ℹ️  Make sure Kanata has the required macOS permissions:"
echo "   System Settings → Privacy & Security → Input Monitoring"
echo "   System Settings → Privacy & Security → Accessibility"
echo
echo "   Remove any entry for the old versioned Homebrew Cellar binary, for example:"
echo "   /opt/homebrew/Cellar/kanata/<old-version>/bin/kanata"
echo
echo "   Then add the stable Homebrew path to both permission lists:"
echo "   /opt/homebrew/opt/kanata/bin/kanata"
echo
echo "   In the file picker, press ⌘⇧G and paste the path above."
