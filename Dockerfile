######## Downloader ########
FROM debian:bookworm-slim as downloader

ARG CHANNEL=latest

# set environment variables
ENV IBC_VERSION_JSON_URL="https://api.github.com/repos/IbcAlpha/IBC/releases"
ENV IBC_INI=/root/ibc/config.ini \
    IBC_PATH=/opt/ibc

# install dependencies
RUN  apt-get update \
  && apt-get upgrade -y \
  && apt-get install -y wget \
  unzip
RUN apt install -y jq curl

# make dirs
RUN mkdir -p /tmp

# download IB TWS
RUN wget -q -O /tmp/ibgw.sh https://download2.interactivebrokers.com/installers/ibgateway/${CHANNEL}-standalone/ibgateway-${CHANNEL}-standalone-linux-x64.sh
RUN chmod +x /tmp/ibgw.sh

# download IBC
RUN IBC_ASSET_URL=$(curl ${IBC_VERSION_JSON_URL} | jq -r '.[0].assets[]|select(.name | test("IBCLinux*")).browser_download_url') && \
wget -q -O /tmp/IBC.zip ${IBC_ASSET_URL}
RUN unzip /tmp/IBC.zip -d ${IBC_PATH}
RUN chmod +x ${IBC_PATH}/*.sh ${IBC_PATH}/*/*.sh

# copy IBC/Jts configs
COPY ibc/config.ini ${IBC_INI}

# Extract IB Gateway version
RUN curl "https://download2.interactivebrokers.com/installers/ibgateway/${CHANNEL}-standalone/version.json" | \
grep -Po '"buildVersion"\s*:\s*"\K[^"]+' | \
head -1 > /tmp/ibgw-version

######## healthcheck tools ########
# temp container to build using gradle
FROM gradle:8.7.0-jdk17 AS healthcheck-tools
ENV APP_HOME=/usr/app/
WORKDIR $APP_HOME
COPY healthcheck $APP_HOME
COPY --from=downloader /tmp/ibgw-version /tmp/ibgw-version

# Derive IBAPI URL from gateway version (e.g., 10.45.1c → twsapi_macunix.1045.01.zip)
RUN IB_VER=$(cat /tmp/ibgw-version) && \
    MAJOR=$(echo $IB_VER | cut -d. -f1) && \
    MINOR=$(echo $IB_VER | cut -d. -f2) && \
    IB_API_URL="https://interactivebrokers.github.io/downloads/twsapi_macunix.${MAJOR}${MINOR}.01.zip" && \
    gradle clean build -PibApiUrl=$IB_API_URL

RUN mkdir -p $APP_HOME/build

RUN unzip healthcheck/build/distributions/healthcheck.zip -d $APP_HOME/build
RUN unzip healthcheck-rest/build/distributions/healthcheck-rest-boot.zip -d $APP_HOME/build

######## FINAL ########

FROM debian:bookworm-slim

# install dependencies
RUN  apt-get update \
  && apt-get upgrade -y \
  && apt-get install -y \
  xvfb \
  libxtst6 \
  libxrender1 \
  net-tools \
  x11-utils \
  socat \
  procps \
  xterm
RUN apt install -y openjdk-17-jre

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
RUN IB_GATEWAY_VERSION=$(cat /tmp/ibgw-version) && \
/tmp/ibgw.sh -q -dir /root/Jts/ibgateway/${IB_GATEWAY_VERSION}
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

ENV IBGW_PORT 4002
ENV JAVA_HEAP_SIZE 768
ENV HEALTHCHECK_API_ENABLE=false

EXPOSE $IBGW_PORT

# Run as non-root. /root remains the working tree (TWS_PATH, IBC_INI, start.sh
# all live there) but is now owned by the ibgw user. /tmp keeps its standard
# 1777 mode so Xvfb can manage its lock files.
RUN useradd -u 1000 -m -s /bin/bash ibgw \
 && chown -R ibgw:ibgw /root /opt/ibc /healthcheck /healthcheck-rest \
 && chmod 755 /root
USER ibgw

ENTRYPOINT [ "/root/start.sh" ]
