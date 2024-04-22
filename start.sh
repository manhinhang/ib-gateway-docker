#!/bin/bash
set -e

echo "Starting Xvfb..."
rm -f /tmp/.X0-lock
/usr/bin/Xvfb "$DISPLAY" -ac -screen 0 1024x768x16 +extension RANDR >&1 &

echo "Waiting for Xvfb to be ready..."
XVFB_TIMEOUT=120
XVFB_WAITING_TIME=0
while ! xdpyinfo -display "$DISPLAY"; do
  echo -n ''
  sleep 1
  XVFB_WAITING_TIME=$(($XVFB_WAITING_TIME+1))
  echo "WAITING TIME: $XVFB_WAITING_TIME"
  if [ "$XVFB_WAITING_TIME" -gt "$XVFB_TIMEOUT" ]; then
    echo "Xvfb TIMED OUT"
    exit 1
  fi
done

echo "Xvfb is ready"
echo "Setup port forwarding..."

socat TCP-LISTEN:$IBGW_PORT,fork TCP:localhost:4001,forever >&1 &
echo "*****************************"

# python /root/bootstrap.py

# echo "IB gateway is ready."

#Define cleanup procedure
cleanup() {
    pkill java
    pkill Xvfb
    pkill socat
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
		echo "Usign default Java heap size."
	fi
}

# Java heap size
set_java_heap

# start rest api for healthcheck
healthcheck-rest >&1 &

echo "detect IB gateway version: $IBGW_VERSION"

${IBC_PATH}/scripts/ibcstart.sh "$IB_GATEWAY_VERSION" -g \
     "--ibc-path=${IBC_PATH}" "--ibc-ini=${IBC_INI}" \
     "--user=${IB_ACCOUNT}" "--pw=${IB_PASSWORD}" "--mode=${TRADING_MODE}" \
     "--on2fatimeout=${TWOFA_TIMEOUT_ACTION}"
