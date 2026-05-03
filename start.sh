#!/bin/bash
set -e

echo "Starting Xvfb..."
pkill Xvfb 2>/dev/null || true
rm -f /tmp/.X${DISPLAY#:}-lock
/usr/bin/Xvfb "$DISPLAY" -ac -nolisten tcp -screen 0 1024x768x16 +extension RANDR &

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

# Pin IB Gateway's API socket to $IBGW_PORT so external clients can connect
# directly without a socat hop. config.ini ships with a static default; this
# rewrites it to whatever IBGW_PORT was set to at run time. Validate the
# value first so a misconfigured env var fails loudly instead of producing
# a corrupt config.ini line that IBC then misreads.
case "${IBGW_PORT}" in
  ''|*[!0-9]*)
    echo "IBGW_PORT must be a positive integer, got: '${IBGW_PORT}'" >&2
    exit 1
    ;;
esac
sed -i "s|^OverrideTwsApiPort=.*|OverrideTwsApiPort=${IBGW_PORT}|" "${IBC_INI}"

# Inject credentials into the IBC config so they don't appear in
# /proc/<pid>/cmdline (visible to any in-container 'ps').
escape_sed_repl() {
  printf '%s' "$1" | sed -e 's/[\\&|]/\\&/g'
}
sed -i "s|^IbLoginId=.*|IbLoginId=$(escape_sed_repl "${IB_ACCOUNT}")|" "${IBC_INI}"
sed -i "s|^IbPassword=.*|IbPassword=$(escape_sed_repl "${IB_PASSWORD}")|" "${IBC_INI}"
sed -i "s|^TradingMode=.*|TradingMode=$(escape_sed_repl "${TRADING_MODE}")|" "${IBC_INI}"
unset IB_PASSWORD

${IBC_PATH}/scripts/ibcstart.sh "$IB_GATEWAY_VERSION" -g \
     "--ibc-path=${IBC_PATH}" "--ibc-ini=${IBC_INI}" \
     "--on2fatimeout=${TWOFA_TIMEOUT_ACTION}"
