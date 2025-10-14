# Raycast Integration

Quick guide for integrating Kanata.spoon with Raycast.

## Setup

### 1. Install Raycast

Download from [raycast.com](https://www.raycast.com/)

### 2. Add Scripts to Raycast

1. Open Raycast Settings (`⌘,`)
2. Go to **Extensions** → **Script Commands**
3. Click **+** to add directory
4. Select: `~/.config/hammerspoon/Spoons/Kanata.spoon/scripts/`
5. Click **Add**

**Important**: Scripts require approval on first use. macOS will ask you to approve each script once.

### 3. Enable in Spoon

```lua
spoon.Kanata.useRaycast = true
```

**Note**: Automatically enables AppleScript when set to true.

### 4. Reload Hammerspoon

## Menu Structure

With Raycast enabled, your menu shows:

```
Start/Stop Service
Start/Stop Monitor
───────────────────
Restart Kanata      → Raycast
Stop Kanata         → Raycast
Cleanup Kanata      → Raycast
Install Kanata      → Raycast
───────────────────
Open Kanata Config
Open Hammerspoon Config
───────────────────
Hammerspoon Preferences
Show Console
Quit Hammerspoon
───────────────────
Kanata.spoon v1.0.0
```

## How It Works

Menu items open Raycast deeplinks:
- `raycast://script-commands/kanata-restart`
- `raycast://script-commands/kanata-stop`
- `raycast://script-commands/kanata-cleanup`
- `raycast://script-commands/kanata-install`

## Troubleshooting

### Scripts not in Raycast
- Check folder added: Raycast Settings → Extensions → Script Commands
- Make executable: `chmod +x scripts/*.sh`
- Reload Raycast scripts (right-click folder → Reload)

### Menu items don't work
- Scripts need approval on first use (click "Allow")
- Test manually: `open "raycast://script-commands/kanata-restart"`
- Check Raycast is running: `ps aux | grep -i raycast`

### Script Permissions

Scripts require password access. Set up once:

```bash
security add-generic-password -s 'supa' -a "$(id -un)" -w 'your_password'
```

## Benefits

- ✅ Clean UI in Raycast
- ✅ Quick access via search
- ✅ See script output
- ✅ Assign keyboard shortcuts
- ✅ No Terminal windows

---

For more details, see Raycast's [Script Commands documentation](https://github.com/raycast/script-commands).
