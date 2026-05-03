#!/bin/bash
# Trigger IB Gateway's soft restart inside a k8s pod via IBC's command
# server on loopback. K8s analogue of scripts/restart-ib-gateway.sh.
#
# Why: a plain `kubectl delete pod` (or rollout restart) kills the JVM
# directly, which prevents IB Gateway from writing the autorestart file
# that lets the next launch skip 2FA. IBC's RESTART command runs the
# same internal codepath as the scheduled AutoRestartTime — the
# autorestart file gets written before the JVM bounces, so the new
# process reuses the session.
#
# The IBC command server is bound to 127.0.0.1 inside the pod (set via
# IBC_BIND_ADDRESS in start.sh). We reach it via `kubectl exec`, which
# preserves the loopback-only trust boundary — no Service object needed.
#
# Override via env:
#   NAMESPACE   k8s namespace                     (default: ib-gateway)
#   POD         pod name (overrides label-based discovery)
#   LABEL       label selector to find the pod    (default: app=ib-gateway)
#   PORT        IBC command server port           (default: 7462)

set -euo pipefail

NAMESPACE="${NAMESPACE:-ib-gateway}"
LABEL="${LABEL:-app=ib-gateway}"
PORT="${PORT:-${IBC_COMMAND_SERVER_PORT:-7462}}"

if [ -z "${POD:-}" ]; then
    POD="$(kubectl -n "$NAMESPACE" get pod -l "$LABEL" \
        -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || true)"
    if [ -z "$POD" ]; then
        echo "ERROR: no pod found in namespace '$NAMESPACE' with label '$LABEL'." >&2
        echo "  Set POD=<name> explicitly, or check 'kubectl -n $NAMESPACE get pods'." >&2
        exit 1
    fi
fi

echo "==> Sending IBC RESTART to pod $NAMESPACE/$POD on 127.0.0.1:$PORT..."

# We open /dev/tcp inside the pod (bash builtin) rather than using
# `kubectl port-forward` + a host-side connect: it avoids a separate
# port-forward process, and there's no advantage to going through the
# host since the command server is loopback-only by design.
kubectl exec -n "$NAMESPACE" "$POD" -- bash -c '
    set -e
    PORT="$1"
    if ! exec 3<>"/dev/tcp/127.0.0.1/$PORT" 2>/dev/null; then
        echo "ERROR: cannot connect to IBC command server at 127.0.0.1:$PORT inside pod" >&2
        echo "  - is IBC up?   (kubectl logs ...)" >&2
        echo "  - is CommandServerPort set in ibc/config.ini?" >&2
        exit 1
    fi
    printf "RESTART\n" >&3
    # 2-second per-line read timeout matches the host-side script.
    while IFS= read -t 2 -r line <&3; do
        printf "%s\n" "$line"
    done
    exec 3<&-
' _ "$PORT"

echo "==> Sent. IB Gateway will run its soft-restart cycle (~60-90s)."
echo "    Watch:   kubectl -n $NAMESPACE logs -f $POD"
echo "    Verify:  scripts/k8s/verify-session-persistence-k8s.sh"
