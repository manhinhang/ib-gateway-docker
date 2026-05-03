# Full Codebase Review — ib-gateway-docker

**Reviewed**: 2026-05-03
**Reviewer**: Claude (Opus 4.7)
**Mode**: Local review (working tree clean — review covers all authored code at HEAD `3c7bf43`)
**Scope**: ~25 authored files. Vendored Interactive Brokers Java SDK under `healthcheck/healthcheck/src/main/java/com/ib/**` (~250K LOC) is **excluded** as third-party.
**Decision**: **REQUEST CHANGES** — no CRITICAL findings, but 12 HIGH-severity issues, several with security or financial-safety implications, plus effectively 0% unit-test coverage.

---

## Summary

| Severity | Count |
|---|---|
| CRITICAL | 0 |
| HIGH | 12 |
| MEDIUM | 20 |
| LOW | 10 |

### Top 5 must-fix (in order)

1. **`AllowBlindTrading=yes` in `ibc/config.ini:682`** — auto-confirms orders for contracts with no market-data subscription. This is a financial-safety override that the user almost certainly does not want as the default for a generic image.
2. **Deploy workflow publishes Docker Hub `latest` from any non-feature branch** (`.github/workflows/deploy.yml:6-9`). A stray push to a `wip-foo` branch will overwrite the `latest` tag.
3. **Container runs as root** — no `USER` directive in `Dockerfile`; the IB Gateway and the Spring Boot REST endpoint both run as UID 0.
4. **IB account password leaks via `ps`** — `start.sh:73` passes `--pw=${IB_PASSWORD}` as a CLI arg; `procps` is installed in the image so any process inside the container can read it.
5. **Healthcheck REST API is unauthenticated and connection-amplifying** (`HttpControllers.kt:19-26`) — every `GET /healthcheck` opens a fresh TWS API socket. Combined with port `8080:8080` exposed in `docker-compose.yaml`, an attacker who reaches the port can DoS the gateway.

---

## CRITICAL

None.

---

## HIGH

### H1 — `AllowBlindTrading=yes` defaults
**File**: `ibc/config.ini:682`
**Issue**: This auto-dismisses TWS's "you have no market data subscription for this contract — are you sure?" warning by clicking OK. It is a deliberate financial-safety guardrail in TWS. Setting it to `yes` as a baked-in default in a publicly published image means every user of `manhinhang/ib-gateway-docker` inherits this behavior, often unknowingly.
**Fix**: Change to `AllowBlindTrading=no` and document that users who need it can override via a custom `config.ini` mount. Alternatively, parameterize via env var (`ALLOW_BLIND_TRADING`) and `sed`-substitute in `start.sh`.

### H2 — Deploy workflow branch filter is a footgun
**File**: `.github/workflows/deploy.yml:6-9`
```yaml
branches:
  - '*'
  - '!feature/**'
  - '!hotfix/**'
  - '!bugfix/**'
```
**Issue**: This pushes to Docker Hub with the `latest` / `stable` tag for **any** branch name not matching the three excluded prefixes. A push to `wip`, `experiment-foo`, `tmp`, etc. publishes to Docker Hub `latest`, which downstream users pull. Combined with `tags: type=raw,value=${{ matrix.channel }}` on line 40, the consequences are silent.
**Fix**: Replace with an allow-list — `branches: [master]` (or `[master, develop]` if both should publish). Use distinct tag suffixes for non-master.

### H3 — Container runs as root
**File**: `Dockerfile` (entire final stage, lines 61-120) — and `Dockerfile.template:32-94`
**Issue**: No `USER` directive. The IB Gateway, IBC, the Spring Boot healthcheck-rest service, socat, and Xvfb all run as UID 0. Container escapes from any of these become root on the host.
**Fix**: Add a non-root user in the final stage:
```dockerfile
RUN useradd -u 1000 -m -s /bin/bash ibgw \
 && chown -R ibgw:ibgw /root /opt/ibc /healthcheck /healthcheck-rest
USER ibgw
WORKDIR /home/ibgw
```
Note: this requires moving `/root/Jts`, `/root/ibc`, and `/root/start.sh` to `/home/ibgw/` — non-trivial but worth it.

