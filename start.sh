#!/bin/bash
set -e

echo "Starting Xvfb..."
pkill Xvfb 2>/dev/null || true
rm -f /tmp/.X${DISPLAY#:}-lock
/usr/bin/Xvfb "$DISPLAY" -ac -screen 0 1024x768x16 +extension RANDR &

echo "Waiting for Xvfb to be ready..."
XVFB_TIMEOUT=120
XVFB_WAITING_TIME=0
while ! xdpyinfo -display "$DISPLAY" >/dev/null 2>&1; do
  sleep 1
  XVFB_WAITING_TIME=$((XVFB_WAITING_TIME + 1))
  echo "WAITING TIME: $XVFB_WAITING_TIME"
  if [ "$XVFB_WAITING_TIME" -gt "$XVFB_TIMEOUT" ]; then
    echo "Xvfb TIMED OUT"
    exit 1
  fi
done

echo "Xvfb is ready"

#Define cleanup procedure
cleanup() {
    pkill java
    pkill Xvfb
    pkill socat 2>/dev/null
    echo "Container stopped, performing cleanup..."
}

#Trap TERM
trap 'cleanup' INT TERM
echo "IB gateway starting..."
IB_GATEWAY_VERSION=$(ls $TWS_PATH/ibgateway)

set_java_heap() {
	# set java heap size in vm options
	if [ -n "${JAVA_HEAP_SIZE}" ]; then
		_vmpath="${TWS_PATH}/ibgateway/${IB_GATEWAY_VERSION}"
		_string="s/-Xmx([0-9]+)m/-Xmx${JAVA_HEAP_SIZE}m/g"
		sed -i -E "${_string}" "${_vmpath}/ibgateway.vmoptions"
		echo "Java heap size set to ${JAVA_HEAP_SIZE}m"
	else
		echo "Using default Java heap size."
	fi
}

# Java heap size
set_java_heap

# start rest api for healthcheck
if [ "$HEALTHCHECK_API_ENABLE" = true ] ; then
  echo "starting healthcheck api..."
  healthcheck-rest &
else
  echo "Skip starting healthcheck api"
fi

echo "detect IB gateway version: $IBGW_VERSION"

# Port architecture:
#   IBGW_PORT          — external port; what clients connect to
#                        (default 4002, same as before).
#   IBGW_INTERNAL_PORT — port IB Gateway's Java actually binds, set via
#                        IBC's OverrideTwsApiPort (default 4001 — keeping
#                        IB Gateway off its mode's canonical port avoids
#                        a "Gateway" device-verification dialog that some
#                        IBKR account/region combinations show when the
#                        API server is on the canonical paper/live port).
#   socat              — forwards external → internal when they differ.
#                        For multi-container deployments under host
#                        networking, set distinct IBGW_INTERNAL_PORT per
#                        container so the forward targets do not collide.
case "${IBGW_PORT}" in
  ''|*[!0-9]*)
    echo "IBGW_PORT must be a positive integer, got: '${IBGW_PORT}'" >&2
    exit 1
    ;;
esac
IBGW_INTERNAL_PORT="${IBGW_INTERNAL_PORT:-4001}"
case "${IBGW_INTERNAL_PORT}" in
  ''|*[!0-9]*)
    echo "IBGW_INTERNAL_PORT must be a positive integer, got: '${IBGW_INTERNAL_PORT}'" >&2
    exit 1
    ;;
esac
sed -i "s|^OverrideTwsApiPort=.*|OverrideTwsApiPort=${IBGW_INTERNAL_PORT}|" "${IBC_INI}"

if [ "${IBGW_PORT}" != "${IBGW_INTERNAL_PORT}" ]; then
    echo "Setup port forwarding: ${IBGW_PORT} -> ${IBGW_INTERNAL_PORT}"
    socat TCP-LISTEN:"${IBGW_PORT}",fork,reuseaddr,keepalive,keepidle=30,keepintvl=10 \
        TCP:localhost:"${IBGW_INTERNAL_PORT}",forever &
fi

# Escape sed-replacement metacharacters before any sed-injection below.
escape_sed_repl() {
  printf '%s' "$1" | sed -e 's/[\\&|]/\\&/g'
}

# Session-persistence settings — IBC reads them from config.ini, so we
# inject the env-var values at boot rather than baking them into the
# committed config. See CLAUDE.md → Session Persistence.
case "${IBC_COMMAND_SERVER_PORT}" in
  ''|*[!0-9]*)
    echo "IBC_COMMAND_SERVER_PORT must be a non-negative integer, got: '${IBC_COMMAND_SERVER_PORT}'" >&2
    exit 1
    ;;
esac
# Refuse to start with an empty BindAddress: under network_mode: host that
# would expose IBC's command server (which accepts STOP/RESTART) on every
# host NIC. Default to 127.0.0.1; require an explicit override otherwise.
if [ -z "${IBC_BIND_ADDRESS}" ]; then
    echo "IBC_BIND_ADDRESS is empty — refusing to bind the command server to all interfaces." >&2
    echo "  Set IBC_BIND_ADDRESS=127.0.0.1 (default) or to an explicit host/IP you control." >&2
    exit 1
fi
sed -i "s|^CommandServerPort=.*|CommandServerPort=$(escape_sed_repl "${IBC_COMMAND_SERVER_PORT}")|" "${IBC_INI}"
sed -i "s|^BindAddress=.*|BindAddress=$(escape_sed_repl "${IBC_BIND_ADDRESS}")|" "${IBC_INI}"
sed -i "s|^AutoRestartTime=.*|AutoRestartTime=$(escape_sed_repl "${IBC_AUTO_RESTART_TIME}")|" "${IBC_INI}"

# Inject credentials into the IBC config so they don't appear in
# /proc/<pid>/cmdline (visible to any in-container 'ps').
sed -i "s|^IbLoginId=.*|IbLoginId=$(escape_sed_repl "${IB_ACCOUNT}")|" "${IBC_INI}"
sed -i "s|^IbPassword=.*|IbPassword=$(escape_sed_repl "${IB_PASSWORD}")|" "${IBC_INI}"
sed -i "s|^TradingMode=.*|TradingMode=$(escape_sed_repl "${TRADING_MODE}")|" "${IBC_INI}"
unset IB_PASSWORD

${IBC_PATH}/scripts/ibcstart.sh "$IB_GATEWAY_VERSION" -g \
     "--ibc-path=${IBC_PATH}" "--ibc-ini=${IBC_INI}" \
     "--on2fatimeout=${TWOFA_TIMEOUT_ACTION}"
