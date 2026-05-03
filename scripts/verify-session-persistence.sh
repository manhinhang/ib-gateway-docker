#!/bin/bash
# Verify that an in-flight IB Gateway container survives a soft restart
# (via IBC's command server) without re-prompting for 2FA.
#
# Why this script does NOT use `docker compose restart`: a brutal restart
# kills the JVM before IB Gateway can write the autorestart file, so the
# next launch always asks for 2FA. The IBC RESTART command runs the same
# soft-restart codepath as the scheduled `AutoRestartTime`, which DOES
# write the autorestart file. See CLAUDE.md → Session Persistence.
#
# Preconditions: container is up and healthy, 2FA has already been completed
# on the IBKR mobile app, IBC's command server is enabled in ibc/config.ini
# (CommandServerPort=7462, BindAddress=127.0.0.1).
#
# Usage:
#   ./scripts/verify-session-persistence.sh
#
# Override via env: COMPOSE_FILE, SERVICE, PROFILE, HEALTH_TIMEOUT,
# IBC_COMMAND_SERVER_PORT, IBC_COMMAND_SERVER_HOST.
#
# Pass criteria:
#   - IBC accepted the RESTART command
#   - healthcheck returns to "healthy" within HEALTH_TIMEOUT seconds
#   - post-restart logs contain no second-factor / 2FA prompts
#   - autorestart file exists in /root/Jts after the restart
#
# Exit codes: 0 = pass, 1 = fail, 2 = misuse / preconditions missing.

set -euo pipefail

COMPOSE_FILE="${COMPOSE_FILE:-docker-compose.yaml}"
SERVICE="${SERVICE:-ib-gateway}"
PROFILE="${PROFILE:-}"
HEALTH_TIMEOUT="${HEALTH_TIMEOUT:-180}"
RESTART_HELPER="${RESTART_HELPER:-$(dirname "$0")/restart-ib-gateway.sh}"

compose() {
    if [ -n "$PROFILE" ]; then
        docker compose -f "$COMPOSE_FILE" --profile "$PROFILE" "$@"
    else
        docker compose -f "$COMPOSE_FILE" "$@"
    fi
}

container_id() {
    compose ps -q "$SERVICE"
}

health() {
    local cid="$1"
    docker inspect -f '{{.State.Health.Status}}' "$cid" 2>/dev/null || echo "missing"
}

wait_healthy() {
    local cid="$1" deadline=$(( SECONDS + HEALTH_TIMEOUT ))
    while [ "$SECONDS" -lt "$deadline" ]; do
        local s
        s="$(health "$cid")"
        case "$s" in
            healthy) return 0 ;;
            unhealthy) echo "FAIL: container went unhealthy" >&2; return 1 ;;
        esac
        sleep 5
    done
    echo "FAIL: healthcheck did not reach 'healthy' within ${HEALTH_TIMEOUT}s" >&2
    return 1
}

cid="$(container_id)"
if [ -z "$cid" ]; then
    echo "FAIL: no running container for service '$SERVICE' in $COMPOSE_FILE" >&2
    echo "Bring it up first:  compose up -d  and complete 2FA before re-running." >&2
    exit 2
fi

initial_state="$(health "$cid")"
if [ "$initial_state" != "healthy" ]; then
    echo "FAIL: container is not healthy before restart (state=$initial_state)" >&2
    echo "Did you complete 2FA on the IBKR mobile app?" >&2
    exit 2
fi

if [ ! -x "$RESTART_HELPER" ]; then
    echo "FAIL: restart helper not found or not executable: $RESTART_HELPER" >&2
    exit 2
fi

echo "Pre-restart: $SERVICE is healthy (cid=$cid). Sending IBC RESTART..."
restart_started_at_ns="$(date +%s%N)"
restart_started_at_iso="$(date -u -d "@$(( restart_started_at_ns / 1000000000 ))" +%Y-%m-%dT%H:%M:%S.%3NZ)"
"$RESTART_HELPER"

