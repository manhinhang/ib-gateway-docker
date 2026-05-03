# IB Gateway on Kubernetes

Plain-YAML Kubernetes manifests that mirror this repo's two compose
entrypoints, plus a k3d-based local verification path.

| Manifest | Mirrors | What it deploys |
|---|---|---|
| [`single.yaml`](single.yaml) | `docker-compose.yaml` | one IB Gateway StatefulSet, one Service, one Secret, namespace `ib-gateway` |
| [`multi.yaml`](multi.yaml) | `docker-compose.multi.yaml` | paper + live StatefulSets/Services/Secrets, namespace `ib-gateway` |

## Why StatefulSet

`/root/Jts` holds the IBKR device fingerprint (and the daily autorestart
file) for one specific account. A pod must keep its PVC for life — a
fresh PVC means re-doing 2FA. StatefulSet's `volumeClaimTemplates` is
the natural fit; `replicas: 1` per gateway. See [CLAUDE.md → Session
Persistence](../../CLAUDE.md) for the underlying mechanics.

## Why the initContainer

The image bakes the IB Gateway binary into `/root/Jts/ibgateway/<version>/`.
Docker auto-seeds named volumes from the image on first mount, so the
binary "appears" inside the docker volume. **Kubernetes PVCs always
start empty**, so without intervention the mount would hide the image's
binary and `start.sh` would fail with `ls: cannot access
/root/Jts/ibgateway: No such file or directory`.

Each StatefulSet has a `seed-jts` initContainer that runs once per
pod start and `cp -rn`s the image's `/root/Jts/*` onto the PVC — first
start fills it from scratch, subsequent starts only fill gaps. This
matches docker's "auto-populate from image" semantics and preserves
the runtime state (`jts.ini`, device fingerprint, autorestart file)
that gets added later. Same caveat as docker — wipe the PVC after a
version bump in `versions.env`, otherwise the stale binary stays put.

## What's intentionally simpler than compose

`docker-compose.multi.yaml` uses `network_mode: host` and so has to give
paper and live distinct `IBGW_INTERNAL_PORT` (4011 / 4012) and
`IBC_COMMAND_SERVER_PORT` (7462 / 7463) values to keep their loopback
ports from colliding. Each k8s pod has its own network namespace, so
**none of that applies** — both pods can keep the upstream defaults
(`IBGW_INTERNAL_PORT=4001`, `IBC_COMMAND_SERVER_PORT=7462`) inside
themselves. The only thing paper and live differ on at the manifest
level is the externally-visible `IBGW_PORT` (4002 / 4001), so that
`localhost:4002` (paper) / `localhost:4001` (live) still works from
the host via `kubectl port-forward`.

## What's the same as compose

- `IB_ACCOUNT` / `IB_PASSWORD` come from a Secret (mounted as env). The
  manifest ships the Secret with `REPLACE_ME` placeholders — replace
  before the gateway can log in.
- The Java `/healthcheck/bin/healthcheck` binary is the liveness +
  readiness probe; same 60s/30s/3-retry/60s-grace timing as compose.
- IBC's command server is bound to `127.0.0.1` inside each pod and is
  **not exposed** as a Service. Loopback-only is the same trust
  boundary the docker setup enforces; reach it via `kubectl exec`.

## Quickstart on k3d

The `scripts/k8s/k3d-up.sh` helper does everything: create cluster,
build local image, import into the cluster, apply manifest, run a
smoke check.

```bash
# Default: single gateway, smoke-only (Secret stays at REPLACE_ME).
./scripts/k8s/k3d-up.sh

# Multi-gateway:
MANIFEST=examples/k8s/multi.yaml ./scripts/k8s/k3d-up.sh

# With real paper credentials — pod will go all the way to Ready:
IB_ACCOUNT=… IB_PASSWORD=… ./scripts/k8s/k3d-up.sh
```

Reach the gateway from your workstation:

```bash
kubectl -n ib-gateway port-forward svc/ib-gateway 4002:4002
# Then your IB API client connects to localhost:4002 as usual.
```

Tear down:

```bash
./scripts/k8s/k3d-down.sh
```

## Smoke vs full verification

`k3d-up.sh` is a **smoke** test by default. Pass criteria:

- PVC is `Bound`
- Pod reaches `Running` (image pulls, container starts)
- `start.sh` runs Xvfb, IBC begins the login attempt
- Required env vars are wired into the container (`IBGW_PORT`,
  `TRADING_MODE`, `IB_ACCOUNT` set)

Without real IBKR credentials the pod stays in `Running` but never
reaches `Ready` — IBC can't log in, so the `/healthcheck/bin/healthcheck`
probe keeps failing. That's the right stopping point for "is the k8s
wiring correct?".

For the **full** verification — same contract as the existing
[`scripts/verify-session-persistence.sh`](../../scripts/verify-session-persistence.sh):

