#!/bin/bash
set -e

echo "Starting Xvfb..."
rm -f /tmp/.X0-lock
/usr/bin/Xvfb "${DISPLAY}" -ac -screen 0 1024x768x16 +extension RANDR &
echo "Waiting for Xvfb to be ready..."
while ! xdpyinfo -display "${DISPLAY}"; do
  echo -n '.'
  sleep 0.1
done
echo "Xvfb is ready"

if [ -n "$VNC_SERVER_PASSWORD" ]; then
  echo "Starting VNC server"
  x11vnc -ncache_cr -display "${DISPLAY}" -forever -shared -logappend /var/log/x11vnc.log -bg -noipv6 -passwd "$VNC_SERVER_PASSWORD"
fi

echo "Setup port forwarding..."
socat TCP-LISTEN:$IBGW_PORT,fork TCP:localhost:4001,forever &

echo "*****************************"

python /root/bootstrap.py
echo "IB gateway is ready."

#Define cleanup procedure
cleanup() {
    pkill java
    pkill x11vnc
    pkill Xvfb
    pkill socat
    echo "Container stopped, performing cleanup..."
}

#Trap TERM
trap 'cleanup' INT TERM

$@
