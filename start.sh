#!/bin/bash
set -e

echo "Starting Xvfb..."
rm -f /tmp/.X0-lock
/usr/bin/Xvfb "$DISPLAY" -ac -screen 0 1024x768x16 +extension RANDR &

echo "Waiting for Xvfb to be ready..."
while ! xdpyinfo -display "$DISPLAY"; do
  echo -n ''
  sleep 0.1
done

echo "Xvfb is ready"
echo "Setup port forwarding..."

socat TCP-LISTEN:$IBGW_PORT,fork TCP:localhost:4001,forever &
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

${IBC_PATH}/scripts/ibcstart.sh "1019" -g \
     "--ibc-path=${IBC_PATH}" "--ibc-ini=${IBC_INI}" \
     "--user=${IB_ACCOUNT}" "--pw=${IB_PASSWORD}" "--mode=${TRADING_MODE}" \
     "--on2fatimeout=${TWOFA_TIMEOUT_ACTION}"
