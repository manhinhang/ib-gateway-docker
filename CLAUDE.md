# CLAUDE.md

This document provides context for AI assistants (like Claude) working with the IB Gateway Docker project.

## Project Overview

**IB Gateway Docker** is a lightweight Docker container for Interactive Brokers Gateway (IB Gateway). This project provides a headless, automated solution for running IB Gateway in containerized environments without VNC or GUI dependencies.

### Key Features
- Automated IB Gateway setup and login using IBC (Interactive Brokers Controller)
- Headless operation using Xvfb (virtual framebuffer)
- Health check capabilities (CLI and REST API)
- Minimal attack surface (no VNC, no extra ports)
- Automated version updates via GitHub Actions
- Published to Docker Hub: `manhinhang/ib-gateway-docker`

### Current Versions
- **IB Gateway**: 10.37.1m
- **IBC**: 3.23.0
- **Java**: OpenJDK 17
- **Base Image**: Debian Bookworm Slim

## Project Structure

```
.
├── Dockerfile              # Multi-stage Docker build
├── start.sh               # Container entrypoint script
├── ibc/                   # IBC configuration files
│   └── config.ini        # IBC settings
├── healthcheck/          # Health check tools (Java/Gradle)
│   ├── healthcheck/      # CLI health check tool
│   └── healthcheck-rest/ # REST API health check service
├── test/                 # Python tests using testinfra
│   ├── test_ib_gateway.py
│   ├── test_ib_gateway_fail.py
│   └── test_docker_interactive.py
├── examples/             # Usage examples
│   └── ib_insync/       # ib_insync integration example
├── scripts/              # Utility scripts
│   ├── detect_ibc_ver.py
│   └── extract_ib_gateway_major_minor.sh
├── .github/workflows/    # GitHub Actions CI/CD
│   ├── build-test.yml   # Build and test workflow
│   ├── deploy.yml       # Docker Hub deployment
│   └── detect-new-ver.yml # Automated version detection
└── doc/                 # Documentation assets
```

## Architecture

### Docker Build Stages

The Dockerfile uses a **multi-stage build** approach:

1. **Downloader Stage** (`debian:bookworm-slim`)
   - Downloads IB Gateway installer from Interactive Brokers
   - Downloads latest IBC release from GitHub
   - Extracts version information
   - Prepares IBC configuration

2. **Healthcheck Tools Stage** (`gradle:8.7.0-jdk17`)
   - Builds Java-based health check CLI tool
   - Builds Java-based REST API health check service
   - Creates distribution packages

3. **Final Stage** (`debian:bookworm-slim`)
   - Installs minimal dependencies (Xvfb, Java 17, etc.)
   - Copies IB Gateway, IBC, and health check tools
   - Configures environment and entrypoint

### Runtime Flow

1. `start.sh` is executed as the container entrypoint
2. Xvfb starts on display `$DISPLAY` (headless X server, default `:0`)
3. IBC's `OverrideTwsApiPort` is rewritten to `$IBGW_INTERNAL_PORT`
   (default `4001`); IB Gateway's Java binds that port internally
4. socat forwards external `$IBGW_PORT` (default `4002`) → internal
   `$IBGW_INTERNAL_PORT` when the two ports differ
5. Optional: Health check REST API starts on port 8080
6. IBC launches IB Gateway with provided credentials
7. Cleanup handlers trap INT/TERM signals for graceful shutdown

### Session Persistence

IB Gateway only skips 2FA on launch if it finds an **autorestart file** on
disk (it logs `autorestart file found` vs `autorestart file not found:
full authentication will be required`). That file is *only* written when
IB Gateway performs its own soft restart — never on a normal login, and
never when something kills the JVM externally. The setup uses three
mechanisms together to keep this file fresh:

1. **IBC `AutoRestartTime`** (env var `IBC_AUTO_RESTART_TIME`, default
   `11:00 AM` UTC) schedules an internal JVM soft restart once a day.
   IB Gateway writes the autorestart file then bounces — no 2FA. Primary
   defence against IBKR's ~24h token expiry. The default lands in the gap
   between HK regular close (08:00 UTC) and US regular open (13:30 UTC EDT
   summer / 14:30 UTC EST winter), so the ~60–90s restart window doesn't
   overlap either market's regular session — see *Picking a restart time*
   below if you trade other markets.