### H4 — IB password visible to in-container `ps`
**File**: `start.sh:73`
```bash
${IBC_PATH}/scripts/ibcstart.sh "$IB_GATEWAY_VERSION" -g \
     "--ibc-path=${IBC_PATH}" "--ibc-ini=${IBC_INI}" \
     "--user=${IB_ACCOUNT}" "--pw=${IB_PASSWORD}" "--mode=${TRADING_MODE}" \
     ...
```
**Issue**: Command-line args are visible in `/proc/<pid>/cmdline` to anyone in the same PID namespace. `procps` is installed (`Dockerfile:73`), so `docker exec <id> ps -ef` reveals the password. Also visible in any `docker top <id>` output.
**Fix**: IBC supports reading credentials from the `config.ini` (`IbLoginId` / `IbPassword`). At container startup, write them into the ini from envs and run IBC without the `--user`/`--pw` flags:
```bash
sed -i "s|^IbLoginId=.*|IbLoginId=${IB_ACCOUNT}|" "${IBC_INI}"
sed -i "s|^IbPassword=.*|IbPassword=${IB_PASSWORD}|" "${IBC_INI}"
```
Better still: use a temporary credentials file with `chmod 600` and clear it after IBC reads it.

### H5 — Healthcheck REST has no auth and amplifies connections
**File**: `healthcheck/healthcheck-rest/src/main/kotlin/.../HttpControllers.kt:19-26`
**Issue**: `GET /healthcheck` calls `ibClient.ping()` which opens a fresh `EClientSocket` to the gateway. There is no auth, no rate limiting, and `docker-compose.yaml:5-6` and `test/test_ib_gateway.py:38` expose port 8080 directly. An external attacker who reaches port 8080 can:
1. Confirm the gateway is up (information disclosure).
2. Burn TWS API client-id slots (TWS limits ~32 concurrent clients) by spamming, DoSing legitimate traders.
3. Cause `EClientSocket.eConnect` thrash that can make the gateway flap.
**Fix**: At minimum, bind the healthcheck server to `127.0.0.1` or to the Docker bridge only — never expose 8080 to the host without authentication. Add a basic shared-secret header check (env-supplied). Consider replacing the deep healthcheck with a cheaper readiness probe that just verifies the IBC log file has reached a known state.

### H6 — `actions/checkout@master` unpinned
**Files**: `.github/workflows/build-test.yml:20`, `.github/workflows/deploy.yml:33`, `.github/workflows/detect-new-ver.yml:16`
**Issue**: `@master` is a moving reference. Supply-chain risk: a compromise of `actions/checkout`'s default branch is immediately consumed. GitHub's own guidance recommends pinning to a tagged release (`@v4`) or, better, a SHA.
**Fix**: Replace all three with `actions/checkout@v4` (or pin the SHA: `actions/checkout@<full-sha> # v4.x.y`). Also pin `actions/setup-python@v5`, `docker/build-push-action@v5`, `docker/login-action@v3`, `docker/metadata-action@v5` consistently — most are already on tagged versions, just `@master` needs fixing.

### H7 — `requests.get` without timeouts
**Files**: `scripts/detect_ib_gateway_ver.py:8`, `scripts/detect_ibc_ver.py:6`
**Issue**: `requests.get(url)` with no `timeout=` parameter blocks indefinitely if the remote hangs. In CI this consumes the whole 6-hour Actions timeout.
**Fix**: Pass `timeout=10` (or similar) to every `requests.get` call. Also call `response.raise_for_status()` to fail loudly on HTTP 4xx/5xx instead of silently parsing HTML as JSON.

