#!/bin/bash
# Capture the container's headless Xvfb display to a PNG, and decode any QR
# code found in it (re-rendering it in the terminal so it can be scanned).
#
# Why this exists: under Xvfb there is no way to see a modal dialog that is
# blocking login. IB Gateway will not open its API port while such a dialog
# is up, so the healthcheck just hangs with no indication of what is on
# screen. This gives you the actual pixels.
#
# Primary use is diagnosis: seeing *which* dialog is blocking login (2FA
# prompt, "insert your security key", exchange agreement, version notice...).
# Pair it with the IBC dialog logging knobs:
#     IBC_LOG_STRUCTURE_SCOPE=all IBC_LOG_STRUCTURE_WHEN=activate
#
# ── On passkey QR codes, read this before relying on it ──
# This script decodes and re-renders a QR code if one is on screen — scanning
# the root window *and* every child window, since a passkey ceremony renders
# its QR inside a dialog that never appears in a root capture. But whether a QR
# appears at all, and whether scanning it can complete the login, depends on
# Bluetooth:
#
#   - IB Gateway renders passkey (WebAuthn) ceremonies in an embedded
#     Chromium (JxBrowser). Chromium only offers the "use a phone or tablet"
#     QR option when a Bluetooth adapter is *present and powered* — see
#     device/fido/cable/v2_discovery.cc, which aborts discovery when
#     BluetoothAdapter::IsPresent() is false. With no BLE radio reachable, no
#     QR is generated at all and the dialog offers only the USB security-key
#     path. To give the container a radio, build with
#     --build-arg ENABLE_PASSKEY=true and run with
#     docker-compose.passkey.yaml (mounts the host D-Bus so Chromium reaches
#     the host's BlueZ).
#   - Even with a QR, the code carries only key material. The phone must then
#     broadcast a BLE advertisement that *this host* receives (Chromium
#     decrypts the 20-byte advert against the QR-derived key to match the
#     tunnel). That proximity requirement (~10m) is the anti-phishing
#     property of caBLE, not an implementation gap — relaying a QR to a
#     remote device is precisely what it is designed to prevent.
#
# So on a host with no Bluetooth hardware, expect "No QR code found" — that is
# the correct result, not a failure of this script.
#
# IB Key (IBKR Mobile push) needs none of this and works headlessly.
#
# SECURITY: the captured image may show your account number, username, or
# other account details from the login screen. Treat the PNG like a
# credential: it is written with owner-only permissions, and you should
# delete it when done rather than pasting it into an issue unredacted.
#
# Usage:
#   ./scripts/capture-screen.sh                      # -> ./ib-gateway-screen.png
#   ./scripts/capture-screen.sh /tmp/shot.png        # explicit output path
#   CONTAINER=my-gw ./scripts/capture-screen.sh      # target a raw container
#
# Override via env: COMPOSE_FILE, SERVICE, PROFILE, CONTAINER, DISPLAY_OVERRIDE.
#
# Exit codes: 0 = captured, 1 = capture failed, 2 = misuse / preconditions.

set -euo pipefail

OUT="${1:-ib-gateway-screen.png}"
COMPOSE_FILE="${COMPOSE_FILE:-docker-compose.yaml}"
SERVICE="${SERVICE:-ib-gateway}"
PROFILE="${PROFILE:-}"

# Scratch file for container stderr. mktemp (not a fixed /tmp path) so a
# pre-existing file or symlink cannot be clobbered or read by another user.
errf="$(mktemp "${TMPDIR:-/tmp}/capture-screen.XXXXXX")"
cleanup() { rm -f "$errf"; }
trap cleanup EXIT INT TERM

compose() {
    if [ -n "$PROFILE" ]; then
        docker compose -f "$COMPOSE_FILE" --profile "$PROFILE" "$@"
    else
        docker compose -f "$COMPOSE_FILE" "$@"
    fi
}

# Resolve the target container: explicit CONTAINER wins, else ask compose.
if [ -n "${CONTAINER:-}" ]; then
    cid="$CONTAINER"
    if ! docker inspect "$cid" >/dev/null 2>&1; then
        echo "FAIL: no such container: $cid" >&2
        exit 2
    fi
