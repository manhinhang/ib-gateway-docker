FROM debian:bookworm-slim as downloader
# IBC Version : https://github.com/IbcAlpha/IBC/releases
ARG IBC_VER="3.18.0"
ARG IBC_ASSET_URL="https://github.com/IbcAlpha/IBC/releases/download/3.18.0-Update.1/IBCLinux-3.18.0.zip"

# set environment variables
ENV IBC_INI=/root/ibc/config.ini \
    IBC_PATH=/opt/ibc

# install dependencies
RUN  apt-get update \
  && apt-get upgrade -y \
  && apt-get install -y wget \
  unzip
# make dirs
RUN mkdir -p /tmp

# download IB TWS
RUN wget -q -O /tmp/ibgw.sh https://download2.interactivebrokers.com/installers/ibgateway/stable-standalone/ibgateway-stable-standalone-linux-x64.sh
RUN chmod +x /tmp/ibgw.sh

# download IBC
RUN wget -q -O /tmp/IBC.zip ${IBC_ASSET_URL}
RUN unzip /tmp/IBC.zip -d ${IBC_PATH}
RUN chmod +x ${IBC_PATH}/*.sh ${IBC_PATH}/*/*.sh

# copy IBC/Jts configs
COPY ibc/config.ini ${IBC_INI}

FROM debian:bookworm-slim
ARG IB_GATEWAY_MAJOR="10"
ARG IB_GATEWAY_MINOR="19"

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
    TWOFA_TIMEOUT_ACTION=restart \
    IB_GATEWAY_MAJOR=${IB_GATEWAY_MAJOR} \
    IB_GATEWAY_MINOR=${IB_GATEWAY_MINOR} 

# make dirs
RUN mkdir -p /tmp && mkdir -p ${IBC_PATH} && mkdir -p ${TWS_PATH}

# download IB TWS
COPY --from=downloader /tmp/ibgw.sh /tmp/ibgw.sh

RUN /tmp/ibgw.sh -q -dir /root/Jts/ibgateway/${IB_GATEWAY_MAJOR}${IB_GATEWAY_MINOR}
# remove downloaded files
RUN rm /tmp/ibgw.sh

COPY --from=downloader /opt/ibc /opt/ibc
COPY --from=downloader /root/ibc /root/ibc

# install healthcheck tool
ADD healthcheck/healthcheck/build/distributions/healthcheck.tar /
ENV PATH="${PATH}:/healthcheck/bin"

# copy cmd script
WORKDIR /root
COPY start.sh /root/start.sh
RUN chmod +x /root/start.sh

# set display environment variable (must be set after TWS installation)
ENV DISPLAY=:0

ENV IBGW_PORT 4002

EXPOSE $IBGW_PORT

ENTRYPOINT [ "sh", "/root/start.sh" ] 