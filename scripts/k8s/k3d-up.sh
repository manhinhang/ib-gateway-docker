#!/bin/bash
# Stand up a local k3d cluster, build the IB Gateway image, ship it into
# the cluster, and apply the example manifests.
#
# By default this is a SMOKE test: PVCs bind, the pod schedules, the
# image pulls, the container starts, IBC begins its login attempt. The
# pod will NOT pass the healthcheck without real IBKR credentials —
# that's expected and is the right stopping point for "is the k8s wiring
# correct?". To go further (full session login + soft-restart proof),
# put real paper creds into the Secret and run
# scripts/k8s/verify-session-persistence-k8s.sh.
#
# Override via env:
#   CLUSTER_NAME   k3d cluster name              (default: ib-gateway)
#   IMAGE          local image tag               (default: manhinhang/ib-gateway-docker:dev)
#   MANIFEST       which example to apply        (default: examples/k8s/single.yaml)
#   NAMESPACE      target namespace              (default: ib-gateway)
#   IB_ACCOUNT,    IBKR creds; if both set, the
#   IB_PASSWORD    Secret is replaced with them. Otherwise REPLACE_ME stays.
#   SKIP_BUILD=1   reuse an existing local image (skips docker build)
#   USE_HOST_NETWORK=1
#                  pass --network host to k3d cluster create. This makes the
#                  k3s server container share the host's network namespace
#                  (including DNS), which fixes Docker Hub TLS handshake
#                  timeouts on hosts where the docker bridge has flaky
#                  outbound DNS. Cannot be used if the host already has
#                  containers attached to the host network without IPs
#                  (k3d's prep step rejects them) — fall back to the
#                  manual ctr-import workaround in examples/k8s/README.md
#                  in that case.

set -euo pipefail

CLUSTER_NAME="${CLUSTER_NAME:-ib-gateway}"
IMAGE="${IMAGE:-manhinhang/ib-gateway-docker:dev}"
MANIFEST="${MANIFEST:-examples/k8s/single.yaml}"
NAMESPACE="${NAMESPACE:-ib-gateway}"
SKIP_BUILD="${SKIP_BUILD:-0}"

# Resolve repo root so the script works from any directory.
REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$REPO_ROOT"

require() {
    command -v "$1" >/dev/null 2>&1 || {
        echo "ERROR: '$1' not found on PATH." >&2
        exit 2
    }
}

require docker
require kubectl
require k3d

if ! k3d cluster list "$CLUSTER_NAME" >/dev/null 2>&1; then
    echo "==> Creating k3d cluster '$CLUSTER_NAME' (no LB; we use port-forward)..."
    # --no-lb: skip the traefik LB; we use kubectl port-forward to reach
    #          the gateway from the host, so the LB is dead weight.
    # --servers 1 --agents 0: smallest viable cluster.
    create_args=(--no-lb --servers 1 --agents 0)
    if [ "${USE_HOST_NETWORK:-0}" = "1" ]; then
        echo "    USE_HOST_NETWORK=1 — joining the docker host network."
        create_args+=(--network host)
    fi
    k3d cluster create "$CLUSTER_NAME" "${create_args[@]}"
else
    echo "==> Reusing existing k3d cluster '$CLUSTER_NAME'."
fi

if [ "$SKIP_BUILD" != "1" ]; then
    echo "==> Building local image $IMAGE..."
    # network=host because the host's docker bridge has flaky DNS to
    # deb.debian.org during apt-get inside the build (same workaround
    # used by docker-compose.yaml's `network: host` build flag).
    docker build --network host -t "$IMAGE" .
else
    echo "==> SKIP_BUILD=1 — assuming $IMAGE already exists locally."
    docker image inspect "$IMAGE" >/dev/null 2>&1 || {
        echo "ERROR: $IMAGE not present locally and SKIP_BUILD=1." >&2
        exit 2
    }
fi

echo "==> Importing $IMAGE into k3d cluster '$CLUSTER_NAME'..."
k3d image import "$IMAGE" -c "$CLUSTER_NAME"

echo "==> Applying $MANIFEST..."
# Patch the image tag in the manifest on the fly so the local :dev image
# is what the StatefulSet pulls (otherwise it would request :latest from
# Docker Hub and ignore the imported one).
tmp_manifest="$(mktemp)"
trap 'rm -f "$tmp_manifest"' EXIT
# The default image in the manifest is `manhinhang/ib-gateway-docker:latest`.
# Swap to whatever IMAGE points at.
sed -E "s|image: manhinhang/ib-gateway-docker:latest|image: ${IMAGE}|g" \
    "$MANIFEST" >"$tmp_manifest"