else
    if ! cid="$(compose ps -q "$SERVICE" 2>/dev/null)" || [ -z "$cid" ]; then
        echo "FAIL: no running container for service '$SERVICE' in $COMPOSE_FILE" >&2
        echo "  Bring it up first, or point at a container: CONTAINER=<name|id> $0" >&2
        exit 2
    fi
fi

# The compose file sets DISPLAY=:99 to avoid colliding with a host X server
# on :0 under host networking, so read it from the container rather than
# assuming the image default.
if [ -n "${DISPLAY_OVERRIDE:-}" ]; then
    disp="$DISPLAY_OVERRIDE"
else
    disp="$(docker exec "$cid" printenv DISPLAY 2>/dev/null || true)"
    [ -n "$disp" ] || disp=":0"
fi

echo "Capturing display $disp from container ${cid:0:12}..."

# List every mapped window with a name, so a dialog blocking login is visible
# even when the root capture does not show it.
#
# Why this matters: under Xvfb there is no window manager and no compositing,
# so `xwd -root` captures only the root window's own contents — child dialogs
# are NOT composited into it and come out blank. Dialogs must be captured by
# window id. (Swing also often fails to repaint offscreen windows, so a
# per-window capture can still be an empty frame; the window *list* is then
# the reliable signal, and IBC's own dialog logging is authoritative —
# see IBC_LOG_STRUCTURE_SCOPE / IBC_LOG_STRUCTURE_WHEN.)
echo "Windows currently mapped on $disp:"
docker exec "$cid" sh -c "
    export DISPLAY='$disp'
    for w in \$(xdotool search --name '.' 2>/dev/null); do
        n=\$(xdotool getwindowname \"\$w\" 2>/dev/null) || continue
        [ -n \"\$n\" ] || continue
        g=\$(xdotool getwindowgeometry \"\$w\" 2>/dev/null | tr '\n' ' ' | tr -s ' ')
        printf '  win=%s name=\"%s\" | %s\n' \"\$w\" \"\$n\" \"\$g\"
    done" 2>/dev/null || echo "  (window list unavailable)"

# Capture inside the container and convert there, so the host needs no X
# tooling. xwd grabs the root window; ImageMagick converts to PNG on stdout.
# `docker exec` without -t keeps stdout a clean binary stream.
#
# Create the file with owner-only perms *before* writing: the screenshot can
# contain account details, and a default-umask file would be world-readable.
umask 077
: > "$OUT"
if ! docker exec "$cid" sh -c \
        "xwd -root -silent -display '$disp' | convert xwd:- png:-" \
        > "$OUT" 2>"$errf"; then
    echo "FAIL: capture failed. Error from container:" >&2
    sed 's/^/  /' "$errf" >&2
    rm -f "$OUT"
    echo >&2
    echo "  If this says 'xwd: not found' or 'convert: not found', the image" >&2
    echo "  predates this helper — rebuild it so x11-apps and imagemagick are" >&2
    echo "  installed:  docker compose build" >&2
    exit 1
fi

if [ ! -s "$OUT" ]; then
    echo "FAIL: capture produced an empty file (is Xvfb running on $disp?)" >&2
    rm -f "$OUT"
    exit 1
fi

echo "Wrote $OUT ($(wc -c < "$OUT") bytes)"

# Also capture each named top-level window by id. The root capture above
# misses dialogs entirely (no compositing under Xvfb), and a blocking dialog
# is exactly what you are usually looking for. Skip the tiny helper windows
# the JVM creates (FocusProxy, XIconWindow, 1x1 probes).
base="${OUT%.png}"
# Accumulates "<wid>\t<name>" per successfully captured window, so the QR scan
# below can re-scan exactly those windows.
window_shots=""
ids="$(docker exec "$cid" sh -c "
    export DISPLAY='$disp'
    for w in \$(xdotool search --name '.' 2>/dev/null); do
        n=\$(xdotool getwindowname \"\$w\" 2>/dev/null) || continue
        case \"\$n\" in
            ''|FocusProxy|*XIconWindow*|*FocusProxy*) continue ;;
        esac
        printf '%s\n' \"\$w\"
    done" 2>/dev/null || true)"

for wid in $ids; do
    wname="$(docker exec "$cid" sh -c \
        "DISPLAY='$disp' xdotool getwindowname '$wid' 2>/dev/null" || true)"
    # Sanitise the window name into a filename fragment. Include the window id
    # so same-named windows (the JVM creates several "Content window"s) do not
    # overwrite each other.
    slug="$(printf '%s' "$wname" | tr -cs 'A-Za-z0-9._-' '-' | sed 's/^-*//; s/-*$//')"
    [ -n "$slug" ] || slug="win"
    wout="${base}.${slug}.${wid}.png"
    : > "$wout"
    if docker exec "$cid" sh -c \
            "xwd -id '$wid' -silent -display '$disp' | convert xwd:- png:-" \
            > "$wout" 2>/dev/null && [ -s "$wout" ]; then
        echo "  wrote $wout ($(wc -c < "$wout") bytes) — \"$wname\""
        window_shots="${window_shots}${wid}"$'\t'"${wname}"$'\n'
    else
        rm -f "$wout"
    fi
done

# Decode any QR code. Scan the root window AND every captured child window:
# a QR shown by a dialog (which is where a passkey ceremony renders it) never
# appears in the root capture, because Xvfb has no window manager and so does
# no compositing. Scanning root only would report "no QR found" while a QR was
# plainly on screen.
qr=""
qr_src=""
scan_window() {
    # $1 = window id ("root" for the root window), $2 = human label
    local target="$1" label="$2" out
    if [ "$target" = "root" ]; then
        out="$(docker exec "$cid" sh -c \
            "xwd -root -silent -display '$disp' | convert xwd:- png:- | zbarimg --raw -q - 2>/dev/null" \
            || true)"
    else
        out="$(docker exec "$cid" sh -c \
            "xwd -id '$target' -silent -display '$disp' | convert xwd:- png:- | zbarimg --raw -q - 2>/dev/null" \
            || true)"
    fi
    # zbarimg exits 4 when it finds nothing, which is the common case and not
    # an error — hence the `|| true` above and the emptiness check here.
    if [ -n "$out" ]; then
        qr="$out"
        qr_src="$label"
        return 0
    fi
    return 1
}

scan_window root "root window" || true
if [ -z "$qr" ]; then
    while IFS="$(printf '\t')" read -r swid sname; do
        [ -n "$swid" ] || continue
        if scan_window "$swid" "window \"$sname\""; then
            break
        fi
    done <<EOF
$window_shots
EOF
fi

if [ -n "$qr" ]; then
    echo
    echo "Decoded QR payload (found in ${qr_src}):"
    printf '%s\n' "$qr" | sed 's/^/  /'
    echo
    # Re-render so it can be scanned directly from the terminal. Same payload,
    # freshly encoded — for a FIDO caBLE payload (starts FIDO:/) note the BLE
    # caveat in this script's header: scanning is necessary but not sufficient.
    if command -v qrencode >/dev/null 2>&1; then
        printf '%s' "$qr" | qrencode -t ANSIUTF8
    else
        echo "(install qrencode on this host to re-render it as a scannable QR)"
    fi
    case "$qr" in
        FIDO:/*)
            echo
            echo "NOTE: this is a FIDO caBLE (passkey) payload. Scanning it is not"
            echo "      enough — your phone must also reach this host over Bluetooth"
            echo "      LE, which a container without a BLE radio cannot do. See the"
            echo "      comments at the top of this script."
            ;;
    esac
else
    echo "No QR code found in the capture."
fi

echo
echo "View it:      xdg-open $OUT"
echo "Dialog logs:  set IBC_LOG_STRUCTURE_SCOPE=all and IBC_LOG_STRUCTURE_WHEN=activate,"
echo "              then: docker logs ${cid:0:12} | grep -i 'detected dialog'"
echo "Delete when done — the image may contain account details."
