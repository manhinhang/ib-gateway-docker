######## Downloader ########
FROM debian:bookworm-slim AS downloader

ARG CHANNEL=latest

# set environment variables
ENV IBC_VERSION_JSON_URL="https://api.github.com/repos/IbcAlpha/IBC/releases" \
    IBC_INI=/root/ibc/config.ini \
    IBC_PATH=/opt/ibc

# install dependencies (single layer, single update, lists cleared)
RUN apt-get update \
 && apt-get upgrade -y \
 && apt-get install -y wget unzip jq curl \
 && rm -rf /var/lib/apt/lists/*

# download IB TWS. IB ships native per-arch Linux installers; pick the one
# matching the build target. TARGETARCH is set automatically by buildx
# (amd64/arm64); fall back to the host arch for a plain `docker build`.
ARG TARGETARCH
RUN ARCH="${TARGETARCH:-$(dpkg --print-architecture)}" \
 && case "$ARCH" in \
      arm64) IB_INSTALLER_ARCH=linux-arm ;; \
      amd64) IB_INSTALLER_ARCH=linux-x64 ;; \
      *) echo "Unsupported architecture: $ARCH" >&2; exit 1 ;; \
    esac \
 && IB_URL="https://download2.interactivebrokers.com/installers/ibgateway/${CHANNEL}-standalone/ibgateway-${CHANNEL}-standalone-${IB_INSTALLER_ARCH}.sh" \
 && wget -q -O /tmp/ibgw.sh "$IB_URL" \
      || { echo "ERROR: could not download IB Gateway installer from $IB_URL" >&2; \
           echo "       IB may have stopped publishing the '${IB_INSTALLER_ARCH}' build for channel '${CHANNEL}'." >&2; \
           exit 1; } \
 && chmod +x /tmp/ibgw.sh

# download IBC. -f makes curl fail loudly on HTTP errors instead of piping
# the error body into jq and producing a confusing parse error.
RUN IBC_ASSET_URL=$(curl -fsSL ${IBC_VERSION_JSON_URL} | jq -r '.[0].assets[]|select(.name | test("IBCLinux*")).browser_download_url') \
 && wget -q -O /tmp/IBC.zip ${IBC_ASSET_URL} \
 && unzip /tmp/IBC.zip -d ${IBC_PATH} \
 && chmod +x ${IBC_PATH}/*.sh ${IBC_PATH}/*/*.sh

# copy IBC/Jts configs
COPY ibc/config.ini ${IBC_INI}

# Extract IB Gateway version. version.json is JSONP (callback-wrapped),
# e.g. `ibgatewaylatest_callback({"buildVersion":"10.46.1d",...});`.
# Strip the callback wrapper before piping to jq.
RUN curl -fsSL "https://download2.interactivebrokers.com/installers/ibgateway/${CHANNEL}-standalone/version.json" \
 | sed -E 's/^[^(]+\(//; s/\);[[:space:]]*$//' \
 | jq -r '.buildVersion' > /tmp/ibgw-version

# Resolve the matching TWS API zip URL. IB routinely ships a new
# gateway minor before publishing the matching twsapi_macunix.NN.01.zip
# on github.io, so probe the exact derived URL and walk back through
# earlier minors of the same major until one resolves. The result is
# persisted to /tmp/ibgw-api-url for the healthcheck-tools stage,
# which uses gradle:8.7.0-jdk17 and doesn't ship curl.
RUN IB_VER=$(cat /tmp/ibgw-version) \
 && MAJOR=$(echo "$IB_VER" | cut -d. -f1) \
 && MINOR=$(echo "$IB_VER" | cut -d. -f2) \
 && IB_API_URL="" \
 && for offset in $(seq 0 10); do \
      candidate=$((MINOR - offset)); \
      [ "$candidate" -lt 0 ] && break; \
      URL="https://interactivebrokers.github.io/downloads/twsapi_macunix.${MAJOR}${candidate}.01.zip"; \
      if curl -fsIL -o /dev/null "$URL"; then \
        echo "resolved IBAPI URL: $URL"; \
        IB_API_URL="$URL"; \
        break; \
      fi; \
      echo "  miss: $URL"; \
    done \
 && if [ -z "$IB_API_URL" ]; then \
      echo "ERROR: no twsapi_macunix.${MAJOR}NN.01.zip found within 10 minors of ${IB_VER}" >&2; \
      exit 1; \
    fi \
 && echo "$IB_API_URL" > /tmp/ibgw-api-url

######## healthcheck tools ########
# temp container to build using gradle
FROM gradle:8.7.0-jdk17 AS healthcheck-tools
ENV APP_HOME=/usr/app/
WORKDIR $APP_HOME
COPY healthcheck $APP_HOME
COPY --from=downloader /tmp/ibgw-version /tmp/ibgw-version
COPY --from=downloader /tmp/ibgw-api-url /tmp/ibgw-api-url

