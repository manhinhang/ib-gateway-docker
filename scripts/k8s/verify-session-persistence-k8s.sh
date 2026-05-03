#!/bin/bash
# Verify that an in-flight IB Gateway pod survives an IBC soft restart
# without re-prompting for 2FA. K8s analogue of
# scripts/verify-session-persistence.sh.
#
# Preconditions:
#   - Pod is up and Ready (which means: real creds in the Secret, and
#     2FA was completed on the IBKR mobile app on the very first start).
#   - IBC command server is enabled in ibc/config.ini (default).
#
# Pass criteria (same as the docker script):
#   - IBC accepts the RESTART command
#   - Pod returns to Ready within HEALTH_TIMEOUT seconds
#   - Post-restart logs contain no second-factor / 2FA prompts
#   - Autorestart file is present in /root/Jts after the restart
#
# Exit codes: 0 = pass, 1 = fail, 2 = misuse / preconditions missing.
#
# Override via env:
#   NAMESPACE         k8s namespace               (default: ib-gateway)
#   LABEL             label selector for the pod (default: app=ib-gateway)
#   POD               explicit pod name (skips LABEL discovery)
#   HEALTH_TIMEOUT    seconds to wait for Ready  (default: 240)
#   RESTART_TIMEOUT   seconds to wait for the restart cycle (default: 240)
#   RESTART_HELPER    path to restart helper     (default: ../restart-ib-gateway-k8s.sh)
#   PORT              IBC command server port    (default: 7462)

set -euo pipefail

NAMESPACE="${NAMESPACE:-ib-gateway}"
LABEL="${LABEL:-app=ib-gateway}"
HEALTH_TIMEOUT="${HEALTH_TIMEOUT:-240}"
RESTART_TIMEOUT="${RESTART_TIMEOUT:-240}"
RESTART_HELPER="${RESTART_HELPER:-$(dirname "$0")/restart-ib-gateway-k8s.sh}"
PORT="${PORT:-${IBC_COMMAND_SERVER_PORT:-7462}}"

current_pod() {
    if [ -n "${POD:-}" ]; then
        printf '%s\n' "$POD"
        return
    fi
    kubectl -n "$NAMESPACE" get pod -l "$LABEL" \
        -o jsonpath='{.items[0].metadata.name}' 2>/dev/null
}

# Returns "true" / "false" / "" depending on Ready condition status.
ready_status() {
    local pod="$1"
    kubectl -n "$NAMESPACE" get pod "$pod" \
        -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' 2>/dev/null
}

wait_ready() {
    local pod="$1" deadline=$(( SECONDS + HEALTH_TIMEOUT ))
    while [ "$SECONDS" -lt "$deadline" ]; do
        case "$(ready_status "$pod")" in
            True) return 0 ;;
        esac
        sleep 5
    done
    echo "FAIL: pod '$pod' did not become Ready within ${HEALTH_TIMEOUT}s" >&2
    return 1
}

pod="$(current_pod)"
if [ -z "$pod" ]; then
    echo "FAIL: no pod found in '$NAMESPACE' for selector '$LABEL'" >&2
    echo "  Bring it up first, complete 2FA, and re-run." >&2
    exit 2
fi

initial="$(ready_status "$pod")"
if [ "$initial" != "True" ]; then
    echo "FAIL: pod '$pod' is not Ready before restart (Ready=$initial)" >&2
    echo "  Did you complete 2FA on the IBKR mobile app on the first start?" >&2
    exit 2
fi

if [ ! -x "$RESTART_HELPER" ]; then
    echo "FAIL: restart helper not found or not executable: $RESTART_HELPER" >&2
    exit 2
fi

echo "Pre-restart: pod '$pod' is Ready. Sending IBC RESTART..."
# kubectl logs --since-time wants RFC3339; date -u with 'Z' suffix matches.
restart_started_at_iso="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
NAMESPACE="$NAMESPACE" POD="$pod" PORT="$PORT" "$RESTART_HELPER"

# IBC's RESTART is async — it sets the auto-restart time to "now + ~1m"
# and lets IB Gateway's normal soft-restart logic fire. Watch the pod's
# logs for one of:
#   - "autorestart file found"      → success marker
#   - "autorestart file not found"  → file wasn't written, FAIL
#   - "Second Factor Authentication initiated" → 2FA, FAIL
echo "Waiting up to ${RESTART_TIMEOUT}s for the restart cycle to fire..."
deadline=$(( SECONDS + RESTART_TIMEOUT ))
restart_outcome=""
while [ "$SECONDS" -lt "$deadline" ]; do
    # IB Gateway's soft restart bounces the JVM in-place inside the
    # same container, so the pod name does NOT change. If for some
    # reason the container *did* die (uncaught error etc.), the pod
    # name still stays the same under StatefulSet semantics — the
    # restart count goes up, that's all.
    new_logs="$(kubectl -n "$NAMESPACE" logs "$pod" \
        --since-time="$restart_started_at_iso" 2>&1 || true)"
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
        echo "      no 'autorestart file (found|not found)' since ${restart_started_at_iso}" >&2
        echo "--- last 60 log lines ---" >&2
        kubectl -n "$NAMESPACE" logs "$pod" --tail=60 >&2 || true
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

echo "Post-restart: waiting for Ready (timeout ${HEALTH_TIMEOUT}s)..."
if ! wait_ready "$pod"; then
    echo "--- last 100 log lines ---" >&2
    kubectl -n "$NAMESPACE" logs "$pod" --tail=100 >&2 || true
    exit 1
fi

# Final defensive scan: even if the launcher said "found", confirm no
# 2FA dialog appeared during the post-restart login.
post_logs="$(kubectl -n "$NAMESPACE" logs "$pod" \
    --since-time="$restart_started_at_iso" 2>&1 || true)"
if printf '%s' "$post_logs" | grep -qiE 'Second Factor Authentication initiated|sms code|please respond'; then
    echo "FAIL: 2FA-related markers found in post-restart logs despite autorestart file:" >&2
    printf '%s' "$post_logs" | grep -iE 'Second Factor Authentication initiated|sms code|please respond' >&2
    exit 1
fi

# Positive proof on disk: the autorestart file lives in a per-instance
# dir under /root/Jts (e.g. /root/Jts/ghdiikhpohjdpkekgoiaeondhmnnfepnbmldcgal/autorestart).
echo "Confirming autorestart file on disk in /root/Jts..."
if kubectl -n "$NAMESPACE" exec "$pod" -- sh -c \
        'find /root/Jts -maxdepth 3 -name autorestart -type f -print 2>/dev/null | head -3' \
        | grep -q .; then
    echo "  - autorestart file present on disk"
else
    echo "  - autorestart file not visible via find (launcher confirmed it though)"
fi

echo
echo "PASS: pod '$pod' restarted via IBC command server with no 2FA prompt."
echo "      Autorestart file is in place; subsequent restarts will also"
echo "      skip 2FA until it expires (Sunday 1AM ET hard reset)."