2. **IBC command server** (env vars `IBC_COMMAND_SERVER_PORT` default
   `7462`, `IBC_BIND_ADDRESS` default `127.0.0.1`) lets the host send
   `RESTART` over loopback to trigger the same soft-restart codepath on
   demand. Use `./scripts/restart-ib-gateway.sh` to send it.
3. **Persistent `/root/Jts` volume** stores the autorestart file (plus
   `jts.ini` and the device-fingerprint dir) so it survives a container
   exit and a fresh PID 1.

`start.sh` injects all three values into `/root/ibc/config.ini` at boot —
the committed config keeps upstream defaults so the file stays portable.

#### Operational matrix

The autorestart file is **single-use** — IB Gateway writes it at the start
of every soft restart, the next launcher reads it and immediately consumes
it. So the file does *not* sit around waiting for a future restart; only
the soft-restart codepath itself bridges sessions.

| Action | 2FA required? | Use it for |
|--------|---------------|------------|
| `docker compose restart` (any time) | **YES** — kills the JVM directly; no autorestart file is written before it dies, and any prior file has already been consumed | Avoid for live |
| `./scripts/restart-ib-gateway.sh` (IBC RESTART over loopback) | **NO** — runs the soft-restart codepath: writes a fresh autorestart file, exits the JVM, the new JVM consumes the file | Ad-hoc restarts, config reloads |
| Nightly `AutoRestartTime` (default `11:00 AM` UTC, automatic) | **NO** — same codepath as RESTART | Always on, no action needed |
| First start with empty volume, or after `docker volume rm`, or after Sunday 1AM ET reset | **YES** | Unavoidable |

IBC's RESTART command is **asynchronous** — it sets the auto-restart time
to "now + ~1 minute" and lets IB Gateway's regular auto-restart logic
fire. Expect a ~60–90 second gap between sending RESTART and the new
session being healthy. The verify script (`scripts/verify-session-persistence.sh`)
waits for the launcher's `autorestart file found` log line as the
authoritative success signal, then waits for the healthcheck to flip back.

#### Picking a restart time

`AutoRestartTime` is interpreted in the container's timezone, which is
**UTC** (`user.timezone = Etc/UTC`). The format IBC accepts is `hh:mm AM`
or `hh:mm PM` (no seconds). Two windows where neither HK nor US regular
markets are trading:

| Window | UTC range | HKT range | ET range | Notes |
|--------|-----------|-----------|----------|-------|
| After HK close, before US open | 08:00 – 13:30 (EDT) / 14:30 (EST) | 16:00 – 21:30 (EDT) / 22:30 (EST) | 04:00 – 09:30 ET | The default `11:00 AM` UTC sits here |
| After US close, before HK open | 20:00 (EDT) / 21:00 (EST) – 01:30 next day | 04:00 – 09:30 next day | 16:00 – 21:30 ET | Older default `11:55 PM` was here, only ~1.5h before HK open |

Override via env if you trade other markets:

```bash
# Tokyo trader who wants the restart between TSE close (06:00 UTC) and
# US open (13:30 UTC summer):
IBC_AUTO_RESTART_TIME="10:00 AM"

# London trader who wants the restart well before LSE open (08:00 UTC):
IBC_AUTO_RESTART_TIME="04:00 AM"
```

**Hard limits** (cannot be worked around):
- IBKR fully resets every Sunday 1AM ET — the next login after that boundary
  always requires 2FA, regardless of the autorestart file.
- Volumes are *per IB account*. If you change `IB_ACCOUNT`, the cached
  fingerprint is for the previous user — IBKR will challenge 2FA. Wipe the
  volume in that case.
- Multi-container deployments need distinct command-server ports because
  host networking shares loopback. `docker-compose.multi.yaml` already
  assigns paper=`7462` and live=`7463` via `IBC_COMMAND_SERVER_PORT`; add
  more services with their own ports if you fan out further.

