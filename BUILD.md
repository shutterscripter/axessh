# Building AxeSSH for distribution

The app uses **sshpass** to supply saved passwords when connecting via SSH. So that end users do not need to install anything, sshpass is bundled with the app.

## One-time: build sshpass

Before building the app (or in your CI), run:

```bash
./scripts/build-sshpass.sh
```

This downloads the sshpass source, compiles it, and copies the binary to `Sources/AxeSSH/Resources/sshpass`. That binary is then included when you build the app.

## Build the app

```bash
swift build -c release
# or create an .app bundle for distribution; the Resources folder (with sshpass) will be included
```

If you skip the script, the app still builds but will look for `sshpass` on the PATH when a connection uses a password (e.g. after `brew install sshpass`).
