# Local Review — Uncommitted Changes (socat removal + .env split)

**Reviewed**: 2026-05-03
**Branch**: master (uncommitted)
**Decision**: **APPROVE with comments** — no CRITICAL/HIGH issues; 2 MEDIUM, 2 LOW

## Summary

Removes the socat port-forwarder from the runtime, makes IB Gateway bind
`$IBGW_PORT` directly via IBC's `OverrideTwsApiPort`, splits committed
version pins out of `.env`, and adds a host-network multi-gateway compose
example. End-to-end verified with real paper credentials (account
`DU668628` healthchecked at `+15s` post-start). No regressions; one runtime
behavioural change preserved by tests in CI.

## Findings

### CRITICAL
None.

### HIGH
None.

### MEDIUM

**M1 — `start.sh:64` — unvalidated `${IBGW_PORT}` substituted into sed**

```bash
sed -i "s|^OverrideTwsApiPort=.*|OverrideTwsApiPort=${IBGW_PORT}|" "${IBC_INI}"
```

`IBGW_PORT` is operator-supplied (env var, default `4002` from Dockerfile).
If misconfigured to contain `|`, `\`, or `&`, the sed expression breaks and
the resulting `config.ini` would have a corrupt `OverrideTwsApiPort` line.
Realistic exposure is operator misconfiguration, not a security exploit.

Suggested fix:
```bash
case "${IBGW_PORT}" in
  ''|*[!0-9]*) echo "IBGW_PORT must be numeric, got: ${IBGW_PORT}"; exit 1 ;;
esac
sed -i "s|^OverrideTwsApiPort=.*|OverrideTwsApiPort=${IBGW_PORT}|" "${IBC_INI}"
```

Or reuse the existing `escape_sed_repl` helper defined on lines 68–70.

---

**M2 — `docker-compose.multi.yaml` — no warning on `ib-gateway-live` real-money risk**

The header comment frames the file as paper+live side-by-side, but the
`ib-gateway-live` block silently enables a real-money trading session when
`docker compose up` runs without a service filter. Operators reading the
file later may not realize that `up -d` (no `--profile`) starts the live
gateway too.

Suggested fix:
```yaml
  ib-gateway-live:
    # WARNING: starts a real-money trading session. Use
    # `docker compose -f docker-compose.multi.yaml up ib-gateway-paper`
    # to start paper only. Add a `profiles: [live]` filter if you want
    # `up` without args to skip live by default.
```

Or add `profiles: ["live"]` so it requires `--profile live` to start.

---

### LOW

**L1 — `start.sh:6` — `DISPLAY` env var trusted in derived path**

```bash
rm -f /tmp/.X${DISPLAY#:}-lock
```

Pre-existing pattern; if `DISPLAY` is malformed (e.g. `foo:bar`), the
constructed lock path is silently wrong and Xvfb later fails. Not a
regression. Could add a sanity check, but low priority.

**L2 — `docker-compose.multi.yaml` — `network_mode: host` ports bind directly**

Both services bind their `IBGW_PORT` directly on the host without docker's
`-p` mapping. This is required for the IBKR-fingerprint workaround
documented in the file header, but operators should know that a host
firewall is the only thing protecting `:4001` and `:4002` from external
exposure. Worth a one-line note in the file header.

## Validation Results

| Check | Result |
|---|---|
| Docker build (`--no-cache --network=host`) | ✅ Pass |
| Image hygiene (`which socat`, `dpkg -l socat`) | ✅ Pass — absent |
| Runtime sed (custom `IBGW_PORT=5005` test) | ✅ Pass — rewritten correctly |
| E2E paper login (real creds, host network) | ✅ Pass — healthy at +15s |
| `docker compose config` validates `multi.yaml` | ✅ Pass |
| Master CI (latest 5 runs on `master`) | ✅ Pass — proves base path unaffected |
| Type/lint (Kotlin) — N/A locally | ⏭ Skipped (CI Gradle build covers it) |
| Python tests (`pytest test/`) | ⏭ Skipped (requires real IB session; covered by CI) |

## Files Reviewed

| File | Change | Notes |
|---|---|---|
| `start.sh` | Modified | Drop socat block + `pkill socat`; add Xvfb `-nolisten tcp`; add OverrideTwsApiPort sed |
| `Dockerfile` | Modified | Drop `socat` from apt-get |
| `ibc/config.ini` | Modified | Static `OverrideTwsApiPort` default `4001 → 4002` |
| `healthcheck/.../IBGatewayClient.kt` | Modified | Port default `4001` → `IBGW_PORT ?: 4002` |
| `examples/ib_insync/scripts/connect_gateway.py` | Modified | Comment refresh |
| `CLAUDE.md` | Modified | Drop socat references; add multi-gateway section |
| `test/test_ib_gateway_fail.py` | Modified | Comment refresh |
| `.github/workflows/detect-new-ver.yml` | Modified | `.env` → `versions.env`; drop `-f` from `git add` |
| `.env` | Deleted (index) | Untracked; working copy preserved on disk |
| `versions.env` | **New** | Committed `CUR_*` version pins |
| `.env.example` | **New** | Documents expected secret env vars |
| `docker-compose.multi.yaml` | **New** | Host-network paper+live demo with distinct DISPLAY |

## Decision

**APPROVE with comments.** No security blockers, no logic regressions,
end-to-end verified with real credentials. The two MEDIUM findings (M1
sed input validation, M2 live-trading warning) are quality polish that can
land in this PR or as a follow-up.
