#!/bin/bash
# Trigger IB Gateway's soft restart via IBC's command server on 127.0.0.1.
#
# Why this script exists: a plain `docker compose restart` kills the JVM
# directly, which prevents IB Gateway from writing the "autorestart file"
# that lets it skip 2FA on the next launch. IBC's RESTART command runs the
# same internal codepath as the scheduled `AutoRestartTime` — IB Gateway
# writes the autorestart file before bouncing the JVM, so the new process
# (whether in-place or via `restart: unless-stopped`) reuses the session.
#
# Use this script for ad-hoc restarts, config reloads, or anything where
# you want the gateway to come back without re-prompting for 2FA.
#
# Override the port with IBC_COMMAND_SERVER_PORT if you've changed it in
# `ibc/config.ini` (default 7462, matches the IBC convention).

set -euo pipefail

PORT="${IBC_COMMAND_SERVER_PORT:-7462}"
HOST="${IBC_COMMAND_SERVER_HOST:-127.0.0.1}"

if ! exec 3<>/dev/tcp/"$HOST"/"$PORT" 2>/dev/null; then
    echo "ERROR: cannot connect to IBC command server at $HOST:$PORT" >&2
    echo "  - is the container running?  (docker compose ps)" >&2
    echo "  - is CommandServerPort set in ibc/config.ini?" >&2
    exit 1
fi

printf 'RESTART\n' >&3
# Read whatever IBC sends back (banner, ack, or nothing depending on
# CommandPrompt and SuppressInfoMessages settings). Uses bash's builtin
# `read -t` so it works on both Linux and macOS without depending on
# GNU coreutils' `timeout` being on the host PATH.
while IFS= read -t 2 -r line <&3; do
    printf '%s\n' "$line"
done
exec 3<&-

echo "Sent RESTART to IBC at $HOST:$PORT — IB Gateway is performing its soft restart."
echo "Watch logs:        docker compose logs -f ib-gateway"
echo "Wait for healthy:  docker compose ps"