kubectl apply -f "$tmp_manifest"

if [ -n "${IB_ACCOUNT:-}" ] && [ -n "${IB_PASSWORD:-}" ]; then
    echo "==> Replacing Secret with IB_ACCOUNT/IB_PASSWORD from environment..."
    if [ "$MANIFEST" = "examples/k8s/multi.yaml" ]; then
        # Multi-file lookup: prefer paper creds for the paper Secret if
        # the *_PAPER env vars are set; otherwise fall through to the
        # generic IB_ACCOUNT/IB_PASSWORD.
        paper_account="${IB_PAPER_ACCOUNT:-$IB_ACCOUNT}"
        paper_password="${IB_PAPER_PASSWORD:-$IB_PASSWORD}"
        kubectl -n "$NAMESPACE" create secret generic ib-gateway-paper \
            --from-literal=IB_ACCOUNT="$paper_account" \
            --from-literal=IB_PASSWORD="$paper_password" \
            --dry-run=client -o yaml | kubectl apply -f -
        if [ -n "${IB_LIVE_ACCOUNT:-}" ] && [ -n "${IB_LIVE_PASSWORD:-}" ]; then
            kubectl -n "$NAMESPACE" create secret generic ib-gateway-live \
                --from-literal=IB_ACCOUNT="$IB_LIVE_ACCOUNT" \
                --from-literal=IB_PASSWORD="$IB_LIVE_PASSWORD" \
                --dry-run=client -o yaml | kubectl apply -f -
        else
            echo "    NOTE: ib-gateway-live Secret left as REPLACE_ME (no IB_LIVE_* creds)."
        fi
    else
        kubectl -n "$NAMESPACE" create secret generic ib-gateway \
            --from-literal=IB_ACCOUNT="$IB_ACCOUNT" \
            --from-literal=IB_PASSWORD="$IB_PASSWORD" \
            --dry-run=client -o yaml | kubectl apply -f -
    fi
    # Force pods to pick up the new Secret values.
    kubectl -n "$NAMESPACE" rollout restart statefulset --selector=app=ib-gateway
else
    echo "==> No IB_ACCOUNT/IB_PASSWORD in env — Secret stays at REPLACE_ME."
    echo "    The pod will start but won't pass the healthcheck without real creds."
fi

echo "==> Waiting up to 180s for pod(s) to reach Running..."
# Running != Ready. We deliberately don't wait for Ready here because
# Ready depends on the healthcheck, which requires real credentials.
# Reaching Running means the image pulled, the container started, and
# start.sh executed at least up to the IBC login attempt.
deadline=$(( SECONDS + 180 ))
while [ "$SECONDS" -lt "$deadline" ]; do
    pods="$(kubectl -n "$NAMESPACE" get pods -l app=ib-gateway \
        -o jsonpath='{range .items[*]}{.status.phase}{"\n"}{end}' 2>/dev/null || echo)"
    if [ -n "$pods" ] && ! printf '%s\n' "$pods" | grep -vqE '^(Running|Succeeded)$'; then
        echo "    All gateway pods are Running."
        break
    fi
    sleep 5
done

echo
echo "==> Cluster state:"
kubectl -n "$NAMESPACE" get statefulset,svc,pvc,pod
echo
echo "==> Smoke verification (env wiring + image identity)..."
for pod in $(kubectl -n "$NAMESPACE" get pods -l app=ib-gateway -o name 2>/dev/null); do
    echo "--- $pod ---"
    kubectl -n "$NAMESPACE" exec "$pod" -- env 2>/dev/null \
        | grep -E '^(IBGW_|TRADING_MODE|DISPLAY|IB_ACCOUNT)=' \
        | sed -E 's/^(IB_ACCOUNT)=.*$/\1=<set>/'
done

echo
echo "Done. Useful next commands:"
echo "  kubectl -n $NAMESPACE logs -f -l app=ib-gateway"
echo "  kubectl -n $NAMESPACE port-forward svc/ib-gateway 4002:4002"
echo "  scripts/k8s/restart-ib-gateway-k8s.sh         # ad-hoc soft restart"
echo "  scripts/k8s/verify-session-persistence-k8s.sh # full proof (real creds)"
echo "  scripts/k8s/k3d-down.sh                        # tear down the cluster"