### H8 — `Wrapper.kt` silently swallows all IB callbacks
**File**: `healthcheck/healthcheck/src/main/kotlin/.../Wrapper.kt` (committed) and `healthcheck/healthcheck/generate-wrapper.sh:99` generates `override fun ${name}(...) {}` for every `EWrapper` method, including `error(...)`.
**Issue**: `EWrapper.error(int id, int errorCode, String errorMsg, ...)` is how the IB Gateway reports authentication failures, market-data permission errors, and all server-side problems. Currently every callback is a no-op `{}`, so `IBGatewayClient.ping()` will report success (TCP `eConnect` returns OK) even when the gateway later sends an error indicating credentials are wrong or the API is closed. The healthcheck is effectively a "TCP socket open" probe, not a "gateway is healthy" probe.
**Fix**: Have the generator produce a real `error(...)` override that records the last error onto a thread-safe field, then have `IBGatewayClient.ping()` poll/await that field for a brief window after `eConnect` and treat any `errorCode` in `(502, 504, 1100, 1101, 1102, 2110)` etc. as failure. At minimum, log received errors so the container logs surface them.

### H9 — `AppTest.kt` is an empty stub
**File**: `healthcheck/healthcheck/src/test/kotlin/.../AppTest.kt:9-13`
```kotlin
class AppTest {
    @Test fun appHasAGreeting() { }
}
```
**Issue**: The only Kotlin test is a no-op. There are no tests for `IBGatewayClient`, `Wrapper`, or `HealthcheckApiController`. The Python integration tests under `test/` exercise the Docker image end-to-end but require live IB credentials and add zero unit-level coverage. Per the repo's own `~/.claude/rules/common/testing.md` baseline, this is below 80%.
**Fix**: Add unit tests for `IBGatewayClient` using a fake/stub `EClientSocket` (extract behind an interface). Add a `MockMvc` test for `HealthcheckApiController` that injects a stub `IBGatewayClient`. Add Kover or JaCoCo to the Gradle build to surface coverage in CI.

### H10 — `ENTRYPOINT` shell vs. shebang mismatch
**File**: `Dockerfile:120` and `Dockerfile.template:94`
```dockerfile
ENTRYPOINT [ "sh", "/root/start.sh" ]
```
But `start.sh:1` is `#!/bin/bash`.
**Issue**: On Debian, `/bin/sh` is `dash`, not `bash`. The shebang is ignored when the script is invoked as `sh start.sh`. `start.sh` uses `==` (line 62), `set -e` with subshells, `[[ ]]` only in `extract_ib_gateway_major_minor.sh` (sourced separately), and `pkill` semantics that work in dash too — so it currently runs, but this is fragile. Any future edit using bashisms will break silently.
**Fix**: Either `ENTRYPOINT ["/root/start.sh"]` (relies on the +x bit and the `#!/bin/bash` shebang) or `ENTRYPOINT ["bash", "/root/start.sh"]`. Both are unambiguous.

