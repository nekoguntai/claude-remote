# Claude Remote

Persistent terminal sessions for mobile productivity. Run long processes, disconnect, and reconnect from any device without losing your session.

## Features

- **Persistent Sessions**: Start a process, disconnect, reconnect hours later - your session is exactly as you left it
- **Mosh + tmux**: Native terminal experience with roaming support
- **Web Fallback**: Access via browser when native clients aren't available
- **Cross-Platform**: Works from iOS, Android, Windows, Mac, Linux
- **Secure by Default**: Tailnet-only access, password auth, localhost binding, 2FA support

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
    │    mosh-server     ttyd (127.0.0.1)     │
    │    (UDP 60000+)          │              │
    │                    Tailscale Serve      │
    │                  (Tailnet-only + auth)  │
    └─────────────────────────────────────────┘
```

## How Connections Work

### Mosh Connection (Recommended for Native Clients)

```
┌──────────────────────────────────────────────────────────────────┐
│                     MOSH CONNECTION FLOW                          │
├──────────────────────────────────────────────────────────────────┤
│                                                                   │
│  Mobile Device                              Server                │
│  ┌─────────────┐                         ┌─────────────┐         │
│  │ Blink Shell │                         │  SSH Server │         │
│  │ / Terminal  │                         │  (port 22)  │         │
│  └──────┬──────┘                         └──────┬──────┘         │
│         │                                       │                 │
│         │ ① SSH Handshake (TCP, encrypted)      │                 │
│         │──────────────────────────────────────▶│                 │
│         │   - Authenticate with SSH key         │                 │
│         │   - Start mosh-server                 │                 │
│         │   - Receive UDP port + session key    │                 │
│         │◀──────────────────────────────────────│                 │
│         │                                       │                 │
│  ┌──────┴──────┐                         ┌──────┴──────┐         │
│  │ Mosh Client │                         │ Mosh Server │         │
│  └──────┬──────┘                         └──────┬──────┘         │
│         │                                       │                 │
│         │ ② Mosh Protocol (UDP, encrypted)      │                 │
│         │◀═════════════════════════════════════▶│                 │
│         │   AES-128-OCB authenticated encryption│                 │
│         │   Handles roaming, packet loss        │                 │
│         │                                ┌──────┴──────┐         │
│         │                                │    tmux     │         │
│         │                                │  (session)  │         │
│         │                                └─────────────┘         │
│                                                                   │
│  ENCRYPTION: All traffic encrypted end-to-end                    │
│  - Phase 1: SSH (AES-256-GCM or similar)                         │
│  - Phase 2: Mosh (AES-128-OCB)                                   │
└──────────────────────────────────────────────────────────────────┘
```

**Experience**: Open Blink Shell (iOS) or terminal, run `mosh user@server -- claude-session`. Works like SSH but survives Wi-Fi changes, sleep/wake, and brief disconnections. Best for extended sessions.

### Web Terminal Connection (Browser Fallback)

```
┌──────────────────────────────────────────────────────────────────┐
│                   WEB TERMINAL CONNECTION FLOW                    │
├──────────────────────────────────────────────────────────────────┤
│                                                                   │
│  Mobile Device                              Server                │
│  ┌─────────────┐                         ┌─────────────┐         │
│  │  Tailscale  │                         │  Tailscale  │         │
│  │    App      │                         │   Daemon    │         │
│  └──────┬──────┘                         └──────┬──────┘         │
│         │                                       │                 │
│         │ ① WireGuard Tunnel (always on)        │                 │
│         │◀═════════════════════════════════════▶│                 │
│         │   ChaCha20-Poly1305 encryption        │                 │
│         │   Tailnet-only (not public internet)  │                 │
│         │                                       │                 │
│  ┌──────┴──────┐                         ┌──────┴──────┐         │
│  │   Browser   │                         │  Tailscale  │         │
│  │  (Safari)   │                         │    Serve    │         │
│  └──────┬──────┘                         └──────┬──────┘         │
│         │                                       │                 │
│         │ ② HTTPS Request                       │                 │
│         │──────────────────────────────────────▶│ (localhost)    │
│         │   https://server:7681                 │      │          │
│         │                                ┌──────┴──────┐         │
│         │ ③ Password Prompt              │    ttyd     │         │
│         │   Username: claude             │ (127.0.0.1) │         │
│         │   Password: ********           └──────┬──────┘         │
│         │                                       │                 │
│         │ ④ WebSocket Terminal Stream           │                 │
│         │◀═════════════════════════════════════▶│                 │
│         │                                ┌──────┴──────┐         │
│         │                                │    tmux     │         │
│         │                                │  (session)  │         │
│         │                                └─────────────┘         │
│                                                                   │
│  ENCRYPTION: WireGuard encrypts all traffic through tunnel       │
│  - Tailscale: ChaCha20-Poly1305 (WireGuard)                      │
│  - Localhost segments: Not encrypted (same device, not needed)   │
│  - Auth: Tailscale account (supports 2FA) + password             │
└──────────────────────────────────────────────────────────────────┘
```

**Experience**: Open Safari/Chrome, navigate to `https://your-server:7681`, enter password. Full terminal in browser. Works on any device with Tailscale installed.

