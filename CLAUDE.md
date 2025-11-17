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
├── Dockerfile.template     # Template for automated version updates
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
│   ├── detect_ib_gateway_ver.py
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
2. Xvfb starts on display `:0` (headless X server)
3. Port forwarding configured via `socat` (4001 → 4002)
4. Optional: Health check REST API starts on port 8080
5. IBC launches IB Gateway with provided credentials
6. Cleanup handlers trap INT/TERM signals for graceful shutdown

## Environment Variables

### Required
- `IB_ACCOUNT` - Interactive Brokers account username
- `IB_PASSWORD` - Interactive Brokers account password
- `TRADING_MODE` - Either `paper` or `live`

### Optional
- `IBGW_PORT` - Gateway port (default: 4002)
- `JAVA_HEAP_SIZE` - JVM heap size in MB (default: 768)
- `HEALTHCHECK_API_ENABLE` - Enable REST API health check (default: false)
- `TWOFA_TIMEOUT_ACTION` - Action on 2FA timeout (default: restart)
- `DISPLAY` - X display (default: :0, set automatically)

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
3. **Port Forwarding**: socat forwards 4001→4002 for compatibility
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
