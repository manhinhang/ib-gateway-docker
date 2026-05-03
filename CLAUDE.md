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
- `IBC_AUTO_RESTART_TIME` - When IB Gateway performs its nightly soft restart that preserves the session (default: `11:55 PM`). Set to empty string to disable.
- `IBC_COMMAND_SERVER_PORT` - Port IBC's command server listens on for `RESTART`/`STOP` commands (default: 7462). Set to 0 to disable. Multi-container deployments must set distinct ports per service.
- `IBC_BIND_ADDRESS` - Address the IBC command server binds to (default: `127.0.0.1`). **DO NOT** set to a non-loopback value without locking down access — anyone who can reach the port can shut down or restart your gateway.

## Development Workflow

### Building Locally

```bash
docker build --no-cache -t ib-gateway-docker .
```

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
   - Runs daily via cron
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