### H11 — Build-test workflow leaks containers on failure
**File**: `.github/workflows/build-test.yml:39-66`
**Issue**: The `Verify healthcheck` step has a `for i in $(seq 1 12)` loop that does `docker rm -f $CONTAINER_ID; exit 0` only on success. On the failure path (line 56 `docker rm -f $CONTAINER_ID; exit 1`) it does clean up — that's actually fine. But the `Run ib_insync example` step at line 69 has no cleanup if `python examples/ib_insync/scripts/connect_gateway.py` fails: the `docker stop $(docker ps -a -q)` is the next line and may not execute. Also, `pytest -x` on line 63 leaves any test container running if that test crashes before its `docker rm -f` runs.
**Fix**: Wrap each step body with a `trap 'docker stop $(docker ps -a -q) || true; docker rm -f $(docker ps -a -q) || true' EXIT` or use a fixture-style cleanup step with `if: always()`. In `test/test_*.py`, move `docker rm -f` into a pytest fixture finalizer (already done in `test_ib_gateway_fail.py:31` and `test_docker_interactive.py:27`, but **not** in `test_ib_gateway.py`'s three test functions — they only clean up on the success path).

### H12 — `xdpyinfo` polling spams stderr/stdout
**File**: `start.sh:12-21`
```bash
while ! xdpyinfo -display "$DISPLAY"; do
  echo -n ''
  sleep 1
  ...
done
```
**Issue**: `xdpyinfo` writes to stdout (its display report) and stderr (error if no display) every iteration. Until Xvfb is ready, the container logs receive an `xdpyinfo: unable to open display ":0"` line every second. Plus the verbose dump of the display report once it does come up. The `echo -n ''` is a no-op (likely meant to be a placeholder). The `>&1` on `Xvfb` and `socat` lines is also a no-op (redirecting fd 1 to fd 1).
**Fix**:
```bash
while ! xdpyinfo -display "$DISPLAY" >/dev/null 2>&1; do
  sleep 1
  XVFB_WAITING_TIME=$((XVFB_WAITING_TIME+1))
  ...
done
```
Drop `echo -n ''` and the spurious `>&1` redirects.

---

## MEDIUM

### M1 — `Dockerfile.template` has drifted from `Dockerfile`
**File**: `Dockerfile.template`
**Issue**: The template lacks the **healthcheck-tools** Gradle build stage (`Dockerfile:39-57`), the IBAPI version derivation (`Dockerfile:47-52`), and the protobuf dependency. It still uses `ADD healthcheck/healthcheck/build/distributions/healthcheck.tar /` (line 75) which assumes a pre-built tar exists in the workspace. If `detect-new-ver.yml` ever re-emits a `Dockerfile` from this template, the resulting image will not build. The template is dead or stale.
**Fix**: Either delete `Dockerfile.template` (the version-detect workflow does not actually consume it — line 52-54 of `detect-new-ver.yml` only does `sed` on `README.template`), or sync the template with the current `Dockerfile` and add a CI check that asserts they stay in sync.

### M2 — `HttpControllers.kt` returns 404 on healthcheck failure
**File**: `healthcheck/healthcheck-rest/src/main/kotlin/.../HttpControllers.kt:25`
```kotlin
return ResponseEntity.status(HttpStatus.NOT_FOUND).body("Fail")
```
**Issue**: `404 Not Found` semantically means the resource doesn't exist. For a failing liveness check, `503 Service Unavailable` is the standard. `curl -f` and Docker's `--health-cmd` both treat 4xx as failure, so functionally this works, but proxies and observability tools key off the specific code.
**Fix**: `HttpStatus.SERVICE_UNAVAILABLE`.

### M3 — Bare `except:` in tests
**Files**: `test/test_ib_gateway_fail.py:38-49,57`, `test/test_docker_interactive.py:39-43,63-67`
**Issue**: `except:` (no exception class) catches `KeyboardInterrupt`, `SystemExit`, and any future-introduced exception. It also masks bugs in the test setup itself. Per `~/.claude/rules/python/coding-style.md`, this should be at least `except Exception:` and ideally narrower (`except (ConnectionError, TimeoutError):`).
**Fix**: Use `except (ConnectionError, ConnectionRefusedError, OSError):` for the IB connect retry loop. For the assertion-based "I expect this to fail" pattern, prefer `pytest.raises(...)` explicitly.

### M4 — Hardcoded sleeps in CI tests
**Files**: `test/test_ib_gateway.py:24,40,59`, `test/test_ib_gateway_fail.py:60,65`, `test/test_docker_interactive.py:34,42,63`, `.github/workflows/build-test.yml:78`
**Issue**: `time.sleep(30)` / `sleep 30` is a fragile synchronization mechanism. A slow CI runner takes >30s to start the gateway and tests fail; a fast runner wastes 25s.
**Fix**: Poll with backoff:
```python
def wait_for_healthcheck(docker_id, timeout=120):
    deadline = time.time() + timeout
    while time.time() < deadline:
        if subprocess.call(['docker', 'exec', docker_id, 'healthcheck']) == 0:
            return
        time.sleep(2)
    raise TimeoutError("Healthcheck never came up")
```

### M5 — `sed` substitutions in `detect-new-ver.yml` are not separator-safe
**File**: `.github/workflows/detect-new-ver.yml:52-54`
```bash
sed -e 's/###IB_GATEWAY_LATEST_VER###/${{...}}/' ...
```
**Issue**: If the version string ever contains a `/` (unlikely for IB Gateway versions, but possible for IBC tag names), `sed` errors with "unterminated `s' command". Same with `&` and other sed metachars.
**Fix**: Use a separator unlikely to appear (e.g., `|`) and quote the variable:
```bash
sed -e "s|###IB_GATEWAY_LATEST_VER###|${IB_GW_VER}|" ...
```
Better still, use `envsubst` or a Python templating step.

### M6 — Deprecated `ENV K V` syntax
**File**: `Dockerfile:114-116`, `Dockerfile.template:89-90`
```dockerfile
ENV IBGW_PORT 4002
ENV JAVA_HEAP_SIZE 768
```
**Issue**: Docker emits a deprecation warning for the space-separated form. The `ENV K=V` form is preferred and unambiguous when there are spaces in the value.
**Fix**:
```dockerfile
ENV IBGW_PORT=4002 \
    JAVA_HEAP_SIZE=768 \
    HEALTHCHECK_API_ENABLE=false
```

### M7 — `as` should be `AS` in `FROM` aliases
**Files**: `Dockerfile:2`, `Dockerfile:41`, `Dockerfile.template:1`
**Issue**: `FROM ... as foo` is accepted but emits a hadolint warning (DL3006-ish; specifically the "as" → "AS" warning from BuildKit since 2023).
**Fix**: `FROM debian:bookworm-slim AS downloader`.

### M8 — apt steps are split across multiple `RUN`s
**File**: `Dockerfile:12-16,64-75`
**Issue**: Each `RUN apt-get install -y ...` creates a new image layer and may use stale apt caches if `update` isn't in the same layer.
**Fix**: Combine and clean apt lists in the same `RUN`:
```dockerfile
RUN apt-get update \
 && apt-get upgrade -y \
 && apt-get install -y --no-install-recommends \
    wget unzip jq curl \
 && rm -rf /var/lib/apt/lists/*
```

### M9 — No checksum verification on downloaded installers
**File**: `Dockerfile:22-23,26-29` and the IBAPI download in `build.gradle.kts:31-40`
**Issue**: `wget -q -O /tmp/ibgw.sh https://download2.interactivebrokers.com/...sh` is consumed without integrity check. If the IB CDN is compromised or returns a tampered binary, the Docker image executes it. Same for the IBC zip from GitHub releases (mitigated by GitHub's TLS but not by content-hash verification).
**Fix**: Pin known-good SHA256 sums for each `IB_GATEWAY_VERSION` (regenerated by `detect-new-ver.yml`) and verify with `sha256sum -c`. For IBC, use the GitHub-published asset digest if available.

### M10 — `curl` calls don't use `--fail`
**Files**: `Dockerfile:26,35`, `.github/workflows/detect-new-ver.yml:20-24`
**Issue**: `curl URL | jq ...` succeeds at the curl step even on HTTP 500 — curl exits 0 but pipes the error body, jq then fails with confusing "parse error: Invalid numeric literal at line X" messages.
**Fix**: `curl -fsSL URL | jq ...` — `-f` makes curl return non-zero on HTTP errors, `-s` is silent, `-S` shows errors, `-L` follows redirects.

### M11 — Fragile JSON parsing with grep
**File**: `Dockerfile:35-37`, `.github/workflows/detect-new-ver.yml:21-23`
```dockerfile
curl ... | grep -Po '"buildVersion"\s*:\s*"\K[^"]+' | head -1
```
**Issue**: Will break if IB ever reformats the JSON or adds a `buildVersion` to a nested object. `jq` is already installed in the same image.
**Fix**: `curl -fsSL URL | jq -r '.buildVersion // .version'` (after confirming the actual JSON shape — the file appears to be `{"buildVersion":"10.45.1c"}`-ish).

### M12 — `runBlocking` on Tomcat request threads
**File**: `healthcheck/healthcheck-rest/src/main/kotlin/.../HttpControllers.kt:21`
**Issue**: Spring MVC controllers run on Tomcat worker threads. `runBlocking { ibClient.ping() }` blocks the worker for the full TWS round-trip. Acceptable for a low-traffic healthcheck (Docker probes every 60s per `docker-compose.yaml:14`), but anti-idiomatic. Per `~/.claude/rules/kotlin/patterns.md`, a Spring WebFlux `suspend fun` returning `ResponseEntity` would not block.
**Fix** (optional): Switch the module to Spring WebFlux and make the handler `suspend fun`. Otherwise, document the known blocking behavior.

### M13 — `IBGatewayClient` is a singleton across REST requests
**File**: `healthcheck/healthcheck-rest/src/main/kotlin/.../HttpControllers.kt:12`
```kotlin
val ibClient = IBGatewayClient()
```
**Issue**: The controller is a Spring singleton, so `ibClient` is shared. `EClientSocket` is not documented as thread-safe; concurrent `ping()` calls could corrupt its internal buffer state. `runBlocking` serializes within a single request thread, but Spring may invoke the handler from multiple Tomcat threads concurrently.
**Fix**: Synchronize `ping()` with a `Mutex` (`kotlinx.coroutines.sync.Mutex`) around the connect/disconnect block, or build a fresh `IBGatewayClient` per request and let JVM GC clean it up.

### M14 — `Wrapper.kt` is a generated artifact committed to VCS
**File**: `healthcheck/healthcheck/src/main/kotlin/.../Wrapper.kt`
**Issue**: `build.gradle.kts:54-62` regenerates `Wrapper.kt` from `EWrapper.java` before every `compileKotlin`. So the committed copy is overwritten on every build. Committing it means it can drift from the IBAPI version, then be silently overwritten — confusing diffs in PRs and noise in code review.
**Fix**: Add `Wrapper.kt` to `.gitignore`. Optionally add a CI step that regenerates and asserts the working tree is clean to catch wrapper-generation bugs before merge.

### M15 — `SecondFactorDevice=IB Key` is hardcoded
**File**: `ibc/config.ini:115`
**Issue**: This pre-selects "IB Key" as the 2FA device. Users with different 2FA methods (e.g., SMS, mobile) need to override. Not strictly a bug, but it's a default that surprises non-default users.
**Fix**: Make it configurable or document the override path.

### M16 — `ExistingSessionDetectedAction=primary`
**File**: `ibc/config.ini:326`
**Issue**: Setting this to `primary` means this gateway will preempt any other session for the same account. If the user logs into TWS desktop while the container is running, the desktop session will be killed (or vice versa, depending on timing). Surprising behavior; `manual` would be safer for a generic image.
**Fix**: Document this default prominently in the README, or change to `manual` and let users override to `primary`.

### M17 — Dead script: `scripts/detect_ib_gateway_ver.py`
**File**: `scripts/detect_ib_gateway_ver.py`
**Issue**: Not invoked from Dockerfile (uses inline `grep -Po` instead) nor from any workflow (`detect-new-ver.yml:20-24` also uses inline `grep -Po`). The regex `([^(]+)\)` looks designed for a JSON-with-comments format that no longer matches. Likely vestigial.
**Fix**: Either wire it into the workflow as the canonical version-detection path (preferred — it's testable Python) or delete it.

### M18 — `scripts/detect_ibc_ver.py` appends to `.env` without truncating
**File**: `scripts/detect_ibc_ver.py:14-16`
```python
with open('.env', 'a') as fp:
    fp.write(f'IBC_VER={ver}\n')
    fp.write(f'IBC_ASSET_URL={asset_url}\n')
```
**Issue**: Each invocation appends — if run twice, the file has two `IBC_VER=` lines and tools that consume `.env` (`source .env` in the workflow does this) take the last one, so it works, but the file grows unbounded.
**Fix**: Open with `'w'` to truncate, or use `python-dotenv`'s `set_key()` which updates in place.

### M19 — `scripts/extract_ib_gateway_major_minor.sh` lacks a shebang
**File**: `scripts/extract_ib_gateway_major_minor.sh:1`
**Issue**: The script uses bash-only `[[ =~ ]]` and `BASH_REMATCH`, but has no `#!/bin/bash` line. It must be sourced (since the regex sets variables in caller scope), but nothing in the repo currently sources it. Probably another vestigial file.
**Fix**: If kept, add `#!/bin/bash` and document that it must be `source`d. If unused, delete.

### M20 — `gradle.properties` missing — no `kotlin.code.style=official`
**Files**: `healthcheck/` (no gradle.properties at root or per module)
**Issue**: Per `~/.claude/rules/kotlin/coding-style.md`, projects should set `kotlin.code.style=official`. No ktlint or detekt is configured either.
**Fix**: Add `healthcheck/gradle.properties` with `kotlin.code.style=official`. Add a detekt or ktlint plugin to `build.gradle.kts` and a baseline file.

---

## LOW

### L1 — Typo "Usign" → "Using"
**File**: `start.sh:54` — `echo "Usign default Java heap size."`

### L2 — `echo -n ''` is a no-op
**File**: `start.sh:13`. Remove.

### L3 — `>&1` on background processes is a no-op
**File**: `start.sh:7,26,64` — `>&1` redirects stdout to stdout. Drop the redirect; if the intent was to ensure logs flow, that already happens.

### L4 — Trailing semicolons in Kotlin
**Files**: `IBGatewayClient.kt:20`, `HttpControllers.kt:16`. Kotlin style does not use trailing `;`.

### L5 — Redundant empty parens in Kotlin class declaration
**File**: `HttpControllers.kt:10` — `class HealthcheckApiController()` should be `class HealthcheckApiController`.

### L6 — Inconsistent indentation / missing blank line after package
**File**: `App.kt:5` — `package` and `import` lines should be separated by a blank line per Kotlin style.

### L7 — `examples/ib_insync/scripts/connect_gateway.py` uses `clientId=999`
**File**: line 5. Same as the healthcheck CLI default in `IBGatewayClient.kt:10`. If both run simultaneously, IB rejects the second. Use a different ID (e.g., 998) and/or document this collision.

### L8 — `examples/ib_insync/scripts/connect_gateway.py` connects to port 4001
**File**: line 5. The container exposes 4002 (forwards to internal 4001 via socat). Connecting from the host should use 4002. The example script as-written only works inside the container. Document or fix.

### L9 — `Dockerfile`: redundant `apt install` after `apt-get install`
**File**: `Dockerfile:16,75` — uses `apt install` (the human-friendly wrapper that prints "WARNING: apt does not have a stable CLI interface."). Use `apt-get` for both.

### L10 — `docker-compose.yaml` healthcheck has 4-space indentation under `healthcheck:` but 2-space at the parent
**File**: `docker-compose.yaml:11-16`. Cosmetic; YAML accepts it but inconsistent.

---

## Files Reviewed

| File | Status |
|---|---|
| `Dockerfile` | Reviewed (HIGH/MEDIUM findings) |
| `Dockerfile.template` | Reviewed (drift HIGH/MEDIUM) |
| `.devcontainer/Dockerfile` | Reviewed — minimal, no findings |
| `docker-compose.yaml` | Reviewed (LOW) |
| `start.sh` | Reviewed (HIGH) |
| `ibc/config.ini` | Reviewed (HIGH/MEDIUM) |
| `healthcheck/healthcheck/build.gradle.kts` | Reviewed (MEDIUM) |
| `healthcheck/healthcheck/generate-wrapper.sh` | Reviewed |
| `healthcheck/healthcheck/src/main/kotlin/.../App.kt` | Reviewed (LOW) |
| `healthcheck/healthcheck/src/main/kotlin/.../IBGatewayClient.kt` | Reviewed (HIGH/LOW) |
| `healthcheck/healthcheck/src/main/kotlin/.../Wrapper.kt` | Reviewed (HIGH H8/MEDIUM M14) |
| `healthcheck/healthcheck/src/test/kotlin/.../AppTest.kt` | Reviewed (HIGH H9) |
| `healthcheck/healthcheck-rest/build.gradle.kts` | Reviewed |
| `healthcheck/healthcheck-rest/src/main/kotlin/.../HttpControllers.kt` | Reviewed (HIGH/MEDIUM/LOW) |
| `healthcheck/healthcheck-rest/src/main/kotlin/.../Main.kt` | Reviewed |
| `healthcheck/settings.gradle.kts` | Reviewed |
| `healthcheck/gradle/libs.versions.toml` | Reviewed (MEDIUM M20) |
| `scripts/detect_ib_gateway_ver.py` | Reviewed (HIGH/MEDIUM) |
| `scripts/detect_ibc_ver.py` | Reviewed (HIGH/MEDIUM) |
| `scripts/extract_ib_gateway_major_minor.sh` | Reviewed (MEDIUM) |
| `test/test_ib_gateway.py` | Reviewed (HIGH/MEDIUM) |
| `test/test_ib_gateway_fail.py` | Reviewed (MEDIUM) |
| `test/test_docker_interactive.py` | Reviewed (MEDIUM) |
| `examples/ib_insync/scripts/connect_gateway.py` | Reviewed (LOW) |
| `.github/workflows/build-test.yml` | Reviewed (HIGH/MEDIUM) |
| `.github/workflows/deploy.yml` | Reviewed (HIGH H2/H6) |
| `.github/workflows/detect-new-ver.yml` | Reviewed (HIGH H6/MEDIUM) |

**Excluded** (vendored Interactive Brokers Java SDK — not project code):
- `healthcheck/healthcheck/src/main/java/com/ib/client/**` (~250 files)
- `healthcheck/healthcheck/src/main/java/com/ib/contracts/**`
- `healthcheck/healthcheck/src/main/java/com/ib/controller/**`

---

## Validation Results

This is a static review only — no build/test commands were executed.

| Check | Result |
|---|---|
| Type check | Skipped (Kotlin code is small; manual review sufficient) |
| Lint | Skipped (no detekt/ktlint configured — see M20) |
| Tests | Skipped (`./gradlew test` would only run the empty `appHasAGreeting` — see H9) |
| Build | Skipped (would require IB credentials and Docker image build) |
| `hadolint` | Recommended as follow-up |
| `actionlint` | Recommended as follow-up |
| `ruff` / `bandit` | Recommended as follow-up for `scripts/` and `test/` |

---

## Recommended next steps

1. Address the **Top 5 must-fix** above as a single PR.
2. Add `hadolint`, `actionlint`, `ruff`, and `detekt`/`ktlint` to a new lint job in `.github/workflows/build-test.yml`. Most of the MEDIUM findings will be caught automatically going forward.
3. Add `Wrapper.kt` to `.gitignore` and either delete `Dockerfile.template` or sync it (M1).
4. Bring unit-test coverage above 0% — at minimum, mock `EClientSocket` and test the `ping()` happy/sad paths (H9).
5. Decide a policy on `ibc/config.ini` defaults (H1, M15, M16): change the unsafe defaults to safe ones, or surface them as documented env vars.