**Security:** the command server on `IBC_BIND_ADDRESS:IBC_COMMAND_SERVER_PORT`
(default `127.0.0.1:7462`) accepts `RESTART`, `STOP`, and other commands
from any process that can reach it. With `network_mode: host`, an empty
`BindAddress=` would expose it on every NIC — do NOT set
`IBC_BIND_ADDRESS` to a non-loopback value without locking down who can
reach the port. **The volume contains a credential-equivalent device
fingerprint** — treat `/var/lib/docker/volumes/<...>-jts/` with the same
sensitivity as `.secrets`.

## Environment Variables

### Required
- `IB_ACCOUNT` - Interactive Brokers account username
- `IB_PASSWORD` - Interactive Brokers account password
- `TRADING_MODE` - Either `paper` or `live`

### Optional
- `IBGW_PORT` - Gateway port (default: 4002)
- `IBGW_INTERNAL_PORT` - Internal port IB Gateway's Java binds (default: 4001)
- `JAVA_HEAP_SIZE` - JVM heap size in MB (default: 768)
- `HEALTHCHECK_API_ENABLE` - Enable REST API health check (default: false)
- `TWOFA_TIMEOUT_ACTION` - Action on 2FA timeout (default: restart)
- `DISPLAY` - X display (default: :0, set automatically)
- `IBC_AUTO_RESTART_TIME` - When IB Gateway performs its nightly soft restart that preserves the session (default: `11:00 AM`, UTC). Set to empty string to disable.
- `IBC_COMMAND_SERVER_PORT` - Port IBC's command server listens on for `RESTART`/`STOP` commands (default: 7462). Set to 0 to disable. Multi-container deployments must set distinct ports per service.
- `IBC_BIND_ADDRESS` - Address the IBC command server binds to (default: `127.0.0.1`). **DO NOT** set to a non-loopback value without locking down access — anyone who can reach the port can shut down or restart your gateway.
- `IBC_SECOND_FACTOR_DEVICE` - Which 2FA method IBC preselects when the account has more than one registered (default: `IB Key`). Must match IBKR's device-list entry exactly; set to empty string to disable preselection and pick manually. See *Second-factor authentication* below.
- `IBC_RELOGIN_AFTER_2FA_TIMEOUT` - Whether IBC retries login after an unanswered 2FA prompt (default: `yes`). Must be `yes` or `no`.
- `IBC_LOG_STRUCTURE_SCOPE` / `IBC_LOG_STRUCTURE_WHEN` - Opt-in IBC window logging for diagnosing a dialog that blocks login headlessly (unset = upstream defaults `known`/`never`). Set to `all` / `activate` when investigating.

### Build arguments

Passed with `--build-arg` (or via a compose `build.args` block), not at runtime.

| Arg | Default | Purpose |
|-----|---------|---------|
| `CHANNEL` | `latest` | IB Gateway release channel to install (`latest` or `stable`). |
| `TARGETARCH` | (set by buildx) | Selects the native IB installer (`amd64` → `linux-x64`, `arm64` → `linux-arm`). |
| `ENABLE_SCREEN_CAPTURE` | `false` | Installs `x11-apps`, `imagemagick`, `zbar-tools` for `scripts/capture-screen.sh` (~50MB). Debugging only — the script fails with a rebuild hint if absent. |
| `ENABLE_PASSKEY` | `false` | Installs the Chromium + Bluetooth client libraries needed to *render* a passkey (WebAuthn) second factor (~40MB). See *Enabling passkey (WebAuthn) support*. |

## Helper scripts

