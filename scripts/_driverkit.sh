#!/usr/bin/env bash

DRIVERKIT_VERSION="6.2.0"
DRIVERKIT_SHA256="9e8c46239f0748161241e42444857901224e5c82f5b58a1731df4c70bf0736a8"
DRIVERKIT_PACKAGE_ID="org.pqrs.Karabiner-DriverKit-VirtualHIDDevice"
DRIVERKIT_TEAM_ID="G43BCU2T37"
DRIVERKIT_BUNDLE_ID="org.pqrs.Karabiner-DriverKit-VirtualHIDDevice"
DRIVERKIT_MANAGER="/Applications/.Karabiner-VirtualHIDDevice-Manager.app/Contents/MacOS/Karabiner-VirtualHIDDevice-Manager"
DRIVERKIT_DAEMON="/Library/Application Support/org.pqrs/Karabiner-DriverKit-VirtualHIDDevice/Applications/Karabiner-VirtualHIDDevice-Daemon.app/Contents/MacOS/Karabiner-VirtualHIDDevice-Daemon"
DRIVERKIT_DAEMON_LABEL="com.kanata.karabiner-vhiddaemon"
DRIVERKIT_MANAGER_LABEL="com.kanata.karabiner-vhidmanager"
DRIVERKIT_CHANGED=false

driverkit_installed_version() {
    pkgutil --pkg-info "$DRIVERKIT_PACKAGE_ID" 2>/dev/null |
        awk '/^version:/{print $2; exit}'
}

verify_driverkit_package() {
    local package_path="$1"
    local actual_sha256

    [ -f "$package_path" ] || {
        echo "❌ Bundled DriverKit package not found: $package_path" >&2
        return 1
    }

    actual_sha256=$(shasum -a 256 "$package_path" | awk '{print $1}')
    [ "$actual_sha256" = "$DRIVERKIT_SHA256" ] || {
        echo "❌ DriverKit package checksum mismatch" >&2
        return 1
    }
}

install_driverkit_services() {
    local temp_dir daemon_plist manager_plist
    temp_dir=$(mktemp -d)
    daemon_plist="$temp_dir/$DRIVERKIT_DAEMON_LABEL.plist"
    manager_plist="$temp_dir/$DRIVERKIT_MANAGER_LABEL.plist"

    cat >"$daemon_plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>Label</key><string>$DRIVERKIT_DAEMON_LABEL</string>
  <key>ProgramArguments</key><array><string>$DRIVERKIT_DAEMON</string></array>
  <key>RunAtLoad</key><true/>
  <key>KeepAlive</key><true/>
  <key>ProcessType</key><string>Interactive</string>
  <key>UserName</key><string>root</string>
  <key>GroupName</key><string>wheel</string>
  <key>ThrottleInterval</key><integer>10</integer>
</dict></plist>
EOF

    cat >"$manager_plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>Label</key><string>$DRIVERKIT_MANAGER_LABEL</string>
  <key>ProgramArguments</key><array>
    <string>$DRIVERKIT_MANAGER</string>
    <string>activate</string>
  </array>
  <key>RunAtLoad</key><true/>
  <key>KeepAlive</key><false/>
  <key>UserName</key><string>root</string>
  <key>GroupName</key><string>wheel</string>
</dict></plist>
EOF

    run_as_root launchctl bootout "system/$DRIVERKIT_DAEMON_LABEL" 2>/dev/null || true
    run_as_root launchctl bootout "system/$DRIVERKIT_MANAGER_LABEL" 2>/dev/null || true
    run_as_root cp "$daemon_plist" "/Library/LaunchDaemons/$DRIVERKIT_DAEMON_LABEL.plist"
    run_as_root cp "$manager_plist" "/Library/LaunchDaemons/$DRIVERKIT_MANAGER_LABEL.plist"
    run_as_root chown root:wheel \
        "/Library/LaunchDaemons/$DRIVERKIT_DAEMON_LABEL.plist" \
        "/Library/LaunchDaemons/$DRIVERKIT_MANAGER_LABEL.plist"
    run_as_root chmod 644 \
        "/Library/LaunchDaemons/$DRIVERKIT_DAEMON_LABEL.plist" \
        "/Library/LaunchDaemons/$DRIVERKIT_MANAGER_LABEL.plist"
    run_as_root launchctl bootstrap system "/Library/LaunchDaemons/$DRIVERKIT_DAEMON_LABEL.plist"
    run_as_root launchctl bootstrap system "/Library/LaunchDaemons/$DRIVERKIT_MANAGER_LABEL.plist"
    run_as_root launchctl enable "system/$DRIVERKIT_DAEMON_LABEL"
    run_as_root launchctl enable "system/$DRIVERKIT_MANAGER_LABEL"
    run_as_root launchctl kickstart -k "system/$DRIVERKIT_DAEMON_LABEL"
    run_as_root launchctl kickstart -k "system/$DRIVERKIT_MANAGER_LABEL" || true

    rm -rf "$temp_dir"
}