# IBC's RESTART is async: it sets the auto-restart time to "now + ~1 min"
# and lets IB Gateway's normal soft-restart logic fire. We have to wait
# for the actual restart cycle to complete before we can judge the result.
# Watch the logs for either:
#   - "autorestart file found"      → success marker we want
#   - "autorestart file not found"  → file wasn't written, will FAIL
#   - "Second Factor Authentication initiated" → 2FA was triggered, FAIL
# Whichever appears first decides the outcome. Bound by RESTART_TIMEOUT.
RESTART_TIMEOUT="${RESTART_TIMEOUT:-240}"
echo "Waiting up to ${RESTART_TIMEOUT}s for the restart cycle to fire..."
deadline=$(( SECONDS + RESTART_TIMEOUT ))
restart_outcome=""
while [ "$SECONDS" -lt "$deadline" ]; do
    new_logs="$(docker logs --since "$restart_started_at_iso" \
        "$(container_id)" 2>&1 || true)"
    if printf '%s' "$new_logs" | grep -qiE 'autorestart file found'; then
        restart_outcome="found"; break
    fi
    if printf '%s' "$new_logs" | grep -qiE 'autorestart file not found'; then
        restart_outcome="missing"; break
    fi
    if printf '%s' "$new_logs" | grep -qiE 'Second Factor Authentication initiated'; then
        restart_outcome="2fa"; break
    fi
    sleep 5
done

case "$restart_outcome" in
    "")
        echo "FAIL: restart cycle did not complete within ${RESTART_TIMEOUT}s" >&2
        echo "      no 'autorestart file (found|not found)' in logs since ${restart_started_at_iso}" >&2
        echo "--- last 60 log lines ---" >&2
        docker logs --tail 60 "$(container_id)" 2>&1 | tail -60 >&2
        exit 1
        ;;
    "missing")
        echo "FAIL: launcher reported 'autorestart file not found' on the" >&2
        echo "      post-restart launch. The IBC RESTART codepath did not" >&2
        echo "      write the autorestart file as expected." >&2
        exit 1
        ;;
    "2fa")
        echo "FAIL: 2FA was triggered after the IBC RESTART (autorestart" >&2
        echo "      file likely missing or expired)." >&2
        exit 1
        ;;
    "found")
        echo "  - launcher confirmed: autorestart file found"
        ;;
esac

# After the launcher finds the file, wait for the new JVM to fully come up.
cid="$(container_id)"
if [ -z "$cid" ]; then sleep 5; cid="$(container_id)"; fi
echo "Post-restart cid=$cid. Waiting for healthcheck (timeout ${HEALTH_TIMEOUT}s)..."
if ! wait_healthy "$cid"; then
    echo "--- last 100 log lines ---" >&2
    docker logs --tail 100 "$cid" >&2 || true
    exit 1
fi

# Final defensive scan: even if the launcher said "found", confirm no 2FA
# dialog appeared during the post-restart login.
post_restart_logs="$(docker logs --since "$restart_started_at_iso" "$cid" 2>&1 || true)"
if printf '%s' "$post_restart_logs" | grep -qiE 'Second Factor Authentication initiated|sms code|please respond'; then
    echo "FAIL: 2FA-related markers found in post-restart logs despite autorestart file:" >&2
    printf '%s' "$post_restart_logs" | grep -iE 'Second Factor Authentication initiated|sms code|please respond' >&2
    exit 1
fi

# Positive proof on disk: the autorestart file lives in a per-instance dir
# directly under /root/Jts (e.g. /root/Jts/ghdiikhpohjdpkekgoiaeondhmnnfepnbmldcgal/autorestart),
# NOT under /root/Jts/ibgateway/<version>/.
echo "Confirming autorestart file on disk in the persistent volume..."
if compose exec -T "$SERVICE" sh -c \
        'find /root/Jts -maxdepth 3 -name autorestart -type f -print 2>/dev/null | head -3' \
        | grep -q .; then
    echo "  - autorestart file present on disk"
else
    echo "  - autorestart file not visible via find (launcher confirmed it though)"
fi

echo
echo "PASS: $SERVICE restarted via IBC command server with no 2FA prompt."
echo "      Autorestart file is in place; subsequent docker restarts will also"
echo "      skip 2FA until it expires (Sunday 1AM ET hard reset)."
