#!/bin/bash
# Delete the local k3d cluster created by k3d-up.sh.
#
# This wipes everything in the cluster — PVCs, Secrets, the lot.
# The local `manhinhang/ib-gateway-docker:dev` image stays in the host
# Docker daemon (k3d image import only copies it into the cluster).

set -euo pipefail

CLUSTER_NAME="${CLUSTER_NAME:-ib-gateway}"

if k3d cluster list "$CLUSTER_NAME" >/dev/null 2>&1; then
    echo "==> Deleting k3d cluster '$CLUSTER_NAME'..."
    k3d cluster delete "$CLUSTER_NAME"
else
    echo "==> No k3d cluster '$CLUSTER_NAME' to delete."
fi