ensure_driverkit() {
    local spoon_root="$1"
    local package_path installed_version
    local package_changed=false
    package_path="$spoon_root/drivers/Karabiner-DriverKit-VirtualHIDDevice-$DRIVERKIT_VERSION.pkg"
    installed_version=$(driverkit_installed_version || true)
    DRIVERKIT_CHANGED=false

    verify_driverkit_package "$package_path"

    if [ "$installed_version" != "$DRIVERKIT_VERSION" ]; then
        echo "Installing Karabiner VirtualHID DriverKit $DRIVERKIT_VERSION..."
        run_as_root systemextensionsctl uninstall "$DRIVERKIT_TEAM_ID" "$DRIVERKIT_BUNDLE_ID" 2>/dev/null || true
        sleep 2
        run_as_root /usr/sbin/installer -pkg "$package_path" -target /
        sleep 3
        package_changed=true
        DRIVERKIT_CHANGED=true
    else
        echo "✅ Karabiner VirtualHID DriverKit $DRIVERKIT_VERSION already installed"
    fi

    [ -x "$DRIVERKIT_MANAGER" ] || {
        echo "❌ VirtualHID manager missing after installation" >&2
        return 1
    }
    [ -x "$DRIVERKIT_DAEMON" ] || {
        echo "❌ VirtualHID daemon missing after installation" >&2
        return 1
    }

    if ! launchctl print "system/$DRIVERKIT_DAEMON_LABEL" >/dev/null 2>&1 ||
       ! launchctl print "system/$DRIVERKIT_MANAGER_LABEL" >/dev/null 2>&1 ||
       ! pgrep -f "$DRIVERKIT_DAEMON" >/dev/null 2>&1; then
        run_as_root "$DRIVERKIT_MANAGER" activate
        install_driverkit_services
        DRIVERKIT_CHANGED=true
    elif [ "$package_changed" = true ]; then
        run_as_root "$DRIVERKIT_MANAGER" activate
    else
        echo "✅ VirtualHID services are healthy; restart skipped"
    fi
}

# Kanata is terminated by launchd with SIGTERM, which does not run Rust Drop
# cleanup. Restarting the KeepAlive VirtualHID daemon clears stale virtual
# keyboard reports and mirrors KeyPath's restartKarabinerDaemon recovery.
reset_driverkit_after_kanata_stop() {
    local attempt

    if ! launchctl print "system/$DRIVERKIT_DAEMON_LABEL" >/dev/null 2>&1; then
        echo "⚠️  VirtualHID daemon service is not loaded; reset skipped"
        return 0
    fi

    run_as_root /usr/bin/pkill -f "$DRIVERKIT_DAEMON" 2>/dev/null || true

    for attempt in {1..10}; do
        if pgrep -f "$DRIVERKIT_DAEMON" >/dev/null 2>&1; then
            echo "✅ VirtualHID state reset; physical keyboards are in passthrough mode"
            return 0
        fi
        sleep 1
    done

    echo "❌ VirtualHID daemon did not recover after reset" >&2
    return 1
}
