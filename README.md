# Claude Remote

Persistent terminal sessions for mobile productivity. Run long processes, disconnect, and reconnect from any device without losing your session.

## Features

- **Persistent Sessions**: Start a process, disconnect, reconnect hours later - your session is exactly as you left it
- **Mosh + tmux**: Native terminal experience with roaming support
- **Web Fallback**: Access via browser when native clients aren't available
- **Cross-Platform**: Works from iOS, Android, Windows, Mac, Linux
- **Secure**: Tailscale Funnel provides HTTPS without port forwarding

## Architecture

```
                    YOUR DEVICES
    ┌─────────────────────────────────────────┐
    │  iPhone    Laptop    Desktop    Tablet  │
    │  (Blink)   (mosh)    (ssh)     (browser)│
    └─────────────┬───────────────────────────┘
                  │
                  ▼
    ┌─────────────────────────────────────────┐
    │              YOUR SERVER                │
    │  ┌───────────────────────────────────┐  │
    │  │             tmux                  │  │
    │  │   ┌─────────────────────────┐     │  │
    │  │   │  Your persistent shell  │     │  │
    │  │   │  (Claude Code, etc.)    │     │  │
    │  │   └─────────────────────────┘     │  │
    │  └───────────────────────────────────┘  │
    │         ▲                 ▲             │
    │    mosh-server          ttyd            │
    │    (UDP 60000+)    (via Tailscale)      │
    └─────────────────────────────────────────┘
```

## Quick Start

### Installation

```bash
# Clone the repository
git clone <repo-url> claude-remote
cd claude-remote

# Run the installer
./install.sh
```

The installer will:
1. Install mosh, tmux, and ttyd
2. Configure tmux with an optimized config
3. Set up the web terminal service
4. Configure Tailscale Funnel (if available)

### Usage

**Start a persistent session:**
```bash
claude-session
```

**Connect remotely with Mosh (recommended):**
```bash
mosh user@yourserver -- claude-session
```

**Connect via SSH:**
```bash
ssh user@yourserver -t 'claude-session'
```

**Connect via web browser:**
Open your Tailscale Funnel URL (shown after installation)

**Check status:**
```bash
claude-status
```

## Client Apps by Platform

| Platform | Recommended App | Notes |
|----------|-----------------|-------|
| iOS/iPadOS | [Blink Shell](https://blink.sh) | Best mosh client, $20 one-time |
| | [Termius](https://termius.com) | Free tier, mosh via subscription |
| Android | [Termux](https://termux.dev) | Free, run `pkg install mosh` |
| | [JuiceSSH](https://juicessh.com) | Free + mosh plugin |
| Windows | WSL2 + Windows Terminal | `apt install mosh` in WSL |
| macOS | Native Terminal/iTerm2 | `brew install mosh` |
| Linux | Native Terminal | `apt install mosh` |
| Any | Web Browser | Via Tailscale Funnel URL |

## Session Management

**Create named sessions:**
```bash
claude-session work      # Create/attach to "work" session
claude-session personal  # Create/attach to "personal" session
```

**List all sessions:**
```bash
claude-session --list
```

**Kill a session:**
```bash
claude-session --kill work
```

## tmux Cheat Sheet

The tmux prefix is `Ctrl+a` (press Ctrl+a, release, then press the command key).

| Command | Action |
|---------|--------|
| `Ctrl+a d` | Detach from session (keeps running) |
| `Ctrl+a c` | Create new window |
| `Ctrl+a n` | Next window |
| `Ctrl+a p` | Previous window |
| `Ctrl+a 1-9` | Switch to window number |
| `Ctrl+a \|` | Split pane vertically |
| `Ctrl+a -` | Split pane horizontally |
| `Ctrl+a h/j/k/l` | Navigate panes (vim keys) |
| `Ctrl+a [` | Enter scroll/copy mode |
| `Ctrl+a r` | Reload tmux config |

**In scroll mode:**
- Use arrow keys or vim keys to navigate
- `q` to exit scroll mode
- `v` to start selection, `y` to copy

## Configuration

### tmux config
The tmux configuration is installed to `~/.tmux.conf`. Key settings:
- 50,000 line scrollback buffer
- Mouse support enabled
- Vim-style keybindings
- Status bar with session info

### Web terminal
The web terminal runs on localhost:7681 and is exposed via Tailscale Funnel.

**Linux:** Managed via systemd user service
```bash
systemctl --user status claude-web.service
systemctl --user restart claude-web.service
```

**macOS:** Managed via launchd
```bash
launchctl list | grep claude
launchctl unload ~/Library/LaunchAgents/com.claude.web.plist
launchctl load ~/Library/LaunchAgents/com.claude.web.plist
```

## Security

- **Mosh/SSH**: Uses your existing SSH authentication
- **Web terminal**: Protected by Tailscale authentication
  - Only accessible to devices on your Tailnet
  - HTTPS encryption via Tailscale
- **Sessions**: User-scoped, no privilege escalation

### Optional: Add basic auth to web terminal
Edit the service to add credentials:
```bash
ttyd --credential user:password ...
```

## Troubleshooting

### Mosh connection fails
1. Ensure UDP ports 60000-60010 are open on your server
2. Check that mosh-server is installed: `which mosh-server`

### Web terminal not accessible
1. Check service status: `claude-status`
2. Verify Tailscale Funnel: `tailscale funnel status`
3. Check ttyd is running: `pgrep ttyd`

### tmux session lost after reboot
tmux sessions don't survive reboots by default. Options:
1. Install tmux-resurrect plugin for manual save/restore
2. Install tmux-continuum for automatic persistence
3. Use systemd to auto-start a session on boot

### "claude-session: command not found"
Add `~/.local/bin` to your PATH:
```bash
echo 'export PATH="${HOME}/.local/bin:${PATH}"' >> ~/.bashrc
source ~/.bashrc
```

## Uninstallation

```bash
./uninstall.sh
```

This removes scripts, services, and optionally the tmux config. Installed packages (mosh, tmux, ttyd) are left in place.

## Use Case: Claude Code on the Go

1. Start Claude Code in a persistent session:
   ```bash
   mosh user@server -- claude-session claude
   # Now in the session:
   claude
   ```

2. Start a long-running task (refactoring, code review, etc.)

3. Close your laptop, switch to your phone, lose connectivity - it doesn't matter

4. Reconnect from any device and pick up exactly where you left off

## License

MIT