| Script | Purpose |
|--------|---------|
| `scripts/restart-ib-gateway.sh` | Sends `RESTART` to IBC's command server over loopback — soft-restarts IB Gateway *without* re-triggering 2FA. Use instead of `docker compose restart`. |
| `scripts/verify-session-persistence.sh` | End-to-end check that a soft restart preserves the session (no 2FA prompt, autorestart file present). Exit 0 = pass, 1 = fail, 2 = preconditions missing. |
| `scripts/capture-screen.sh` | Captures the headless Xvfb display to PNG (root window plus each named window by id) and decodes any QR code. Use to identify a modal dialog blocking login. |
| `scripts/detect_ibc_ver.py` | Resolves the newest IBC release; used by the version-detection workflow. |
| `scripts/extract_ib_gateway_major_minor.sh` | Parses a version like `10.45.1c` into `IB_GATEWAY_MAJOR`/`_MINOR`. **Must be sourced**, not executed — it sets caller-scope variables. |
| `scripts/ci/graceful-stop.sh` | CI helper that logs IB Gateway off its IBKR session before the container/pod is destroyed. |
| `scripts/k8s/k3d-up.sh` / `k3d-down.sh` | Stands up a local k3d cluster, builds and imports the image, applies the `examples/k8s/` manifests (and tears it all down). |
| `scripts/k8s/restart-ib-gateway-k8s.sh` | Kubernetes equivalent of the IBC `RESTART` helper. |
| `scripts/k8s/verify-session-persistence-k8s.sh` | Kubernetes equivalent of the session-persistence check. |


## Second-factor authentication

**IBKR Mobile push ("IB Key") works out of the box.** Passkeys need the
optional build (`ENABLE_PASSKEY=true` + `docker-compose.passkey.yaml`) *and*
real Bluetooth hardware on the host — the constraint is the transport, not
configuration:

| Method | Works headlessly? | Why |
|--------|-------------------|-----|
| **IB Key** (IBKR Mobile push — tap Approve) | **Yes**, no extras | Pure push/pull over the network; no browser or local hardware involved |
| Passkey on a phone (QR code) | **Only on a host with a BLE radio** | The host must *receive a BLE advertisement* from the phone — the QR code only carries key material. Chromium's `device/fido/cable/v2_discovery.cc` aborts discovery unless an adapter is present *and* powered, reached via BlueZ over D-Bus. Build with `ENABLE_PASSKEY=true` and run `docker-compose.passkey.yaml` (mounts the host D-Bus). Impossible on a remote VM with no radio, and the phone must be within ~10m |
| Passkey in a password manager (e.g. 1Password) | **No** | Needs either a browser extension — impossible in IB Gateway's *embedded* JxBrowser — or the same phone hybrid flow above. Changing where the credential is stored does not create a transport |
| USB security key | Only with passthrough | Needs `--device=/dev/hidraw0` plus explicit ownership/mode. udev's `uaccess` ACLs are granted to an active logind seat, which a container does not have |

IBC ≥3.24.0 does pass `-DjxBrowserKey` (read from `.install4j/i4jparams.conf`)
so passkey ceremonies can *render* — the build always pulls the newest IBC, so
that fix is present. But rendering is not the blocker for a phone passkey; the
BLE transport is. Adding a passkey to an account that currently uses IB Key
makes IBKR show a device-selection list, so keep `IBC_SECOND_FACTOR_DEVICE` in
sync with the exact entry text.

### Seeing what is on the headless screen

`scripts/capture-screen.sh` captures the container's Xvfb display to a PNG
(via `xwd` + ImageMagick, run inside the container so the host needs no X
tooling) and decodes any QR code in it with `zbarimg`, re-rendering it in the
terminal with `qrencode`.

```bash
./scripts/capture-screen.sh                 # -> ./ib-gateway-screen.png
CONTAINER=<name|id> ./scripts/capture-screen.sh
```

It reads `DISPLAY` from the container rather than assuming `:0`, since
`docker-compose.yaml` sets `:99` to avoid colliding with a host X server
under host networking.

Use it to identify a modal dialog that is blocking login — IB Gateway will
not open its API port while one is up, so the healthcheck hangs with no clue
as to why. Pair it with `IBC_LOG_STRUCTURE_SCOPE=all` /
`IBC_LOG_STRUCTURE_WHEN=activate`.

**On passkey QR codes:** the script decodes a QR if one is present, but for a
passkey login do not expect one. Chromium only offers the "use a phone or
tablet" QR option when a Bluetooth adapter is present, so in a container the
dialog offers only the USB security-key path and no QR is generated. Even
with a QR, scanning it from a remote device cannot complete the login — see
the transport table above. The script prints this caveat when it decodes a
`FIDO:/` payload.