### Which Should I Use?

| Scenario | Recommendation |
|----------|----------------|
| Extended coding sessions | Mosh - handles disconnections gracefully |
| Quick check from any device | Web - no app installation needed beyond Tailscale |
| Unreliable network | Mosh - designed for packet loss and roaming |
| Device without mosh client | Web - works in any browser |
| Maximum responsiveness | Mosh - lower latency, local echo |

## Server Setup (One-Time)

These steps are performed once on your server (Linux or macOS machine that will host your sessions).

### Step 1: Install Claude Remote

```bash
# Clone the repository
git clone https://github.com/nekoguntai/claude-remote.git
cd claude-remote

# Run the installer
./install.sh
```

The installer will:
1. Install mosh, tmux, and ttyd (with checksum verification)
2. Generate a secure random password for web access
3. Configure tmux with security-optimized settings
4. Set up the web terminal service (localhost only)
5. Configure Tailscale Serve for Tailnet-only access (if available)

**Important**: Save the web terminal password shown at the end of installation!

### Step 2: Configure Tailscale (Required for Web Access)

If not already installed:
```bash
# Linux
curl -fsSL https://tailscale.com/install.sh | sh
sudo tailscale up

# macOS
brew install tailscale
```

Enable 2FA on your Tailscale account at https://login.tailscale.com/admin/settings/keys for additional security.

### Step 3: Configure Firewall (For Mosh)

Mosh requires UDP ports to be open:
```bash
# Ubuntu/Debian with ufw
sudo ufw allow 60000:60010/udp comment "mosh"

# RHEL/Fedora with firewalld
sudo firewall-cmd --permanent --add-port=60000-60010/udp
sudo firewall-cmd --reload

# macOS - usually no firewall changes needed
```

### Step 4: Surviving Server Reboots

By default, tmux sessions are lost when the server reboots. Choose one of these options:

**Option A: Auto-start a default session (Recommended)**

Create a systemd user service to start a tmux session on boot:
```bash
mkdir -p ~/.config/systemd/user

cat > ~/.config/systemd/user/claude-session.service << 'EOF'
[Unit]
Description=Claude tmux session
After=default.target

[Service]
Type=forking
ExecStart=/usr/bin/tmux new-session -d -s main
ExecStop=/usr/bin/tmux kill-session -t main
Restart=on-failure

[Install]
WantedBy=default.target
EOF

systemctl --user enable claude-session.service
systemctl --user start claude-session.service

# Enable lingering so service starts even when not logged in
sudo loginctl enable-linger $USER
```

