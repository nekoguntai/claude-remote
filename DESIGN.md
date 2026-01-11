# Anyshell - Design Document

This document captures all design decisions, architecture choices, and implementation details for the Anyshell project.

## Project Goal

Enable mobile productivity with Claude Code by providing persistent terminal sessions that:
- Continue running when disconnected
- Can be resumed from any device
- Work with sporadic internet connectivity
- Support multiple platforms (iOS, Android, Windows, Mac, Linux)

## Problem Statement

When using Claude Code (or any long-running terminal process) remotely:
1. Disconnecting kills the process
2. Network changes break the connection
3. Mobile connectivity is unreliable
4. Different devices need different connection methods

## Solution Architecture

### Core Components

```
┌─────────────────────────────────────────────────────────────────┐
│                           SERVER                                 │
│  ┌───────────────────────────────────────────────────────────┐  │
│  │                         tmux                               │  │
│  │   Persistent sessions that survive disconnection           │  │
│  │   ┌─────────────┐  ┌─────────────┐  ┌─────────────┐       │  │
│  │   │   "main"    │  │  "claude"   │  │   "dev"     │       │  │
│  │   └─────────────┘  └─────────────┘  └─────────────┘       │  │
│  └───────────────────────────────────────────────────────────┘  │
│                    ▲                         ▲                   │
│                    │                         │                   │
│  ┌─────────────────┴───────┐   ┌─────────────┴───────────────┐  │
│  │      mosh-server        │   │          ttyd               │  │
│  │   (UDP, roaming)        │   │   (web terminal, localhost) │  │
│  └─────────────────────────┘   └─────────────┬───────────────┘  │
│                                              │                   │
│                                   ┌──────────┴──────────┐       │
│                                   │  Tailscale Serve    │       │
│                                   │  (Tailnet-only)     │       │
│                                   └─────────────────────┘       │
└─────────────────────────────────────────────────────────────────┘
```

### Why These Technologies?

| Component | Choice | Alternatives Considered | Why This Choice |
|-----------|--------|------------------------|-----------------|
| Session persistence | tmux | screen, abduco | Most features, best maintained, plugin ecosystem |
| Native terminal | Mosh | SSH, Eternal Terminal | Best roaming support, handles network changes |
| Web terminal | ttyd | Wetty, code-server | Lightweight, fast, simple |
| Network access | Tailscale Serve | Funnel, Cloudflare, ngrok | Tailnet-only = 2FA possible, not public |

## Security Model

### Evolution of Security Decisions

#### Initial Implementation (Insecure)
- ttyd with no authentication
- Bound to 0.0.0.0 (all interfaces)
- Tailscale Funnel (public exposure)
- No binary verification

#### After Security Audit
1. **Added password authentication** - ttyd `--credential` flag
2. **Localhost binding** - ttyd `--interface 127.0.0.1`
3. **Connection limits** - ttyd `--max-clients 2`
4. **Binary verification** - SHA256 checksums for ttyd downloads
5. **Secure file permissions** - 700 for dirs, 600 for credentials

#### Final Security Model (Tailnet-only)
Switched from Tailscale Funnel to Tailscale Serve:

| Aspect | Funnel (Rejected) | Serve (Chosen) |
|--------|-------------------|----------------|
| Exposure | Public internet | Tailnet only |
| Auth layers | 1 (password) | 2 (Tailscale + password) |
| 2FA possible | No | Yes (via Tailscale account) |
| Attack surface | URL discoverable | Invisible to internet |

### Current Security Layers

```
Layer 1: Network Access
        └── Must be on Tailnet (device auth)

Layer 2: Tailscale Account
        └── Can have 2FA enabled

Layer 3: Password
        └── Required for web terminal

Layer 4: Session Lock
        └── Auto-lock after 15 minutes idle
```

### Threat Model

| Threat | Mitigation |
|--------|------------|
| Unauthorized web access | Tailnet + password auth |
| Brute force password | Rate limited by Tailscale, max 2 clients |
| Session hijacking | WireGuard encryption |
| Credential theft | 600 permissions, secure directory, atomic file creation |
| Supply chain attack | SHA256 checksum verification |
| Idle session exposure | 15-minute idle screen (cosmetic, not security) |
| Scrollback data leak | Reduced buffer (10k), manual clear binding |
| Session name injection | Regex validation on session names |

### Known Security Limitations

| Limitation | Description | Mitigation |
|------------|-------------|------------|
| Password visible in process list | ttyd's `--credential` flag exposes password to `ps aux` | Primary auth is Tailscale; password is defense-in-depth. Multi-user warning added. |
| Idle lock is cosmetic | tmux lock just clears screen, press Enter to continue | Not a security feature - rely on Tailscale/SSH auth |
| armhf not supported | No verified checksum available | Architecture explicitly rejected in installer |
| No brute-force protection | Password attempts not rate-limited at ttyd level | Tailscale provides implicit rate limiting |
| Log files unbounded | ttyd logs can grow indefinitely | Manual logrotate recommended for long-term use |

## Platform Support

### Server Platforms
- **Linux** (Ubuntu/Debian, RHEL/Fedora)
  - systemd user service
  - apt/dnf package management
  - ttyd from GitHub releases (verified)

- **macOS**
  - launchd user agent
  - Homebrew package management
  - ttyd from Homebrew

### Client Platforms

| Platform | Mosh Client | Web Access |
|----------|-------------|------------|
| iOS/iPadOS | Blink Shell ($20), Termius | Safari + Tailscale app |
| Android | Termux, JuiceSSH | Chrome + Tailscale app |
| Windows | WSL2 + mosh | Browser + Tailscale |
| macOS | Native terminal | Browser + Tailscale |
| Linux | Native terminal | Browser + Tailscale |