```bash
# 1. Put real paper credentials into the Secret (or pass them to k3d-up.sh).
kubectl -n ib-gateway create secret generic ib-gateway \
    --from-literal=IB_ACCOUNT="$IB_ACCOUNT" \
    --from-literal=IB_PASSWORD="$IB_PASSWORD" \
    --dry-run=client -o yaml | kubectl apply -f -
kubectl -n ib-gateway rollout restart statefulset/ib-gateway

# 2. Complete 2FA on the IBKR mobile app on this first start.
kubectl -n ib-gateway wait --for=condition=ready pod/ib-gateway-0 --timeout=300s

# 3. Run the k8s-native session-persistence check.
./scripts/k8s/verify-session-persistence-k8s.sh
```

## Soft restart from the host

`scripts/k8s/restart-ib-gateway-k8s.sh` is the k8s analogue of
`scripts/restart-ib-gateway.sh`. It `kubectl exec`s into the pod and
sends `RESTART\n` to IBC's command server on `127.0.0.1:7462` — the
**same** loopback path the docker script uses, just reached via
`kubectl exec` instead of bash redirection on the host. This preserves
the loopback-only trust boundary; nothing in the cluster network can
reach the command server.

```bash
# Defaults: namespace=ib-gateway, label app=ib-gateway, port=7462
./scripts/k8s/restart-ib-gateway-k8s.sh

# Multi: target a specific pod
POD=ib-gateway-paper-0 ./scripts/k8s/restart-ib-gateway-k8s.sh
POD=ib-gateway-live-0  ./scripts/k8s/restart-ib-gateway-k8s.sh
```

## If k3d can't reach Docker Hub

Some hosts have flaky outbound DNS on docker's default bridge network
(the same issue `docker-compose.yaml` documents with `network: host`
on builds). Symptom: k3s system pods stuck in `ErrImagePull` /
`ImagePullBackOff` with `TLS handshake timeout` to `auth.docker.io` or
`registry-1.docker.io`. Two fixes:

### Preferred: host networking

Run k3d on the host network so the k3s server container shares the
host's `/etc/resolv.conf`. If `docker pull` works on the host, this
makes containerd inside k3s work too:

```bash
USE_HOST_NETWORK=1 ./scripts/k8s/k3d-up.sh
```

Caveat: k3d's prep step inspects every container on the host network,
and bails with `ParseAddr("")` if any of them have no IP set
(common with long-running runners like `act`). If the cluster fails to
create with that error, list the offenders with
`docker network inspect host --format '{{json .Containers}}'` and
either stop them or use the fallback below.

### Fallback: pre-pull and ctr-import

When host networking isn't available, pre-pull the k3s system images
on the host and import them via `ctr`:

```bash
for img in rancher/mirrored-pause:3.6 \
           rancher/local-path-provisioner:v0.0.30 \
           rancher/mirrored-coredns-coredns:1.11.3 \
           rancher/mirrored-metrics-server:v0.7.2 \
           rancher/klipper-helm:v0.9.3-build20241008 \
           rancher/mirrored-library-busybox:1.36.1 \
           rancher/mirrored-library-traefik:2.11.10 \
           rancher/klipper-lb:v0.4.9; do
    docker pull "$img"
done
docker save rancher/mirrored-pause:3.6 \
            rancher/local-path-provisioner:v0.0.30 \
            rancher/mirrored-coredns-coredns:1.11.3 \
            rancher/mirrored-metrics-server:v0.7.2 \
            rancher/klipper-helm:v0.9.3-build20241008 \
            rancher/mirrored-library-busybox:1.36.1 \
            rancher/mirrored-library-traefik:2.11.10 \
            rancher/klipper-lb:v0.4.9 \
    -o /tmp/k3s.tar
docker cp /tmp/k3s.tar k3d-ib-gateway-server-0:/tmp/k3s.tar
docker exec k3d-ib-gateway-server-0 ctr -n=k8s.io image import /tmp/k3s.tar
```

The exact tags depend on the k3d / k3s versions in use — check
`kubectl -n kube-system get pods -o jsonpath='{range .items[*]}{.spec.containers[*].image}{"\n"}{end}'`
on a fresh cluster to see what your version pulls. `k3d image import`
itself is unreliable for the kube-system images on some k3d versions
(imports land in the wrong containerd namespace); going through `ctr`
directly avoids that. The application image
(`manhinhang/ib-gateway-docker:dev`) that `k3d-up.sh` imports works
fine via `k3d image import`.

## Production notes (NOT covered by k3d)

What this example deliberately does **not** do, because it would either
not work the same on k3d or would distract from the core mapping:

- **NetworkPolicy** locking inbound to `IBGW_PORT` only — recommended
  for shared clusters.
- **PodDisruptionBudget** — for clusters where node maintenance could
  evict the pod during a trading window.
- **External DNS / Ingress** for the API port — most setups expose the
  gateway only to other in-cluster workloads via the ClusterIP.
- **Backups** of the `jts` PVC — losing it means re-doing 2FA on the
  next start, exactly as in the docker setup.