**Option B: tmux-resurrect plugin (Manual save/restore)**
```bash
# Install TPM (Tmux Plugin Manager)
git clone https://github.com/tmux-plugins/tpm ~/.tmux/plugins/tpm

# Add to ~/.tmux.conf
echo "set -g @plugin 'tmux-plugins/tmux-resurrect'" >> ~/.tmux.conf

# Reload tmux config
tmux source ~/.tmux.conf

# Install plugins: press Ctrl+a then I (capital i)
# Save session: Ctrl+a then Ctrl+s
# Restore session: Ctrl+a then Ctrl+r
```

**Option C: tmux-continuum (Automatic save/restore)**
```bash
# Add to ~/.tmux.conf (requires tmux-resurrect)
echo "set -g @plugin 'tmux-plugins/tmux-continuum'" >> ~/.tmux.conf
echo "set -g @continuum-restore 'on'" >> ~/.tmux.conf
echo "set -g @continuum-save-interval '15'" >> ~/.tmux.conf

# Reload and install: Ctrl+a then I
```

### Step 5: Verify Setup

```bash
claude-status
```

This shows:
- Active tmux sessions
- Mosh server status
- Web terminal (ttyd) status
- Tailscale connection and URL

---

## Client Setup (One-Time per Device)

Set up each device you want to connect from.

### iOS / iPadOS

| App | Setup |
|-----|-------|
| **Blink Shell** ($20) | Best mosh client. Add server in Settings → Hosts. |
| **Termius** (Free/Paid) | Mosh requires subscription. Add server in Hosts. |
| **Tailscale** (Free) | Install from App Store, sign in to your Tailnet. |

### Android

| App | Setup |
|-----|-------|
| **Termux** (Free) | Run `pkg install mosh openssh` |
| **JuiceSSH** (Free) | Install mosh plugin from app. |
| **Tailscale** (Free) | Install from Play Store, sign in. |

### Windows

```powershell
# Option 1: WSL2 (Recommended)
wsl --install
# Then in WSL:
sudo apt install mosh

# Option 2: Install Tailscale for Windows
# Download from https://tailscale.com/download/windows
```

### macOS

```bash
brew install mosh
# Tailscale: brew install tailscale OR download from App Store
```

### Linux

```bash
# Debian/Ubuntu
sudo apt install mosh

# Fedora/RHEL
sudo dnf install mosh

# Tailscale
curl -fsSL https://tailscale.com/install.sh | sh
sudo tailscale up
```

---

## Daily Usage

Once server and client are set up, this is your daily workflow.

### Connecting via Mosh (Recommended)

Best for extended sessions - survives network changes, sleep/wake, and brief disconnections.

```bash
# Connect and attach to default session
mosh user@yourserver -- claude-session

# Connect to a named session
mosh user@yourserver -- claude-session work
```

**Disconnecting**: Just close the terminal or put your device to sleep. The session keeps running.

**Reconnecting**: Run the same mosh command - you'll be right where you left off.

### Connecting via SSH

For quick connections when mosh isn't available:

```bash
ssh user@yourserver -t 'claude-session'
```

Note: SSH connections don't survive network changes like mosh does.

### Connecting via Web Browser

When you don't have a terminal app (e.g., borrowed computer, tablet):

1. Ensure Tailscale is connected on your device
2. Open your browser to `https://your-server-hostname:7681`
3. Login with:
   - Username: `claude`
   - Password: (from installation, or run `cat ~/.config/claude-remote/web-credentials` on server)

### Working with Sessions

```bash
# List all sessions (from server or while connected)
claude-session --list

# Create/attach to named session
claude-session projectname

# Kill a session
claude-session --kill projectname
```

### Detaching vs Disconnecting

| Action | What Happens | How to Do It |
|--------|--------------|--------------|
| **Detach** | Cleanly exit, session keeps running | `Ctrl+a d` |
| **Disconnect** | Close terminal/browser, session keeps running | Just close it |
| **Kill session** | Terminate the session entirely | `claude-session --kill name` |

### Check Server Status