## File Structure

```
anyshell/
├── install.sh              # Main installer (OS detection, package install, service setup)
├── uninstall.sh            # Clean removal
├── config/
│   └── tmux.conf           # Optimized tmux configuration
├── scripts/
│   ├── anyshell      # Session management (create/attach/list/kill)
│   ├── web-terminal        # ttyd wrapper for tmux attachment
│   ├── ttyd-wrapper        # Credential loading wrapper for services
│   ├── status              # Status display utility
│   └── maintenance         # Cleanup and maintenance tasks
├── systemd/
│   ├── anyshell-web.service          # Linux systemd user service
│   ├── anyshell-maintenance.service  # Maintenance oneshot service
│   └── anyshell-maintenance.timer    # Weekly maintenance timer
├── launchd/
│   ├── com.anyshell.web.plist         # macOS launchd agent
│   └── com.anyshell.maintenance.plist # macOS maintenance agent
├── README.md               # User documentation
└── DESIGN.md               # This file
```

## Configuration Files (on installed system)

| Path | Purpose | Permissions |
|------|---------|-------------|
| `~/.tmux.conf` | tmux configuration | 644 |
| `~/.config/anyshell/web-credentials` | Web terminal password | 600 |
| `~/.config/systemd/user/anyshell-web.service` | Linux service | 644 |
| `~/Library/LaunchAgents/com.anyshell.web.plist` | macOS service | 644 |
| `~/.local/bin/anyshell` | Session script | 755 |
| `~/.local/bin/ttyd-wrapper` | Service wrapper | 755 |
| `~/.local/share/anyshell/` | Logs directory | 700 |

## Key Implementation Details

### Credential Handling

Problem: systemd/launchd can't easily read files for command arguments.

Solution: Created `ttyd-wrapper` script that:
1. Reads password from `~/.config/anyshell/web-credentials`
2. Constructs ttyd command with `--credential` flag
3. Executed by service instead of ttyd directly

### Binary Verification

ttyd binaries downloaded from GitHub are verified:
```bash
TTYD_VERSION="1.7.7"
TTYD_CHECKSUMS=(
    ["x86_64"]="a68fca635dbc2b8d2d7c6a4442f0d59246c909c07051aba02834d84e81396fe9"
    ["aarch64"]="7e71bae2c0b96e8d66ad4611e075c2c22561fac55ccd7df085d86f5d4bf3cb26"
)
```

### Session Name Validation

Prevents command injection via session names:
```bash
if [[ ! "$name" =~ ^[a-zA-Z0-9_-]{1,64}$ ]]; then
    # Reject invalid session name
fi
```

### systemd Hardening

```ini
NoNewPrivileges=true
PrivateTmp=true
PrivateDevices=true
ProtectSystem=strict
ProtectHome=read-only
ReadWritePaths=%h/.local/share/anyshell %h/.config/anyshell
ProtectKernelTunables=true
ProtectKernelModules=true
ProtectControlGroups=true
RestrictRealtime=true
RestrictSUIDSGID=true
LockPersonality=true
```

## Encryption Summary

### Mosh Connection
```
iPhone ←→ Mac
   └── SSH (initial): AES-256-GCM
   └── Mosh (ongoing): AES-128-OCB (UDP)
```

### Web Terminal Connection
```
iPhone ←→ Mac
   └── Tailscale: WireGuard (ChaCha20-Poly1305)
   └── Loopback segments: Not encrypted (same device)
```

Both methods provide end-to-end encryption for all network traffic.

## tmux Configuration Highlights

| Setting | Value | Reason |
|---------|-------|--------|
| Prefix | `Ctrl+a` | Easier to reach than `Ctrl+b` |
| History limit | 10,000 | Balance usability vs security |
| Lock timeout | 15 minutes | Auto-lock idle sessions |
| Mouse | Enabled | Touch-friendly |
| Mode keys | vi | Familiar navigation |

### Security Bindings
- `Ctrl+a L` - Manual lock
- `Ctrl+a C-k` - Clear scrollback (remove sensitive data)

## Future Considerations

### Not Implemented (Could Add Later)

1. **Per-session passwords** - Different passwords for different tmux sessions
2. **Session recording** - Audit logging of terminal sessions
3. **tmux-resurrect** - Persist sessions across server reboots
4. **Cloudflare Tunnel option** - Alternative to Tailscale
5. **Hardware key support** - WebAuthn for web terminal
6. **Rate limiting** - Fail2ban-style blocking for failed auth

### Known Limitations

1. **Shared sessions** - Multiple web clients see same tmux session
2. **No session isolation** - All sessions run as same user
3. **Reboot loses sessions** - tmux sessions don't survive reboot
4. **Tailscale required for web** - No fallback for web access

## Deployment Checklist

1. [ ] Clone repository to server
2. [ ] Run `./install.sh`
3. [ ] Save displayed web password
4. [ ] Install Tailscale on server if not present
5. [ ] Run `sudo tailscale up`
6. [ ] Enable 2FA on Tailscale account
7. [ ] Install Tailscale on client devices
8. [ ] Test mosh connection
9. [ ] Test web terminal connection

## References

- [Mosh](https://mosh.org/) - Mobile shell
- [tmux](https://github.com/tmux/tmux) - Terminal multiplexer
- [ttyd](https://github.com/tsl0922/ttyd) - Web terminal
- [Tailscale](https://tailscale.com/) - Zero-config VPN
- [WireGuard](https://www.wireguard.com/) - Modern VPN protocol