# Use the IBAPI URL resolved in the downloader stage (which probed
# github.io for the closest available twsapi_macunix.NN.01.zip to the
# installed gateway version).
RUN IB_API_URL=$(cat /tmp/ibgw-api-url) && \
    gradle clean build -PibApiUrl=$IB_API_URL

RUN mkdir -p $APP_HOME/build

RUN unzip healthcheck/build/distributions/healthcheck.zip -d $APP_HOME/build
RUN unzip healthcheck-rest/build/distributions/healthcheck-rest-boot.zip -d $APP_HOME/build

######## FINAL ########

FROM debian:bookworm-slim

# install dependencies (single layer, lists cleared)
RUN apt-get update \
 && apt-get upgrade -y \
 && apt-get install -y \
    xvfb \
    libxtst6 \
    libxrender1 \
    net-tools \
    x11-utils \
    socat \
    procps \
    xterm \
    xdotool \
    openjdk-17-jre \
 && rm -rf /var/lib/apt/lists/*

# set environment variables
ENV TWS_INSTALL_LOG=/root/Jts/tws_install.log \
    IBC_INI=/root/ibc/config.ini \
    IBC_PATH=/opt/ibc \
    TWS_PATH=/root/Jts \
    TWOFA_TIMEOUT_ACTION=restart

# make dirs
RUN mkdir -p /tmp && mkdir -p ${IBC_PATH} && mkdir -p ${TWS_PATH} && mkdir -p /healthcheck

# download IB TWS
COPY --from=downloader /tmp/ibgw.sh /tmp/ibgw.sh
COPY --from=downloader /tmp/ibgw-version /tmp/ibgw-version
# Install IB Gateway from the native per-arch installer downloaded above.
# The installer bundles its own JRE — which ships JavaFX and the native libs
# IB Gateway's UI needs — under <install-dir>/jre. IB Gateway must run on that
# bundled JRE (the system openjdk-17-jre lacks JavaFX, so the login dialog
# never renders). But the installer records the JRE path in
# .install4j/inst_jre.cfg as its temp self-extraction dir
# (/tmp/ibgw.sh.<n>.dir/jre), which is deleted after the build — leaving IBC
# unable to locate java at runtime. Rewrite the cfg to point at the real
# bundled JRE so IBC resolves it. (Same fix as the upstream gnzsnz image.)
RUN IB_GATEWAY_VERSION=$(cat /tmp/ibgw-version) && \
    /tmp/ibgw.sh -q -dir /root/Jts/ibgateway/${IB_GATEWAY_VERSION} && \
    echo "/root/Jts/ibgateway/${IB_GATEWAY_VERSION}/jre" \
      > "/root/Jts/ibgateway/${IB_GATEWAY_VERSION}/.install4j/inst_jre.cfg"
# remove files
RUN rm /tmp/ibgw.sh
RUN rm /tmp/ibgw-version

COPY --from=downloader /opt/ibc /opt/ibc
COPY --from=downloader /root/ibc /root/ibc

# install healthcheck tool
COPY --from=healthcheck-tools /usr/app/build/healthcheck /healthcheck
ENV PATH="${PATH}:/healthcheck/bin"

COPY --from=healthcheck-tools /usr/app/build/healthcheck-rest-boot /healthcheck-rest
ENV PATH="${PATH}:/healthcheck-rest/bin"

# copy cmd script
WORKDIR /root
COPY start.sh /root/start.sh
RUN chmod +x /root/start.sh

# set display environment variable (must be set after TWS installation)
ENV DISPLAY=:0

ENV IBGW_PORT=4002 \
    JAVA_HEAP_SIZE=768 \
    HEALTHCHECK_API_ENABLE=false \
    IBC_AUTO_RESTART_TIME="11:00 AM" \
    IBC_COMMAND_SERVER_PORT=7462 \
    IBC_BIND_ADDRESS=127.0.0.1

EXPOSE $IBGW_PORT

# Run as non-root. Use /root as $HOME so IBC's TWS_SETTINGS_PATH (derived
# from $HOME/Jts) lands where TWS was installed during the build. Pre-create
# /tmp/.X11-unix with 1777 perms because Xvfb's transport refuses to mkdir
# it when euid != 0.
RUN useradd -u 1000 -d /root -s /bin/bash ibgw \
 && chown -R ibgw:ibgw /root /opt/ibc /healthcheck /healthcheck-rest \
 && chmod 755 /root \
 && mkdir -p /tmp/.X11-unix \
 && chmod 1777 /tmp/.X11-unix
USER ibgw

ENTRYPOINT [ "/root/start.sh" ]
