#!/bin/bash
set -e

echo "Starting Xvfb..."
/usr/bin/Xvfb "$DISPLAY" -ac -screen 0 1024x768x16 +extension RANDR &

echo "Waiting for Xvfb to be ready..."
while ! xdpyinfo -display "$DISPLAY"; do
  echo -n ''
  sleep 0.1
done

echo "Xvfb is ready"

socat TCP-LISTEN:$IBGW_PORT,fork TCP:localhost:4001,forever &

python /root/bootstrap.py

echo "IB gateway is ready."

$@