```bash
# From server
claude-status

# Remotely
ssh user@yourserver claude-status
```

## Security Model

### What's Protected

| Layer | Protection |
|-------|------------|
| **Network Access** | Tailnet-only (not publicly accessible) |
| **Authentication** | Tailscale account + password (effective 2FA) |
| **Web Terminal** | Password authentication required |
| **Network Binding** | ttyd binds to 127.0.0.1 only |
| **Connections** | Max 2 concurrent web clients |
| **Transport** | HTTPS via Tailscale |
| **Idle Sessions** | Auto-lock after 15 minutes |
| **Binary Downloads** | SHA256 checksum verification |
| **Credentials** | Stored with 600 permissions |

### Why Tailnet-Only is Secure

Unlike Tailscale Funnel (which exposes services publicly), Tailscale Serve restricts access to devices on your Tailnet:

1. **Attacker must compromise your Tailscale account** to reach the URL
2. **Your Tailscale account can have 2FA** enabled for additional protection
3. **No public URL to discover** - invisible to the internet
4. **Password is a second factor** - even if someone joins your Tailnet, they need the password

### What This Does NOT Protect Against

- **SSH/Mosh access**: Uses your existing SSH authentication
- **Tailnet member with password**: If someone has both, they can access
- **Shared sessions**: Multiple web clients see the same tmux session
- **Server compromise**: If your server is compromised, sessions are exposed

### Security Recommendations

1. **Enable 2FA on your Tailscale account** (strongly recommended)
2. **Use a strong SSH key** for mosh/SSH access
3. **Use `Ctrl+a C-k`** to clear scrollback after entering sensitive data
4. **Audit your Tailnet members** regularly

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
| `Ctrl+a L` | Lock session manually |
| `Ctrl+a C-k` | Clear scrollback (security) |
| `Ctrl+a [` | Enter scroll/copy mode |
| `Ctrl+a r` | Reload tmux config |

**In scroll mode:**
- Use arrow keys or vim keys to navigate
- `q` to exit scroll mode
- `v` to start selection, `y` to copy

## Configuration

### tmux config
The tmux configuration is installed to `~/.tmux.conf`. Key settings:
- 10,000 line scrollback buffer (security-conscious default)
- Mouse support enabled
- Vim-style keybindings
- 15-minute idle auto-lock
- Status bar with session info

### Web terminal credentials
Stored in `~/.config/claude-remote/web-credentials` with 600 permissions.

To regenerate credentials:
```bash
openssl rand -hex 16 > ~/.config/claude-remote/web-credentials
systemctl --user restart claude-web.service  # Linux
# or
launchctl unload ~/Library/LaunchAgents/com.claude.web.plist && \
launchctl load ~/Library/LaunchAgents/com.claude.web.plist  # macOS
```

### Service management

**Linux (systemd):**
```bash
systemctl --user status claude-web.service
systemctl --user restart claude-web.service
systemctl --user stop claude-web.service
journalctl --user -u claude-web.service  # View logs
```

**macOS (launchd):**
```bash
launchctl list | grep claude
launchctl unload ~/Library/LaunchAgents/com.claude.web.plist
launchctl load ~/Library/LaunchAgents/com.claude.web.plist
```

## Troubleshooting

### Mosh connection fails
1. Ensure UDP ports 60000-60010 are open on your server
2. Check that mosh-server is installed: `which mosh-server`

### Web terminal not accessible
1. Check service status: `claude-status`
2. Verify ttyd is running: `pgrep -a ttyd`
3. Check credentials exist: `cat ~/.config/claude-remote/web-credentials`
4. Verify Tailscale Serve: `tailscale serve status`

### "Authentication failed" on web terminal
1. Ensure you're using username `claude`
2. Check your password: `cat ~/.config/claude-remote/web-credentials`

### tmux session lost after reboot
See [Step 4: Surviving Server Reboots](#step-4-surviving-server-reboots) in the Server Setup section.

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

## License

MIT
