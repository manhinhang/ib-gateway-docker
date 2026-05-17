#!/bin/bash
# CI helper — log IB Gateway off its IBKR session before the container or
# pod running it is destroyed.
#
# Why this exists: the build-test matrix runs the functional suite once per
# architecture against ONE shared IB paper account, and IB Gateway permits
# a single login session per account. A container/pod that is hard-killed
# (`docker rm -f`, `k3d cluster delete`) never logs off, so IB keeps the
# session marked active — and the next matrix leg's login is then rejected
# (`ExistingSessionDetectedAction=primary` -> "exit code=1112" restart loop).
#
# IBC's STOP command shuts IB Gateway down via its normal File>Exit
# codepath, which logs the session off cleanly. Same /dev/tcp technique as
# scripts/restart-ib-gateway.sh, but STOP instead of RESTART. The command
# server is loopback-only inside the container, so we reach it via
# `docker exec` / `kubectl exec` — CI containers run on the default bridge
# network, so port 7462 is not published to the runner.
#
# Usage:
#   scripts/ci/graceful-stop.sh docker <container-id-or-name>
#   scripts/ci/graceful-stop.sh k8s    <pod-name>
#
# Env overrides:
#   IBC_COMMAND_SERVER_PORT   IBC command server port   (default: 7462)
#   NAMESPACE                 k8s namespace (k8s mode)  (default: ib-gateway)
#
# Best-effort by design: connection failures are swallowed so teardown
# never fails the build — a missed STOP only spends the cooldown's margin.

set -uo pipefail

MODE="${1:-}"
TARGET="${2:-}"
PORT="${IBC_COMMAND_SERVER_PORT:-7462}"
NAMESPACE="${NAMESPACE:-ib-gateway}"

if [ -z "$MODE" ] || [ -z "$TARGET" ]; then
    echo "usage: $0 <docker|k8s> <container-or-pod>" >&2
    exit 1
fi

# Runs inside the container/pod: open the IBC command server on loopback,
# send STOP, echo whatever IBC replies (banner/ack vary by config), close.
# Mirrors the read loop in scripts/restart-ib-gateway.sh.
remote_stop='
    PORT="$1"
    if ! exec 3<>"/dev/tcp/127.0.0.1/$PORT" 2>/dev/null; then
        echo "graceful-stop: IBC command server not reachable on 127.0.0.1:$PORT" >&2
        exit 0
    fi
    printf "STOP\n" >&3
    while IFS= read -t 2 -r line <&3; do
        printf "%s\n" "$line"
    done
    exec 3<&-
'

echo "==> Sending IBC STOP to $MODE target '$TARGET' on 127.0.0.1:$PORT..."

case "$MODE" in
    docker)
        docker exec "$TARGET" bash -c "$remote_stop" _ "$PORT" || true
        ;;
    k8s)
        kubectl exec -n "$NAMESPACE" "$TARGET" -- bash -c "$remote_stop" _ "$PORT" || true
        ;;
    *)
        echo "graceful-stop: unknown mode '$MODE' (want 'docker' or 'k8s')" >&2
        exit 1
        ;;
esac

echo "==> STOP sent — IB Gateway will log off and exit."
