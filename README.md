# AxeSSH

> A native macOS menu bar app for managing SSH connections and browsing remote files over SFTP—built with SwiftUI and designed to stay out of the way until you need it.

<div align="center">
	<video src="assets/demo.mp4" controls autoplay loop muted playsinline width="85%"></video>
</div>
---

## Highlights

- **Native experience** — SwiftUI, menu bar integration, and system conventions
- **Zero extra installs** — Bundles `sshpass` for password auth; no Homebrew required
- **Terminal-agnostic** — Uses iTerm when available, falls back to Terminal.app
- **Full SFTP workflow** — List, upload (drag-and-drop), delete, with overwrite safety

---

## Features

### Connection Management

- **Save SSH profiles** — Host, port, username, authentication (password or SSH key)
- **Optional base path** — Start sessions in a specific remote directory
- **Quick connect** — Opens Terminal or iTerm with one click
- **Connection status** — Track connected vs disconnected sessions

### SFTP File Browser

- **Browse remote directories** — Navigate folder structure with breadcrumbs
- **Upload files and folders** — Toolbar button or drag-and-drop
- **Delete remote items** — Multi-select files and folders, confirm before delete
- **Overwrite confirmation** — Warns when uploading would overwrite existing files
- **Refresh** — Reload directory contents on demand

### Authentication

- **Password** — Uses bundled `sshpass` so users don't need to install anything
- **SSH keys** — Private key path with recent paths for quick selection

---

## Requirements

- macOS 13.0 or later
- Xcode 15+ (for building)

---

## Quick Start

### Build

```bash
# One-time: build and bundle sshpass (for password auth)
./scripts/build-sshpass.sh

# Build the app
swift build -c release
```

### Run

```bash
swift run
```

The app appears in the menu bar. Click the terminal icon to add connections and connect.

---

## Project Structure

```
Sources/AxeSSH/
├── App/           # App entry point, AppState
├── Models/        # SSHProfile, RemoteFileItem
├── Services/      # SFTPService, TerminalLauncher, ProfileStore
├── Views/         # SwiftUI views (menu bar, file browser, profile editor)
└── Resources/     # sshpass binary (after build-sshpass.sh)
```

---

## Tech Stack

- **Swift 6.2** with SwiftUI
- **SFTP** via `/usr/bin/sftp` and SSH via `/usr/bin/ssh`
- **Terminal integration** — AppleScript to launch Terminal or iTerm
- **Persistence** — UserDefaults for saved profiles

## Implementation Notes

- **Async SFTP** — Long-running operations run off the main thread; UI stays responsive
- **Auth flexibility** — Password flow uses `sshpass` + `script`; key-based uses `BatchMode`
- **Menu bar window handling** — Uses `NSApp.setActivationPolicy` and `orderFrontRegardless` so file browser and editor windows reliably appear on top when opened from the menu

---

## Building for Distribution

See [BUILD.md](BUILD.md) for detailed instructions on building `sshpass` and creating distributable app bundles.

---

## License

MIT License. See [LICENSE](LICENSE).