**The capture may contain account details** (account number, username on the
login screen). It is written owner-only; delete it when done and redact
before attaching to an issue.

### Enabling passkey (WebAuthn) support

Passkey support is **off by default** — the libraries only matter for accounts
whose second factor is a passkey, and they add ~40MB.

```bash
# Build with the Chromium + BlueZ dependencies
docker compose -f docker-compose.yaml -f docker-compose.passkey.yaml build
# Run with D-Bus + shm wired up
docker compose -f docker-compose.yaml -f docker-compose.passkey.yaml up -d
```

`docker-compose.passkey.yaml` sets `shm_size: 1gb` (Chromium crashes on
Docker's default 64MB `/dev/shm`), mounts the host's D-Bus system socket so
Chromium can reach BlueZ, and adds `NET_ADMIN`.

**Which libraries, and why these.** The list is not the vendor's generic
54-package recommendation — it is what `ldd` reports as actually unresolved
for the Chromium that ships inside
`jars/jxbrowser-linux64-8.9.4.jar` (extract with the bundled `7zr-linux64`)
against this image:

| Missing object | Package |
|---|---|
| `libgbm.so.1` | `libgbm1` |
| `libgtk-3.so.0`, `libgdk-3.so.0` | `libgtk-3-0` |
| `libnss3.so`, `libnssutil3.so`, `libsmime3.so` | `libnss3` |
| `libnspr4.so` | `libnspr4` |

`libasound.so.2` and `libXtst.so.6` are already satisfied via `xvfb` /
`libxtst6`; `libjawt.so` resolves at runtime from IB's bundled JRE. Verified:
with these installed, `ldd` reports no unresolved objects for `chromium`,
`libtoolkit.so`, `libEGL.so`, `libGLESv2.so`, or `libipc.so`.

**This does not make a phone passkey work on a headless server.** Installing
BlueZ does not create a radio. Chromium's cross-device flow needs an adapter
that is present *and* powered, plus your phone within BLE range. Check the
host before expecting the QR flow to appear:

```bash
ls /sys/class/bluetooth/     # must list hci0 (or similar)
bluetoothctl list            # must show a controller
systemctl is-active bluetooth
```

An empty `/sys/class/bluetooth` means the QR option will not be offered at
all — the dialog will show only the USB security-key path.

**Security note:** mounting the host D-Bus system socket is a broad grant, not
a Bluetooth-only one. Prefer enabling this overlay only on a machine you
control.

### Why `IBC_RELOGIN_AFTER_2FA_TIMEOUT` defaults to `yes`

IBC's `LoginManager.reloginPermitted()` gates the *entire* 2FA-timeout path on
this setting. With the upstream default `no`, an unanswered 2FA prompt logs
`Re-login after second factor authentication timeout not required` and then
nothing happens — IB Gateway sits at the dialog indefinitely and never opens
its API port. `TWOFA_TIMEOUT_ACTION=restart` cannot help, because the restart
is driven by exit code 1111 (`SECOND_FACTOR_AUTH_LOGIN_TIMED_OUT`), which IBC
only raises when relogin is permitted. So the image's `restart` default was
unreachable for the timeout case until this was set to `yes`.

Retrying is safe: IBC's `TooManyFailedLoginAttemptsDialogHandler` parses
IBKR's "please wait N seconds" lockout message and waits out the backoff.

## Development Workflow

### Building Locally

```bash
docker build --no-cache -t ib-gateway-docker .
```

The image is multi-arch (`linux/amd64` + `linux/arm64`). IB ships native
per-arch Linux installers — `ibgateway-...-linux-x64.sh` and
`ibgateway-...-linux-arm.sh` — each carrying a bundled JVM for its
architecture. The Dockerfile's downloader stage reads `TARGETARCH`
(populated automatically by buildx) and fetches the matching installer, so
amd64 and arm64 builds each install IB Gateway with a native bundled JVM.
To build a specific arch locally:

```bash
docker buildx build --platform linux/arm64 -t ib-gateway-docker .
```

CI builds each arch natively (`deploy.yml` uses `ubuntu-latest` and
`ubuntu-24.04-arm` runners, pushes by digest, then merges a multi-arch
manifest).

### Running Locally

```bash
docker run -d \
  --env IB_ACCOUNT=your_account \
  --env IB_PASSWORD=your_password \
  --env TRADING_MODE=paper \
  -p 4002:4002 \
  ib-gateway-docker
```

### Running Paper + Live Side-by-Side

Two gateways can run simultaneously since each container's IB Gateway binds
its own `IBGW_PORT` directly (no socat indirection). Use the bundled
multi-service compose file:

```bash
# .env supplies IB_PAPER_ACCOUNT/PASSWORD and IB_LIVE_ACCOUNT/PASSWORD
docker compose -f docker-compose.multi.yaml up -d
# paper → localhost:4002, live → localhost:4001
```

### Running on Kubernetes

Plain-YAML manifests for both single and multi-gateway are in
[`examples/k8s/`](examples/k8s/), with a k3d-based local verification
helper at [`scripts/k8s/k3d-up.sh`](scripts/k8s/k3d-up.sh). The compose
multi setup's per-service `IBGW_INTERNAL_PORT` and
`IBC_COMMAND_SERVER_PORT` overrides do **not** transfer — those exist
only because `network_mode: host` makes paper and live share the host's
loopback. Each k8s pod has its own network namespace, so both pods keep
upstream defaults inside themselves and only `IBGW_PORT` differs.

### Running Tests

Tests use **pytest** and **testinfra**:

```bash
# Install test dependencies
pip install -r requirements-test.txt

# Run tests
pytest
```

**Important**: Tests require valid IB account credentials:
- `IB_ACCOUNT` - Test account username
- `IB_PASSWORD` - Test account password
- `TRADING_MODE` - Trading mode (paper/live)
- `IMAGE_NAME` - Docker image to test

### Health Checks

Two health check methods are available:

1. **CLI Health Check**
   ```bash
   docker exec <container_id> healthcheck
   # Exit code 0 = healthy, 1 = unhealthy
   ```

2. **REST API Health Check**
   ```bash
   curl -f http://localhost:8080/healthcheck
   # HTTP 200 = healthy, non-200 = unhealthy
   ```

## CI/CD Pipeline

### GitHub Actions Workflows

1. **build-test.yml** - Build and test on push/PR
   - Builds Docker image
   - Runs pytest tests with real IB credentials
   - Requires secrets: `IB_ACCOUNT`, `IB_PASSWORD`

2. **deploy.yml** - Deploy to Docker Hub
   - Triggered on version tag pushes
   - Builds and pushes to Docker Hub
   - Requires secrets: `DOCKERHUB_USERNAME`, `DOCKERHUB_TOKEN`

3. **detect-new-ver.yml** - Automated version updates
   - Runs Sun-Fri at 12:00 UTC via cron (skips Saturday to avoid IBKR maintenance)
   - Detects new IB Gateway and IBC versions
   - Creates PR with updated Dockerfile and README
   - Uses version detection scripts

### GitHub Secrets Required

- `IB_ACCOUNT` - Paper trading account for CI tests
- `IB_PASSWORD` - Paper trading account password
- `DOCKERHUB_USERNAME` - Docker Hub username
- `DOCKERHUB_TOKEN` - Docker Hub access token

## Code Conventions

### Shell Scripts
- Use `#!/bin/bash` shebang
- Set `set -e` for error handling
- Use cleanup traps for graceful shutdown
- Quote variables to prevent word splitting

### Dockerfile
- Use multi-stage builds to minimize final image size
- Pin base image versions (e.g., `debian:bookworm-slim`)
- Combine RUN commands to reduce layers
- Use `.dockerignore` to exclude unnecessary files
- Document environment variables with `ENV`

### Python Tests
- Follow pytest conventions
- Use environment variables for configuration
- Clean up Docker containers after tests
- Include both positive and negative test cases

### Version Management
- IB Gateway version is automatically detected from Interactive Brokers
- IBC version is pulled from GitHub releases API
- Templates are updated via scripts when new versions are detected

## Common Tasks

### Updating IB Gateway Version

The version update is **automated** via GitHub Actions, but can be done manually:

1. Update version in `Dockerfile` if not using auto-detection
2. Update version in `README.md`
3. Test the build: `docker build -t test-image .`
4. Create PR with changes

**Volume wipe required on version bump.** Because the persistent `/root/Jts`
volume is initialised from the image's `/root/Jts` only on first mount, an
existing volume keeps the *old* IB Gateway binary and hides the new install.
`start.sh` then picks the old version via `ls $TWS_PATH/ibgateway`. After
bumping `versions.env`, run:

```bash
docker compose down
docker volume ls | grep -E 'jts$'                # find the volume name(s)
docker volume rm ib-gateway-docker_ib-gateway-jts  # adjust prefix
docker compose up -d                              # IBKR will 2FA once
```

The 2FA on first start is unavoidable — the new binary writes a new device
fingerprint that IBKR has not yet trusted.

### Adding New Features

1. Create feature branch from `develop`
2. Make changes (code, tests, docs)
3. Update tests in `test/` directory
4. Run local tests: `pytest`
5. Update README.md if user-facing changes
6. Create PR to `develop` branch

### Modifying IBC Configuration

Edit `ibc/config.ini` to change IBC behavior:
- Login automation settings
- 2FA handling
- API port configuration
- Logging options

After changes, rebuild the Docker image.

### Adding Dependencies

**System packages** (Dockerfile):
```dockerfile
RUN apt-get install -y package-name
```

**Python test dependencies** (requirements-test.txt):
```
pytest==x.x.x
testinfra==x.x.x
```

## Troubleshooting

### Common Issues

1. **Container exits immediately**
   - Check credentials are valid
   - Review logs: `docker logs <container_id>`
   - Verify TRADING_MODE is `paper` or `live`

2. **Health check fails**
   - Wait 30-60s after container start
   - Check IB Gateway started: `docker logs <container_id>`
   - Verify port 4002 is accessible

3. **Xvfb timeout**
   - Usually indicates system resource issues
   - Check Docker resource limits
   - Review Xvfb logs in container output

4. **2FA issues**
   - Configure TWOFA_TIMEOUT_ACTION appropriately
   - Some accounts require device authentication
   - Check IBC configuration in `ibc/config.ini`

## Testing Strategy

- **Unit tests**: N/A (no application logic, infrastructure only)
- **Integration tests**: Python/testinfra tests in `test/`
- **Smoke tests**: Health check validation after container start
- **CI tests**: Automated builds and tests on every push

## Important Notes

1. **Security**: Never commit IB credentials to version control
2. **Paper Trading**: Use paper trading for all CI/CD testing
3. **API Port**: IB Gateway's Java binds `$IBGW_INTERNAL_PORT` (default
   `4001`); socat exposes that as `$IBGW_PORT` (default `4002`) for
   external clients. Multi-container deployments override
   `IBGW_INTERNAL_PORT` per container to avoid port-bind races
4. **Display**: Xvfb required for headless IB Gateway operation
5. **Cleanup**: Always properly stop containers to avoid orphaned processes
6. **Versions**: IB Gateway updates frequently; automated detection helps

## External Dependencies

- **IB Gateway**: Downloaded from Interactive Brokers
  - URL: `https://download2.interactivebrokers.com/installers/ibgateway/stable-standalone/`

- **IBC**: Downloaded from GitHub releases
  - Repo: `https://github.com/IbcAlpha/IBC`

- **Base Images**:
  - `debian:bookworm-slim`
  - `gradle:8.7.0-jdk17`

## Resources

- [Interactive Brokers API](https://www.interactivebrokers.com/en/index.php?f=16457)
- [IBC Documentation](https://github.com/IbcAlpha/IBC)
- [Docker Hub Repository](https://hub.docker.com/r/manhinhang/ib-gateway-docker)
- [GitHub Repository](https://github.com/manhinhang/ib-gateway-docker)

## License

This project is licensed under the terms specified in the LICENSE file.

**Disclaimer**: This project is not affiliated with Interactive Brokers Group, Inc.
